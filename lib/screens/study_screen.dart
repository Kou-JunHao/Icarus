/// 学习页面
/// 展示学习通相关内容：进行中活动、未交作业
library;

import 'package:flutter/material.dart';

import '../models/xxt_work.dart';
import '../models/xxt_activity.dart';
import '../services/xxt_service.dart';
import '../services/widget_service.dart';
import '../services/notification_service.dart';
import 'account_manage_screen.dart';
import 'xxt_sign_screen.dart';

/// 学习页面
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final XxtService _xxtService = XxtService();

  // 活动相关状态
  bool _isLoadingActivities = true;
  XxtActivityResult? _activityResult;
  String? _activityError;

  // 作业相关状态
  bool _isLoadingWorks = true;
  XxtWorkResult? _workResult;
  String? _workError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    await Future.wait([
      _loadActivities(forceRefresh: forceRefresh),
      _loadWorks(forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _loadActivities({bool forceRefresh = false}) async {
    setState(() {
      _isLoadingActivities = true;
      _activityError = null;
    });

    final result = await _xxtService.getOngoingActivities(
      forceRefresh: forceRefresh,
    );

    // 为即将结束的活动安排通知
    if (result.success && result.hasActivities) {
      _scheduleActivityNotifications(result);
    }

    if (mounted) {
      setState(() {
        _isLoadingActivities = false;
        _activityResult = result;
        if (!result.success) {
          _activityError = result.error;
        }
      });
    }
  }

  /// 为活动安排结束提醒通知
  Future<void> _scheduleActivityNotifications(XxtActivityResult result) async {
    final notificationService = NotificationService();

    // 检查是否启用活动通知
    final enabled = await notificationService.isActivityNotificationEnabled();
    if (!enabled) return;

    for (final courseActivity in result.courseActivities) {
      for (final activity in courseActivity.activities) {
        // 只为有结束时间且未过期的活动安排通知
        if (activity.endTime != null && !activity.isExpired) {
          await notificationService.scheduleActivityNotification(
            activityName: activity.name,
            courseName: courseActivity.courseName,
            activityType: activity.type.displayName,
            endTime: activity.endTime!,
          );
        }
      }
    }
  }

  Future<void> _loadWorks({bool forceRefresh = false}) async {
    setState(() {
      _isLoadingWorks = true;
      _workError = null;
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
        _isLoadingWorks = false;
        _workResult = result;
        if (!result.success) {
          _workError = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 计算徽章数量
    final activityCount = _activityResult?.totalActivityCount ?? 0;
    final workCount = _workResult?.works.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: (_isLoadingActivities || _isLoadingWorks)
                ? null
                : () => _loadData(forceRefresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded, size: 18),
                  const SizedBox(width: 4),
                  const Text('活动'),
                  if (activityCount > 0) ...[
                    const SizedBox(width: 6),
                    _buildBadge(activityCount, colorScheme),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_outlined, size: 18),
                  const SizedBox(width: 4),
                  const Text('作业'),
                  if (workCount > 0) ...[
                    const SizedBox(width: 6),
                    _buildBadge(workCount, colorScheme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActivitiesTab(theme, colorScheme),
          _buildWorksTab(theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildBadge(int count, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.tertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          color: colorScheme.onTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ========== 活动 Tab ==========

  Widget _buildActivitiesTab(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoadingActivities) {
      return _buildLoadingView(colorScheme);
    }

    // 需要配置学习通账号
    if (_activityResult?.needLogin == true) {
      return _buildNeedLoginView(theme, colorScheme);
    }

    // 加载失败
    if (_activityError != null) {
      return _buildErrorView(
        theme,
        colorScheme,
        _activityError!,
        () => _loadActivities(forceRefresh: true),
      );
    }

    // 没有进行中活动
    if (_activityResult?.hasActivities != true) {
      return _buildEmptyActivitiesView(theme, colorScheme);
    }

    // 显示活动列表
    return RefreshIndicator(
      onRefresh: () => _loadActivities(forceRefresh: true),
      child: _buildActivityList(theme, colorScheme),
    );
  }

  Widget _buildLoadingView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text('加载中...', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEmptyActivitiesView(ThemeData theme, ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: () => _loadActivities(forceRefresh: true),
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '暂无进行中的活动',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前没有需要参与的签到、测验等活动',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList(ThemeData theme, ColorScheme colorScheme) {
    final courseActivities = _activityResult!.courseActivities;

    // 按签到优先排序
    final sortedCourses = List<XxtCourseActivities>.from(courseActivities);
    sortedCourses.sort((a, b) {
      final aHasSignIn = a.activities.any(
        (act) => act.type == XxtActivityType.signIn,
      );
      final bHasSignIn = b.activities.any(
        (act) => act.type == XxtActivityType.signIn,
      );
      if (aHasSignIn && !bHasSignIn) return -1;
      if (!aHasSignIn && bHasSignIn) return 1;
      return 0;
    });

    // 统计信息
    final totalActivities = _activityResult!.totalActivityCount;
    final signInCount = _activityResult!.signInActivities.length;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 概览卡片
        _buildActivityOverviewCard(
          theme,
          colorScheme,
          totalActivities,
          signInCount,
          sortedCourses.length,
        ),
        const SizedBox(height: 16),
        // 课程活动列表
        ...sortedCourses.map(
          (course) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCourseActivityCard(theme, colorScheme, course),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityOverviewCard(
    ThemeData theme,
    ColorScheme colorScheme,
    int totalActivities,
    int signInCount,
    int courseCount,
  ) {
    // 使用更柔和的颜色方案
    final hasUrgent = signInCount > 0;
    final baseColor = hasUrgent
        ? colorScheme.errorContainer
        : colorScheme.primaryContainer;
    final accentColor = hasUrgent ? colorScheme.error : colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildOverviewItem(
              theme,
              colorScheme,
              '进行中',
              totalActivities.toString(),
              accentColor,
              Icons.play_circle_outline_rounded,
            ),
          ),
          Container(
            width: 1,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0),
                  accentColor.withValues(alpha: 0.2),
                  accentColor.withValues(alpha: 0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Expanded(
            child: _buildOverviewItem(
              theme,
              colorScheme,
              '待签到',
              signInCount.toString(),
              signInCount > 0 ? colorScheme.error : colorScheme.outline,
              Icons.edit_location_alt_outlined,
            ),
          ),
          Container(
            width: 1,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0),
                  accentColor.withValues(alpha: 0.2),
                  accentColor.withValues(alpha: 0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Expanded(
            child: _buildOverviewItem(
              theme,
              colorScheme,
              '课程数',
              courseCount.toString(),
              hasUrgent
                  ? colorScheme.onErrorContainer
                  : colorScheme.onPrimaryContainer,
              Icons.school_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCourseActivityCard(
    ThemeData theme,
    ColorScheme colorScheme,
    XxtCourseActivities course,
  ) {
    final hasSignIn = course.activities.any(
      (a) => a.type == XxtActivityType.signIn,
    );

    return Card(
      elevation: 0,
      color: hasSignIn
          ? colorScheme.errorContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: hasSignIn
              ? colorScheme.error.withValues(alpha: 0.2)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 课程名称
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: hasSignIn ? colorScheme.error : colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    course.courseName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hasSignIn
                        ? colorScheme.error.withValues(alpha: 0.12)
                        : colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${course.activityCount} 项',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasSignIn
                          ? colorScheme.error
                          : colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 活动列表
            ...course.activities.map(
              (activity) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildActivityItem(theme, colorScheme, activity, course),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(
    ThemeData theme,
    ColorScheme colorScheme,
    XxtActivity activity,
    XxtCourseActivities course,
  ) {
    final isSignIn = activity.type == XxtActivityType.signIn;
    final isUrgent = activity.isUrgent;
    final isCompleted = activity.status.isCompleted;
    final isPending = activity.status.isPending;

    // 使用更柔和的颜色方案
    Color bgColor;
    Color borderColor;
    Color iconBgColor;
    Color iconColor;
    Color mainColor;

    if (isCompleted) {
      // 已完成：柔和的绿色
      bgColor = const Color(0xFF4CAF50).withValues(alpha: 0.08);
      borderColor = const Color(0xFF4CAF50).withValues(alpha: 0.2);
      iconBgColor = const Color(0xFF4CAF50).withValues(alpha: 0.15);
      iconColor = const Color(0xFF2E7D32);
      mainColor = const Color(0xFF4CAF50);
    } else if (isSignIn) {
      // 签到：使用橙色而非红色，更友好
      bgColor = const Color(0xFFFF9800).withValues(alpha: 0.1);
      borderColor = const Color(0xFFFF9800).withValues(alpha: 0.25);
      iconBgColor = const Color(0xFFFF9800).withValues(alpha: 0.2);
      iconColor = const Color(0xFFE65100);
      mainColor = const Color(0xFFFF9800);
    } else if (isUrgent) {
      // 紧急：柔和的红色
      bgColor = colorScheme.errorContainer.withValues(alpha: 0.4);
      borderColor = colorScheme.error.withValues(alpha: 0.2);
      iconBgColor = colorScheme.error.withValues(alpha: 0.15);
      iconColor = colorScheme.error;
      mainColor = colorScheme.error;
    } else {
      // 普通：使用主题色
      bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.3);
      iconBgColor = colorScheme.primaryContainer.withValues(alpha: 0.7);
      iconColor = colorScheme.primary;
      mainColor = colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 活动类型图标
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_rounded
                      : _getActivityIcon(activity.type),
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              // 活动信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isCompleted
                            ? colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              )
                            : colorScheme.onSurface,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // 活动类型标签
                        _buildActivityTag(
                          activity.type.displayName,
                          mainColor,
                          theme,
                        ),
                        // 状态标签
                        if (isPending || isCompleted) ...[
                          const SizedBox(width: 6),
                          _buildActivityTag(
                            isCompleted ? '已完成' : '待完成',
                            isCompleted
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF9800),
                            theme,
                          ),
                        ],
                        const Spacer(),
                        // 时间信息
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: isUrgent
                              ? mainColor
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          activity.remainingTimeText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isUrgent
                                ? mainColor
                                : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                            fontWeight: isUrgent
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 签到按钮（仅对签到类型活动且未完成时显示）
          if (isSignIn && !isCompleted) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => _navigateToSign(activity, course),
                style: FilledButton.styleFrom(
                  backgroundColor: mainColor.withValues(alpha: 0.15),
                  foregroundColor: mainColor,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_location_alt_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('立即签到', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建活动标签
  Widget _buildActivityTag(String text, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }

  IconData _getActivityIcon(XxtActivityType type) {
    switch (type) {
      case XxtActivityType.signIn:
        return Icons.location_on_rounded;
      case XxtActivityType.quiz:
        return Icons.quiz_rounded;
      case XxtActivityType.groupTask:
        return Icons.group_rounded;
      case XxtActivityType.vote:
        return Icons.how_to_vote_rounded;
      case XxtActivityType.discussion:
        return Icons.forum_rounded;
      case XxtActivityType.live:
        return Icons.videocam_rounded;
      case XxtActivityType.other:
        return Icons.assignment_rounded;
    }
  }

  /// 跳转到签到页面
  Future<void> _navigateToSign(
    XxtActivity activity,
    XxtCourseActivities course,
  ) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            XxtSignScreen(activity: activity, courseActivity: course),
      ),
    );

    // 如果签到成功，刷新活动列表
    if (result != null && mounted) {
      _loadActivities(forceRefresh: true);
    }
  }

  // ========== 作业 Tab ==========

  Widget _buildWorksTab(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoadingWorks) {
      return _buildLoadingView(colorScheme);
    }

    // 需要配置学习通账号
    if (_workResult?.needLogin == true) {
      return _buildNeedLoginView(theme, colorScheme);
    }

    // 加载失败
    if (_workError != null) {
      return _buildErrorView(
        theme,
        colorScheme,
        _workError!,
        () => _loadWorks(forceRefresh: true),
      );
    }

    // 没有未交作业
    if (_workResult?.works.isEmpty ?? true) {
      return _buildEmptyWorksView(theme, colorScheme);
    }

    // 显示作业列表
    return RefreshIndicator(
      onRefresh: () => _loadWorks(forceRefresh: true),
      child: _buildWorkList(theme, colorScheme),
    );
  }

  Widget _buildEmptyWorksView(ThemeData theme, ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: () => _loadWorks(forceRefresh: true),
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.task_alt_rounded,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '作业已全部完成',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '太棒了！没有待提交的作业',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkList(ThemeData theme, ColorScheme colorScheme) {
    final works = _workResult!.works;
    final overdueWorks = works.where((w) => w.isOverdue).toList();
    final urgentWorks = works.where((w) => w.isUrgent && !w.isOverdue).toList();
    final normalWorks = works
        .where((w) => !w.isUrgent && !w.isOverdue)
        .toList();

    // 未交作业数量不包含已超时的
    final pendingCount = urgentWorks.length + normalWorks.length;

    return ListView(
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
        const SizedBox(height: 16),

        // 紧急作业（24小时内截止）- 优先显示
        if (urgentWorks.isNotEmpty) ...[
          _buildSectionTitle(
            theme,
            colorScheme,
            '即将截止',
            Icons.warning_amber_rounded,
            colorScheme.error,
          ),
          const SizedBox(height: 8),
          ...urgentWorks.map(
            (work) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildWorkCard(theme, colorScheme, work, status: 'urgent'),
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
          const SizedBox(height: 8),
          ...normalWorks.map(
            (work) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildWorkCard(theme, colorScheme, work, status: 'normal'),
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
            colorScheme.outline,
          ),
          const SizedBox(height: 8),
          ...overdueWorks.map(
            (work) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
    );
  }

  Widget _buildStatsCard(
    ThemeData theme,
    ColorScheme colorScheme,
    int total,
    int urgent,
    int overdue,
  ) {
    final hasUrgent = urgent > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasUrgent
              ? [
                  colorScheme.errorContainer,
                  colorScheme.errorContainer.withValues(alpha: 0.7),
                ]
              : [
                  colorScheme.primaryContainer,
                  colorScheme.primaryContainer.withValues(alpha: 0.7),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              theme,
              colorScheme,
              '待完成',
              total.toString(),
              hasUrgent ? colorScheme.error : colorScheme.primary,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: (hasUrgent ? colorScheme.error : colorScheme.primary)
                .withValues(alpha: 0.2),
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
            color: (hasUrgent ? colorScheme.error : colorScheme.primary)
                .withValues(alpha: 0.2),
          ),
          Expanded(
            child: _buildStatItem(
              theme,
              colorScheme,
              '已超时',
              overdue.toString(),
              overdue > 0 ? colorScheme.onErrorContainer : colorScheme.outline,
            ),
          ),
        ],
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
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color.withValues(alpha: 0.8),
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
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
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
      cardColor = colorScheme.surfaceContainerLow;
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);
      timeColor = colorScheme.outline;
    } else if (isUrgent) {
      cardColor = colorScheme.errorContainer.withValues(alpha: 0.4);
      borderColor = colorScheme.error.withValues(alpha: 0.3);
      timeColor = colorScheme.error;
    } else {
      cardColor = colorScheme.surfaceContainerLow;
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);
      timeColor = colorScheme.onSurfaceVariant;
    }

    return Card(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作业名称
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    work.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isOverdue
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                      decoration: isOverdue ? TextDecoration.lineThrough : null,
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
                      color: colorScheme.outline.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '已超时',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  )
                else if (isUrgent)
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
                      '紧急',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onError,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 课程名称和时间
            Row(
              children: [
                if (work.courseName != null) ...[
                  Icon(
                    Icons.book_outlined,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      work.courseName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(Icons.schedule_rounded, size: 14, color: timeColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    work.remainingTime,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: timeColor,
                      fontWeight: isUrgent ? FontWeight.w600 : null,
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

  // ========== 通用视图 ==========

  Widget _buildNeedLoginView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_circle_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '请配置学习通账号',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在账号管理中绑定学习通账号后\n即可查看活动和作业',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openAccountSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    ThemeData theme,
    ColorScheme colorScheme,
    String error,
    VoidCallback onRetry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  void _openAccountSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AccountManageScreen()),
    );
  }
}
