/// 学习通未交作业页面
library;

import 'package:flutter/material.dart';

import '../models/xxt_work.dart';
import '../services/xxt_service.dart';
import '../services/widget_service.dart';
import 'account_manage_screen.dart';

/// 未交作业页面
class XxtWorkScreen extends StatefulWidget {
  const XxtWorkScreen({super.key});

  @override
  State<XxtWorkScreen> createState() => _XxtWorkScreenState();
}

class _XxtWorkScreenState extends State<XxtWorkScreen> {
  final XxtService _xxtService = XxtService();

  bool _isLoading = true;
  XxtWorkResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWorks();
  }

  Future<void> _loadWorks({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _xxtService.getUnfinishedWorks(
      forceRefresh: forceRefresh,
    );

    // 更新作业小组件
    if (result.success) {
      await WidgetService.updateWorksWidget(
        works: result.works,
        needLogin: false,
      );
    } else if (result.needLogin) {
      await WidgetService.updateWorksWidgetNeedLogin();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _result = result;
        if (!result.success) {
          _errorMessage = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('未交作业'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _isLoading ? null : () => _loadWorks(forceRefresh: true),
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 需要配置学习通账号
    if (_result?.needLogin == true) {
      return _buildNeedLoginView(theme, colorScheme);
    }

    // 加载失败
    if (_errorMessage != null) {
      return _buildErrorView(theme, colorScheme);
    }

    // 没有未交作业
    if (_result?.works.isEmpty ?? true) {
      return _buildEmptyView(theme, colorScheme);
    }

    // 显示作业列表
    return _buildWorkList(theme, colorScheme);
  }

  Widget _buildNeedLoginView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '请先配置学习通账号',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在账号管理中添加学习通账号后即可查看未交作业',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openAccountSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '未知错误',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadWorks,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '太棒了！',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '没有未交的作业',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkList(ThemeData theme, ColorScheme colorScheme) {
    final works = _result!.works;
    final overdueWorks = works.where((w) => w.isOverdue).toList();
    final urgentWorks = works.where((w) => w.isUrgent && !w.isOverdue).toList();
    final normalWorks = works
        .where((w) => !w.isUrgent && !w.isOverdue)
        .toList();

    // 未交作业数量不包含已超时的
    final pendingCount = urgentWorks.length + normalWorks.length;

    return RefreshIndicator(
      onRefresh: () => _loadWorks(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 统计信息
          _buildStatsCard(
            theme,
            colorScheme,
            pendingCount,
            urgentWorks.length,
            overdueWorks.length,
          ),
          const SizedBox(height: 14),

          // 紧急作业（24小时内截止）- 优先显示
          if (urgentWorks.isNotEmpty) ...[
            _buildSectionTitle(
              theme,
              colorScheme,
              '即将截止',
              Icons.warning_amber_rounded,
              colorScheme.error,
            ),
            const SizedBox(height: 6),
            ...urgentWorks.map(
              (work) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildWorkCard(
                  theme,
                  colorScheme,
                  work,
                  status: 'urgent',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 普通作业（待完成）
          if (normalWorks.isNotEmpty) ...[
            _buildSectionTitle(
              theme,
              colorScheme,
              '待完成',
              Icons.assignment_outlined,
              colorScheme.primary,
            ),
            const SizedBox(height: 6),
            ...normalWorks.map(
              (work) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildWorkCard(
                  theme,
                  colorScheme,
                  work,
                  status: 'normal',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 已超时作业 - 放在最后
          if (overdueWorks.isNotEmpty) ...[
            _buildSectionTitle(
              theme,
              colorScheme,
              '已超时',
              Icons.error_outline_rounded,
              colorScheme.error,
            ),
            const SizedBox(height: 6),
            ...overdueWorks.map(
              (work) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildWorkCard(
                  theme,
                  colorScheme,
                  work,
                  status: 'overdue',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsCard(
    ThemeData theme,
    ColorScheme colorScheme,
    int total,
    int urgent,
    int overdue,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                theme,
                colorScheme,
                '未交作业',
                total.toString(),
                colorScheme.primary,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _buildStatItem(
                theme,
                colorScheme,
                '即将截止',
                urgent.toString(),
                urgent > 0 ? colorScheme.error : colorScheme.outline,
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _buildStatItem(
                theme,
                colorScheme,
                '已超时',
                overdue.toString(),
                overdue > 0 ? colorScheme.error : colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(
    ThemeData theme,
    ColorScheme colorScheme,
    String title,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkCard(
    ThemeData theme,
    ColorScheme colorScheme,
    XxtWork work, {
    required String status,
  }) {
    final isOverdue = status == 'overdue';
    final isUrgent = status == 'urgent';

    Color cardColor;
    Color borderColor;
    Color timeColor;

    if (isOverdue) {
      // 使用与即将截止一致的颜色逻辑，兼容深色模式
      cardColor = colorScheme.errorContainer.withValues(alpha: 0.5);
      borderColor = colorScheme.error.withValues(alpha: 0.5);
      timeColor = colorScheme.error;
    } else if (isUrgent) {
      cardColor = colorScheme.errorContainer.withValues(alpha: 0.5);
      borderColor = colorScheme.error.withValues(alpha: 0.5);
      timeColor = colorScheme.error;
    } else {
      cardColor = colorScheme.surfaceContainerLow;
      borderColor = colorScheme.outlineVariant;
      timeColor = colorScheme.onSurfaceVariant;
    }

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作业名称
            Row(
              children: [
                Expanded(
                  child: Text(
                    work.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isOverdue)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '超时',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onError,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 课程名称（单独一行，完整显示）
            if (work.courseName != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 13,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      work.courseName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            // 剩余时间（单独一行）
            Row(
              children: [
                Icon(
                  isOverdue ? Icons.error_outline : Icons.schedule,
                  size: 13,
                  color: timeColor,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    work.remainingTime,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: timeColor,
                      fontSize: 12,
                      fontWeight: (isUrgent || isOverdue)
                          ? FontWeight.w600
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openAccountSettings() {
    // 直接导航到账号管理页面配置学习通
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AccountManageScreen()),
    ).then((_) {
      // 返回后刷新数据
      _loadWorks(forceRefresh: true);
    });
  }
}
