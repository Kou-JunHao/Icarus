/// 更新对话框组件
///
/// 显示更新信息、下载进度和安装按钮
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// 更新对话框
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final VoidCallback? onSkip;
  final VoidCallback? onDismiss;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    this.onSkip,
    this.onDismiss,
  });

  /// 显示更新对话框（底部弹窗样式）
  static Future<void> show(
    BuildContext context, {
    required UpdateInfo updateInfo,
    VoidCallback? onSkip,
    VoidCallback? onDismiss,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (context) => UpdateDialog(
        updateInfo: updateInfo,
        onSkip: onSkip,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _updateService = UpdateService();

  // 下载状态
  bool _isDownloading = false;
  bool _isDownloaded = false;
  bool _isInstalling = false;
  double _downloadProgress = 0.0;
  String? _downloadedFilePath;
  DownloadError? _downloadError;

  // 镜像源状态
  bool _mirrorsInitialized = false;
  bool _isCheckingMirrors = false;

  // 下载进度订阅
  StreamSubscription<DownloadProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _initMirrors();
    _restoreDownloadState();
    _subscribeToProgress();
  }

  /// 恢复下载状态
  void _restoreDownloadState() {
    final progress = _updateService.currentDownloadProgress;
    if (progress.version == widget.updateInfo.version) {
      switch (progress.state) {
        case DownloadState.downloading:
          _isDownloading = true;
          _downloadProgress = progress.progress;
        case DownloadState.completed:
          _isDownloaded = true;
          _downloadedFilePath = progress.filePath;
        case DownloadState.failed:
          _downloadError = progress.error;
        case DownloadState.cancelled:
          _downloadError = DownloadError.cancelled;
        case DownloadState.idle:
          break;
      }
    }
  }

  /// 订阅下载进度
  void _subscribeToProgress() {
    _progressSubscription = _updateService.downloadProgressStream.listen((
      progress,
    ) {
      if (!mounted) return;
      if (progress.version != widget.updateInfo.version) return;

      setState(() {
        switch (progress.state) {
          case DownloadState.downloading:
            _isDownloading = true;
            _isDownloaded = false;
            _downloadProgress = progress.progress;
            _downloadError = null;
          case DownloadState.completed:
            _isDownloading = false;
            _isDownloaded = true;
            _downloadedFilePath = progress.filePath;
            _downloadError = null;
          case DownloadState.failed:
            _isDownloading = false;
            _isDownloaded = false;
            _downloadError = progress.error;
          case DownloadState.cancelled:
            _isDownloading = false;
            _isDownloaded = false;
            _downloadError = DownloadError.cancelled;
          case DownloadState.idle:
            _isDownloading = false;
            _isDownloaded = false;
            _downloadProgress = 0.0;
            _downloadError = null;
            _downloadedFilePath = null;
        }
      });
    });
  }

  /// 初始化镜像源
  Future<void> _initMirrors() async {
    await _updateService.initMirrors();
    if (mounted) {
      setState(() {
        _mirrorsInitialized = true;
      });
      // 自动检测所有镜像源连通性
      _checkAllMirrors();
    }
  }

  /// 检测所有镜像源连通性
  Future<void> _checkAllMirrors() async {
    if (_isCheckingMirrors) return;
    setState(() {
      _isCheckingMirrors = true;
    });

    await _updateService.checkAllMirrorsConnectivity(
      widget.updateInfo.downloadUrl,
    );

    if (mounted) {
      setState(() {
        _isCheckingMirrors = false;
      });
    }
  }

  @override
  void dispose() {
    // 取消订阅
    _progressSubscription?.cancel();
    // 不取消下载，允许后台继续
    super.dispose();
  }

  /// 开始下载
  Future<void> _startDownload() async {
    // 状态通过 stream 自动更新
    await _updateService.downloadUpdateWithResult(
      widget.updateInfo,
      showNotification: true, // 启用通知栏进度
    );
  }

  /// 安装更新
  Future<void> _installUpdate() async {
    if (_downloadedFilePath == null) return;

    setState(() {
      _isInstalling = true;
    });

    final success = await _updateService.installUpdate(_downloadedFilePath!);

    if (!success && mounted) {
      final file = File(_downloadedFilePath!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请手动安装更新包\n路径: ${file.path}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '复制路径',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('路径已复制'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isInstalling = false;
      });
    }
  }

  /// 跳过此版本
  void _skipVersion() {
    _updateService.skipVersion(widget.updateInfo.version);
    widget.onSkip?.call();
    Navigator.of(context).pop();
  }

  /// 关闭对话框
  void _dismiss() {
    // 下载中时关闭弹窗不取消下载，允许后台继续
    widget.onDismiss?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // 固定最大高度为屏幕高度的70%
    final maxHeight = screenHeight * 0.7;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 简化的头部
          _buildHeader(theme, colorScheme),
          // 可滚动的内容区域
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildVersionInfo(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildChangelog(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildMirrorSelector(theme, colorScheme),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // 底部操作区域（固定）
          _buildActions(theme, colorScheme),
          SizedBox(height: bottomPadding + 8),
        ],
      ),
    );
  }

  /// 构建简化头部
  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          // 更新图标
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.system_update_rounded,
              size: 24,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现新版本',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'v${widget.updateInfo.version}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 关闭按钮
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: _dismiss,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建版本信息
  Widget _buildVersionInfo(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildInfoChip(
                  theme,
                  colorScheme,
                  Icons.folder_zip_outlined,
                  widget.updateInfo.formattedFileSize,
                ),
                const SizedBox(width: 16),
                _buildInfoChip(
                  theme,
                  colorScheme,
                  Icons.calendar_today_outlined,
                  _formatDate(widget.updateInfo.publishedAt),
                ),
              ],
            ),
          ),
          if (widget.updateInfo.isForceUpdate)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '重要更新',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onError,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(
    ThemeData theme,
    ColorScheme colorScheme,
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 构建更新日志
  Widget _buildChangelog(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '更新日志',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 120),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Markdown(
            data: widget.updateInfo.changelog,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            styleSheet: MarkdownStyleSheet(
              p: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: 1.5,
              ),
              h1: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              h2: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              h3: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              listBullet: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
              ),
              code: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                backgroundColor: colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              blockquoteDecoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              ),
              blockquotePadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              a: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
            onTapLink: (text, href, title) {
              if (href != null) {
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// 构建底部操作按钮
  Widget _buildActions(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 错误提示
          if (_downloadError != null) ...[
            _buildErrorCard(theme, colorScheme),
            const SizedBox(height: 12),
          ],
          _buildButtonArea(theme, colorScheme),
        ],
      ),
    );
  }

  /// 构建错误提示卡片
  Widget _buildErrorCard(ThemeData theme, ColorScheme colorScheme) {
    final errorIcon = _getErrorIcon(_downloadError!);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(errorIcon, size: 18, color: colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _downloadError!.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取错误图标
  IconData _getErrorIcon(DownloadError error) {
    switch (error) {
      case DownloadError.networkError:
      case DownloadError.timeout:
        return Icons.wifi_off_rounded;
      case DownloadError.serverError:
        return Icons.cloud_off_rounded;
      case DownloadError.storageError:
        return Icons.storage_rounded;
      case DownloadError.directoryError:
      case DownloadError.writeError:
        return Icons.folder_off_rounded;
      case DownloadError.cancelled:
        return Icons.cancel_rounded;
      case DownloadError.unknown:
        return Icons.error_outline_rounded;
    }
  }

  /// 构建按钮区域
  Widget _buildButtonArea(ThemeData theme, ColorScheme colorScheme) {
    // 下载中 - 显示进度条
    if (_isDownloading) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(_downloadProgress * 100).toInt()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '下载中，可关闭窗口后台继续',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  _updateService.cancelDownload();
                  setState(() {
                    _isDownloading = false;
                    _downloadError = DownloadError.cancelled;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('取消'),
              ),
            ],
          ),
        ],
      );
    }

    // 下载完成 - 显示安装按钮
    if (_isDownloaded) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isInstalling ? null : _installUpdate,
          icon: _isInstalling
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.onPrimary,
                    ),
                  ),
                )
              : const Icon(Icons.install_mobile_rounded, size: 20),
          label: Text(_isInstalling ? '正在启动安装...' : '立即安装'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    // 默认/错误状态 - 显示下载和跳过按钮
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _skipVersion,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('跳过'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _startDownload,
            icon: Icon(
              _downloadError != null
                  ? Icons.refresh_rounded
                  : Icons.download_rounded,
              size: 20,
            ),
            label: Text(_downloadError != null ? '重试' : '下载更新'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
  }

  /// 构建镜像源选择器
  Widget _buildMirrorSelector(ThemeData theme, ColorScheme colorScheme) {
    if (!_mirrorsInitialized) {
      return const SizedBox.shrink();
    }

    final mirrors = _updateService.mirrors;
    final selectedId = _updateService.selectedMirrorId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '下载源',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_isCheckingMirrors)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                onPressed: _checkAllMirrors,
                tooltip: '刷新连通性',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            IconButton(
              icon: Icon(
                Icons.add_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              onPressed: () => _showAddMirrorDialog(context),
              tooltip: '添加镜像源',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: mirrors.asMap().entries.map((entry) {
              final index = entry.key;
              final mirror = entry.value;
              final isSelected = mirror.id == selectedId;
              final isLast = index == mirrors.length - 1;

              return Column(
                children: [
                  _buildMirrorItem(theme, colorScheme, mirror, isSelected),
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 44,
                      endIndent: 14,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 构建单个镜像源项
  Widget _buildMirrorItem(
    ThemeData theme,
    ColorScheme colorScheme,
    MirrorSource mirror,
    bool isSelected,
  ) {
    // 状态图标和颜色
    Widget statusWidget;
    switch (mirror.status) {
      case MirrorStatus.checking:
        statusWidget = SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        );
      case MirrorStatus.available:
        statusWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 12, color: Colors.green),
            if (mirror.latency != null) ...[
              const SizedBox(width: 3),
              Text(
                '${mirror.latency}ms',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.green,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        );
      case MirrorStatus.unavailable:
        statusWidget = const Icon(Icons.cancel, size: 12, color: Colors.red);
      case MirrorStatus.unknown:
        statusWidget = Icon(
          Icons.help_outline,
          size: 12,
          color: colorScheme.onSurfaceVariant,
        );
    }

    return InkWell(
      onTap: _isDownloading
          ? null
          : () async {
              await _updateService.setSelectedMirror(mirror.id);
              setState(() {});
            },
      onLongPress: mirror.isBuiltin
          ? null
          : () => _showMirrorOptionsMenu(context, mirror),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Radio<String>(
              value: mirror.id,
              groupValue: _updateService.selectedMirrorId,
              onChanged: _isDownloading
                  ? null
                  : (value) async {
                      if (value != null) {
                        await _updateService.setSelectedMirror(value);
                        setState(() {});
                      }
                    },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  Text(
                    mirror.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (!mirror.isBuiltin) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '自定义',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            statusWidget,
          ],
        ),
      ),
    );
  }

  /// 显示添加镜像源对话框
  Future<void> _showAddMirrorDialog(BuildContext context) async {
    final result = await showDialog<MirrorSource>(
      context: context,
      builder: (context) => const _AddMirrorDialog(),
    );

    if (result != null && mounted) {
      final success = await _updateService.addCustomMirror(result);
      if (success) {
        setState(() {});
        // 检测新添加的镜像源
        _updateService
            .checkMirrorConnectivity(result.id, widget.updateInfo.downloadUrl)
            .then((_) {
              if (mounted) setState(() {});
            });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('镜像源ID已存在')));
        }
      }
    }
  }

  /// 显示镜像源选项菜单
  void _showMirrorOptionsMenu(BuildContext context, MirrorSource mirror) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                _showEditMirrorDialog(context, mirror);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('删除镜像源'),
                    content: Text('确定要删除 "${mirror.name}" 吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await _updateService.removeCustomMirror(mirror.id);
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 显示编辑镜像源对话框
  Future<void> _showEditMirrorDialog(
    BuildContext context,
    MirrorSource mirror,
  ) async {
    final result = await showDialog<MirrorSource>(
      context: context,
      builder: (context) => _AddMirrorDialog(editMirror: mirror),
    );

    if (result != null && mounted) {
      await _updateService.updateCustomMirror(result);
      setState(() {});
      // 检测更新后的镜像源
      _updateService
          .checkMirrorConnectivity(result.id, widget.updateInfo.downloadUrl)
          .then((_) {
            if (mounted) setState(() {});
          });
    }
  }
}

/// 添加/编辑镜像源对话框
class _AddMirrorDialog extends StatefulWidget {
  final MirrorSource? editMirror;

  const _AddMirrorDialog({this.editMirror});

  @override
  State<_AddMirrorDialog> createState() => _AddMirrorDialogState();
}

class _AddMirrorDialogState extends State<_AddMirrorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.editMirror?.name ?? '',
    );
    _urlController = TextEditingController(
      text: widget.editMirror?.urlTemplate ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editMirror != null;

    return AlertDialog(
      title: Text(isEdit ? '编辑镜像源' : '添加镜像源'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：我的镜像源',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL模板',
                hintText: 'https://mirror.example.com/{url}',
                border: OutlineInputBorder(),
                helperText: '使用 {url} 表示原始下载链接',
                helperMaxLines: 2,
              ),
              maxLines: 2,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入URL模板';
                }
                if (!value.contains('{url}') && !value.contains('{path}')) {
                  return 'URL模板需包含 {url} 或 {path} 占位符';
                }
                if (!value.startsWith('http://') &&
                    !value.startsWith('https://')) {
                  return 'URL需以 http:// 或 https:// 开头';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text(
              '示例：\n'
              '• https://ghproxy.cc/{url}\n'
              '• https://mirror.ghproxy.com/{url}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final name = _nameController.text.trim();
              final urlTemplate = _urlController.text.trim();
              final id =
                  widget.editMirror?.id ??
                  'custom_${DateTime.now().millisecondsSinceEpoch}';

              Navigator.pop(
                context,
                MirrorSource(
                  id: id,
                  name: name,
                  urlTemplate: urlTemplate,
                  isBuiltin: false,
                ),
              );
            }
          },
          child: Text(isEdit ? '保存' : '添加'),
        ),
      ],
    );
  }
}
