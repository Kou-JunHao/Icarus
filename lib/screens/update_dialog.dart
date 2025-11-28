/// 更新对话框组件
///
/// 显示更新信息、下载进度和安装按钮
library;

import 'dart:io';

import 'package:flutter/material.dart';

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
  String? _errorMessage;

  @override
  void dispose() {
    if (_isDownloading) {
      _updateService.cancelDownload();
    }
    super.dispose();
  }

  /// 开始下载
  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    final filePath = await _updateService.downloadUpdate(
      widget.updateInfo,
      onProgress: (received, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = received / total;
          });
        }
      },
    );

    if (!mounted) return;

    if (filePath != null) {
      setState(() {
        _isDownloading = false;
        _isDownloaded = true;
        _downloadedFilePath = filePath;
      });
    } else {
      setState(() {
        _isDownloading = false;
        _errorMessage = '下载失败，请重试';
      });
    }
  }

  /// 安装更新
  Future<void> _installUpdate() async {
    if (_downloadedFilePath == null) return;

    setState(() {
      _isInstalling = true;
    });

    try {
      // 使用原生方法安装 APK
      final success = await _updateService.installUpdate(_downloadedFilePath!);

      if (!success && mounted) {
        // 如果原生安装失败，提示用户手动安装
        final file = File(_downloadedFilePath!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请手动安装更新包\n路径: ${file.path}'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: '复制路径',
              onPressed: () {
                // 这里可以添加复制到剪贴板的功能
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('安装失败: $e')));
      }
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
    if (_isDownloading) {
      _updateService.cancelDownload();
    }
    widget.onDismiss?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部
          _buildHeader(theme, colorScheme),
          // 内容
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 版本信息
                _buildVersionInfo(theme, colorScheme),
                const SizedBox(height: 16),
                // 更新日志
                _buildChangelog(theme, colorScheme),
              ],
            ),
          ),
          // 底部按钮
          _buildActions(theme, colorScheme),
          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }

  /// 构建头部
  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // 拖拽指示器和关闭按钮
          Row(
            children: [
              const Spacer(),
              // 拖拽指示器
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    onPressed: _dismiss,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 图标
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(
            '发现新版本',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建版本信息
  Widget _buildVersionInfo(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'v${widget.updateInfo.version}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.updateInfo.isForceUpdate)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '重要更新',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onError,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.folder_zip_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.updateInfo.formattedFileSize,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(widget.updateInfo.publishedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '更新日志',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: SingleChildScrollView(
            child: Text(
              widget.updateInfo.changelog,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建底部操作按钮
  Widget _buildActions(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 错误提示
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // 按钮区域
          _buildButtonArea(theme, colorScheme),
        ],
      ),
    );
  }

  /// 构建按钮区域
  Widget _buildButtonArea(ThemeData theme, ColorScheme colorScheme) {
    // 下载中 - 显示进度条
    if (_isDownloading) {
      return Column(
        children: [
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '正在下载... ${(_downloadProgress * 100).toInt()}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
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
              : const Icon(Icons.install_mobile_rounded),
          label: Text(_isInstalling ? '安装中...' : '立即安装'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
    }

    // 默认 - 显示下载和跳过按钮
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _skipVersion,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('跳过此版本'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download_rounded),
            label: const Text('下载更新'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
