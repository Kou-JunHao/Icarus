/// 主页
/// 展示今日课程和天气信息
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'schedule_screen.dart' show CourseColors;
import 'update_dialog.dart';

/// 通知类型
enum NotificationType {
  update, // 版本更新
  course, // 上课提醒
  announcement, // 公告
}

/// 通知项
class NotificationItem {
  final NotificationType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final DateTime? time;

  const NotificationItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color,
    this.onTap,
    this.time,
  });
}

/// 主页屏幕
class HomeScreen extends StatefulWidget {
  final DataManager dataManager;

  const HomeScreen({super.key, required this.dataManager});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  // 天气服务和数据
  WeatherService? _weatherService;
  WeatherInfo? _weather;
  bool _isLoadingWeather = true;
  bool _hasCity = false; // 是否已设置城市
  String? _cityName; // 当前城市名称

  // 时间表 - 与课程表页面同步
  Map<int, (String, String)> _sectionTimes = {};

  // 课程卡片 PageController
  PageController? _coursePageController;
  int _currentCourseIndex = 0;
  int _lastCourseCount = 0; // 用于检测课程数量变化
  bool _needsInitialScroll = true; // 标记是否需要初始滚动

  // 更新相关
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;

  // 使用 false 允许页面在不可见时释放内存
  @override
  bool get wantKeepAlive => false;

  /// 获取天气服务实例（懒加载）
  WeatherService get weatherService {
    _weatherService ??= WeatherService();
    return _weatherService!;
  }

  @override
  void initState() {
    super.initState();
    _checkCityAndLoadWeather();
    _loadTimetable();
    _checkForUpdate();
  }

  @override
  void dispose() {
    _coursePageController?.dispose();
    _coursePageController = null;
    _weatherService?.dispose();
    _weatherService = null;
    _weather = null;
    _sectionTimes.clear();
    super.dispose();
  }

  /// 获取所有通知列表
  List<NotificationItem> _getNotifications() {
    final notifications = <NotificationItem>[];

    // 版本更新通知
    if (_updateInfo != null) {
      notifications.add(
        NotificationItem(
          type: NotificationType.update,
          title: '发现新版本 v${_updateInfo!.version}',
          subtitle: '点击查看更新内容',
          icon: Icons.system_update_rounded,
          color: Colors.blue,
          onTap: _showUpdateDialog,
        ),
      );
    }

    // 上课提醒通知（检查即将开始的课程）
    final upcomingCourse = _getUpcomingCourseNotification();
    if (upcomingCourse != null) {
      notifications.add(upcomingCourse);
    }

    return notifications;
  }

  /// 获取即将开始的课程通知
  NotificationItem? _getUpcomingCourseNotification() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final schedule = widget.dataManager.schedule;
    final currentWeek = widget.dataManager.currentWeek;

    if (schedule == null) return null;

    final todayCourses = schedule.getCoursesForDay(currentWeek, weekday);
    if (todayCourses.isEmpty) return null;

    for (final course in todayCourses) {
      final startTimeStr = _getSectionTime(course.startSection, true);
      if (startTimeStr == '--:--') continue;

      final parts = startTimeStr.split(':');
      final startTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );

      final diff = startTime.difference(now);
      // 30分钟内即将开始的课程
      if (diff.inMinutes > 0 && diff.inMinutes <= 30) {
        return NotificationItem(
          type: NotificationType.course,
          title: '${course.name} 即将开始',
          subtitle: '${diff.inMinutes}分钟后 · ${course.location ?? "未知地点"}',
          icon: Icons.schedule_rounded,
          color: Colors.orange,
          time: startTime,
        );
      }
    }

    return null;
  }

  /// 检查应用更新
  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;

    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdate();
      if (mounted && updateInfo != null) {
        setState(() {
          _updateInfo = updateInfo;
        });
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  /// 显示更新对话框
  void _showUpdateDialog() {
    if (_updateInfo == null) return;

    UpdateDialog.show(
      context,
      updateInfo: _updateInfo!,
      onSkip: () {
        setState(() {
          _updateInfo = null;
        });
      },
      onDismiss: () {
        // 用户关闭对话框但不跳过版本
      },
    );
  }

  /// 检查城市设置并加载天气
  Future<void> _checkCityAndLoadWeather() async {
    final hasCity = await weatherService.hasCity();
    final cityName = await AuthStorage.getWeatherCityName();

    if (mounted) {
      setState(() {
        _hasCity = hasCity;
        _cityName = cityName;
      });
    }

    if (hasCity) {
      await _loadWeather();
    } else {
      if (mounted) {
        setState(() {
          _isLoadingWeather = false;
        });
      }
    }
  }

  /// 加载天气数据
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<void> _loadWeather({bool forceRefresh = false}) async {
    if (!_hasCity) return;

    setState(() {
      _isLoadingWeather = true;
    });

    try {
      final weather = await weatherService.getWeather(
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _weather = weather;
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      print('加载天气失败: $e');
      if (mounted) {
        setState(() {
          _weather = WeatherInfo.defaultWeather();
          _isLoadingWeather = false;
        });
      }
    }
  }

  /// 加载时间表（与课程表页面同步）
  Future<void> _loadTimetable() async {
    // 优先使用自定义时间表
    final customTimetable = await AuthStorage.getCustomTimetable();
    if (customTimetable != null && customTimetable.isNotEmpty) {
      if (mounted) {
        setState(() {
          _sectionTimes = customTimetable;
        });
      }
      return;
    }
    // 否则根据设置生成时间表
    final settings = await AuthStorage.getScheduleSettings();
    if (mounted) {
      setState(() {
        _sectionTimes = AuthStorage.generateTimetable(settings);
      });
    }
  }

  /// 获取最近课程的索引（优先显示正在进行或即将开始的课程）
  int _getRelevantCourseIndex(List<Course> courses) {
    if (courses.isEmpty) return 0;

    final now = DateTime.now();

    // 首先查找正在进行的课程
    for (int i = 0; i < courses.length; i++) {
      if (_isOngoingCourse(courses[i], now)) {
        return i;
      }
    }

    // 然后查找下一节未开始的课程
    for (int i = 0; i < courses.length; i++) {
      final startTimeStr = _getSectionTime(courses[i].startSection, true);
      if (startTimeStr == '--:--') continue;

      final parts = startTimeStr.split(':');
      final startTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );

      if (now.isBefore(startTime)) {
        return i;
      }
    }

    // 如果所有课程都已结束，显示最后一节课
    return courses.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final weekday = now.weekday;

    return ListenableBuilder(
      listenable: widget.dataManager,
      builder: (context, child) {
        final isLoading =
            widget.dataManager.scheduleState == LoadingState.loading;
        final hasError = widget.dataManager.scheduleState == LoadingState.error;
        final schedule = widget.dataManager.schedule;
        final currentWeek = widget.dataManager.currentWeek;
        final todayCourses =
            schedule?.getCoursesForDay(currentWeek, weekday) ?? [];

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () =>
                widget.dataManager.loadSchedule(forceRefresh: true),
            child: CustomScrollView(
              slivers: [
                // 顶部区域
                SliverAppBar(
                  expandedHeight: 120,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      '今天',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: isLoading
                            ? null
                            : () => widget.dataManager.loadSchedule(
                                forceRefresh: true,
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildNotificationButton(colorScheme),
                    ),
                  ],
                ),

                // 内容区域
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 日期和周次信息
                      _buildDateHeader(theme, colorScheme, now, currentWeek),
                      const SizedBox(height: 20),

                      // 天气卡片
                      _buildWeatherCard(theme, colorScheme),
                      const SizedBox(height: 20),

                      // 今日课程标题
                      _buildSectionTitle(
                        theme,
                        '今日课程',
                        isLoading ? 0 : todayCourses.length,
                      ),
                      const SizedBox(height: 12),

                      // 加载状态
                      if (isLoading) _buildLoadingState(colorScheme),

                      // 错误状态
                      if (hasError && !isLoading)
                        _buildErrorState(theme, colorScheme),

                      // 课程卡片滑动区域或空状态
                      if (!isLoading && !hasError)
                        if (todayCourses.isEmpty)
                          _buildEmptyCoursesCard(theme, colorScheme)
                        else
                          _buildCourseCarousel(
                            theme,
                            colorScheme,
                            todayCourses,
                          ),

                      const SizedBox(height: 20),

                      // 快捷操作区域（签到按钮）
                      _buildQuickActions(theme, colorScheme),

                      const SizedBox(height: 80), // 底部留白
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建通知按钮（按钮样式，支持多种通知）
  Widget _buildNotificationButton(ColorScheme colorScheme) {
    final notifications = _getNotifications();
    final hasNotifications = notifications.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(right: 4),
      child: Material(
        color: hasNotifications
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showNotificationPanel(notifications),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      hasNotifications
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_outlined,
                      size: 20,
                      color: hasNotifications
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    // 通知数量徽章
                    if (hasNotifications)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '${notifications.length}',
                            style: TextStyle(
                              color: colorScheme.onError,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                if (hasNotifications) ...[
                  const SizedBox(width: 8),
                  Text(
                    '通知',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示通知面板
  void _showNotificationPanel(List<NotificationItem> notifications) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.notifications_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    '通知中心',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (notifications.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${notifications.length} 条',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 通知列表
            Flexible(
              child: notifications.isEmpty
                  ? _buildEmptyNotifications(theme, colorScheme)
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 72,
                        endIndent: 24,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        return _buildNotificationTile(
                          theme,
                          colorScheme,
                          notification,
                        );
                      },
                    ),
            ),
            // 底部安全区域
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  /// 构建空通知状态
  Widget _buildEmptyNotifications(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无通知',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '新消息会在这里显示',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建通知项
  Widget _buildNotificationTile(
    ThemeData theme,
    ColorScheme colorScheme,
    NotificationItem notification,
  ) {
    final color = notification.color ?? colorScheme.primary;

    return InkWell(
      onTap: () {
        Navigator.pop(context); // 关闭面板
        notification.onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(notification.icon, size: 24, color: color),
            ),
            const SizedBox(width: 16),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 箭头
            if (notification.onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    DateTime now,
    int currentWeek,
  ) {
    final weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                '${now.month}月${now.day}日 ${weekdayNames[now.weekday - 1]}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '第 $currentWeek 周',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherCard(ThemeData theme, ColorScheme colorScheme) {
    // 未设置城市状态
    if (!_hasCity) {
      return Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showCitySelector(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_city_rounded,
                    size: 24,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置天气城市',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '点击选择您所在的城市',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final weather = _weather;

    // 加载中状态
    if (_isLoadingWeather) {
      return Card(
        elevation: 0,
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '正在获取${_cityName ?? ''}天气...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 天气获取失败状态
    if (weather == null) {
      return Card(
        elevation: 0,
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _loadWeather(forceRefresh: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '天气获取失败，点击重试',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.settings_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: _showCitySelector,
                  tooltip: '更换城市',
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 根据天气状况选择渐变色
    final gradientColors = _getWeatherGradient(weather.icon, colorScheme);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showWeatherDetail(weather), // 点击显示详情
        onLongPress: _showCitySelector, // 长按更换城市
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 天气图标
                Text(weather.iconEmoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 10),
                // 温度和描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${weather.temperature.round()}°',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            weather.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _cityName ?? weather.cityName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          Text(
                            ' · ${weather.humidity}% · ${weather.windLevel}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 右侧信息
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '体感${weather.feelsLike.round()}°',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 显示天气详情弹窗
  void _showWeatherDetail(WeatherInfo weather) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final gradientColors = _getWeatherGradient(weather.icon, colorScheme);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示器
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 顶部渐变头部
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Text(
                      weather.iconEmoji,
                      style: const TextStyle(fontSize: 48),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${weather.temperature.round()}°C',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                weather.description,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _cityName ?? weather.cityName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 详细信息网格
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 第一行：体感温度、湿度、云量
                    Row(
                      children: [
                        _buildWeatherDetailItem(
                          icon: Icons.thermostat_rounded,
                          label: '体感温度',
                          value: '${weather.feelsLike.round()}°C',
                          colorScheme: colorScheme,
                        ),
                        _buildWeatherDetailItem(
                          icon: Icons.water_drop_rounded,
                          label: '湿度',
                          value: '${weather.humidity}%',
                          colorScheme: colorScheme,
                        ),
                        _buildWeatherDetailItem(
                          icon: Icons.cloud_rounded,
                          label: '云量',
                          value: '${weather.clouds}%',
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 第二行：风速、气压、能见度
                    Row(
                      children: [
                        _buildWeatherDetailItem(
                          icon: Icons.air_rounded,
                          label: weather.windDirection.isNotEmpty
                              ? weather.windDirection
                              : '风力',
                          value: '${weather.windSpeed.toStringAsFixed(1)}m/s',
                          colorScheme: colorScheme,
                        ),
                        _buildWeatherDetailItem(
                          icon: Icons.compress_rounded,
                          label: '气压',
                          value: '${weather.pressure}hPa',
                          colorScheme: colorScheme,
                        ),
                        _buildWeatherDetailItem(
                          icon: Icons.visibility_rounded,
                          label: '能见度',
                          value:
                              '${(weather.visibility / 1000).toStringAsFixed(0)}km',
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    // 日出日落（如果有数据）
                    if (weather.sunrise != null || weather.sunset != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (weather.sunrise != null)
                            _buildWeatherDetailItem(
                              icon: Icons.wb_sunny_rounded,
                              label: '日出',
                              value: _formatTime(weather.sunrise!),
                              colorScheme: colorScheme,
                            ),
                          if (weather.sunset != null)
                            _buildWeatherDetailItem(
                              icon: Icons.nightlight_rounded,
                              label: '日落',
                              value: _formatTime(weather.sunset!),
                              colorScheme: colorScheme,
                            ),
                          // 阵风（如果有数据）
                          if (weather.windGust != null)
                            _buildWeatherDetailItem(
                              icon: Icons.storm_rounded,
                              label: '阵风',
                              value:
                                  '${weather.windGust!.toStringAsFixed(1)}m/s',
                              colorScheme: colorScheme,
                            )
                          else
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // 底部操作按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showCitySelector();
                        },
                        icon: const Icon(Icons.location_city_rounded, size: 18),
                        label: const Text('更换城市'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _loadWeather(forceRefresh: true);
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('刷新'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建天气详情项
  Widget _buildWeatherDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建快捷操作区域
  Widget _buildQuickActions(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '快捷操作',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 去签到按钮（单独一个，全宽）
        _buildQuickActionCard(
          theme,
          colorScheme,
          icon: Icons.fact_check_outlined,
          label: '去签到',
          subtitle: '打开超星学习通',
          color: const Color(0xFF2196F3),
          onTap: _launchXuexitong,
        ),
      ],
    );
  }

  /// 构建单个快捷操作卡片
  Widget _buildQuickActionCard(
    ThemeData theme,
    ColorScheme colorScheme, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: color.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 启动超星学习通
  Future<void> _launchXuexitong() async {
    // 超星学习通包名
    const packageName = 'com.chaoxing.mobile';

    // 各平台应用商店链接
    final storeUrl = Platform.isIOS
        ? 'itms-apps://itunes.apple.com/app/id562498600' // iOS App Store
        : 'market://details?id=$packageName'; // Android 应用市场

    // 通用下载页面（后备方案）
    const downloadUrl = 'https://app.chaoxing.com/apis/download/downloadapp';

    try {
      if (Platform.isAndroid) {
        // Android 上直接使用 intent 打开应用
        // 格式: android-app://包名
        final androidIntent = Uri.parse('android-app://$packageName');
        try {
          final launched = await launchUrl(
            androidIntent,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return;
        } catch (_) {
          // 尝试使用 intent scheme
        }

        // 尝试使用 intent scheme 格式
        final intentUri = Uri.parse(
          'intent://#Intent;package=$packageName;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;end',
        );
        try {
          final launched = await launchUrl(
            intentUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return;
        } catch (_) {
          // 继续尝试其他方式
        }
      } else {
        // iOS 使用 URL Scheme
        const xuexitongScheme = 'chaoxing://';
        final schemeUri = Uri.parse(xuexitongScheme);
        try {
          final launched = await launchUrl(
            schemeUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return;
        } catch (_) {
          // 打开失败，继续尝试其他方式
        }
      }

      // 尝试打开应用商店
      final storeUri = Uri.parse(storeUrl);
      try {
        final launched = await launchUrl(
          storeUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {
        // 继续尝试
      }

      // 最后尝试打开下载页面
      final downloadUri = Uri.parse(downloadUrl);
      final launched = await launchUrl(
        downloadUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;

      // 都失败了，提示用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法打开学习通，请确保已安装超星学习通'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开学习通失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 显示城市选择器
  void _showCitySelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => _CitySelector(
        onCitySelected: (cityPinyin, cityName) async {
          // 保存城市设置
          await AuthStorage.saveWeatherCity(cityPinyin, cityName);
          if (mounted) {
            setState(() {
              _hasCity = true;
              _cityName = cityName;
            });
            // 加载新城市的天气
            _loadWeather(forceRefresh: true);
          }
        },
      ),
    );
  }

  /// 根据天气图标获取渐变色
  List<Color> _getWeatherGradient(String icon, ColorScheme colorScheme) {
    switch (icon) {
      case '01d': // 晴天白天
        return [const Color(0xFF4A90D9), const Color(0xFF67B8DE)];
      case '01n': // 晴天夜间
        return [const Color(0xFF2C3E50), const Color(0xFF4A6B8A)];
      case '02d': // 少云白天
      case '03d':
        return [const Color(0xFF5B9BD5), const Color(0xFF7EC8E3)];
      case '02n': // 少云夜间
      case '03n':
        return [const Color(0xFF34495E), const Color(0xFF5D7B93)];
      case '04d': // 阴天
      case '04n':
        return [const Color(0xFF636E72), const Color(0xFF8395A7)];
      case '09d': // 阵雨
      case '09n':
      case '10d':
      case '10n':
        return [const Color(0xFF4B6584), const Color(0xFF778CA3)];
      case '11d': // 雷雨
      case '11n':
        return [const Color(0xFF2D3436), const Color(0xFF636E72)];
      case '13d': // 雪
      case '13n':
        return [const Color(0xFF74B9FF), const Color(0xFFA8D8EA)];
      case '50d': // 雾
      case '50n':
        return [const Color(0xFF95A5A6), const Color(0xFFBDC3C7)];
      default:
        return [colorScheme.primary, colorScheme.secondary];
    }
  }

  Widget _buildSectionTitle(ThemeData theme, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在加载课程表...',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              '加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.dataManager.errorMessage ?? '请检查网络连接',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () =>
                  widget.dataManager.loadSchedule(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCoursesCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.celebration_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '今天没有课程',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '享受美好的一天吧！',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建课程卡片轮播
  Widget _buildCourseCarousel(
    ThemeData theme,
    ColorScheme colorScheme,
    List<Course> courses,
  ) {
    // 检测课程数量是否变化，如果变化则需要重新初始化
    if (_lastCourseCount != courses.length) {
      _lastCourseCount = courses.length;
      _needsInitialScroll = true;
    }

    // 计算初始显示的课程索引
    final initialIndex = _getRelevantCourseIndex(courses);

    // 初始化 PageController（仅在需要时）
    if (_coursePageController == null) {
      _coursePageController = PageController(
        initialPage: initialIndex,
        viewportFraction: 1.0,
      );
      _currentCourseIndex = initialIndex;
      _needsInitialScroll = false;
    } else if (_needsInitialScroll) {
      // 课程数据变化后，需要滚动到最相关的课程
      _currentCourseIndex = initialIndex.clamp(0, courses.length - 1);
      // 使用 addPostFrameCallback 确保在 build 之后执行
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_coursePageController != null &&
            _coursePageController!.hasClients &&
            mounted) {
          _coursePageController!.jumpToPage(_currentCourseIndex);
        }
      });
      _needsInitialScroll = false;
    }

    // 确保当前索引在有效范围内
    if (_currentCourseIndex >= courses.length) {
      _currentCourseIndex = courses.length - 1;
    }
    if (_currentCourseIndex < 0) {
      _currentCourseIndex = 0;
    }

    return Column(
      children: [
        // 课程卡片区域
        SizedBox(
          height: 210, // 固定高度
          child: PageView.builder(
            controller: _coursePageController,
            itemCount: courses.length,
            // 性能优化
            allowImplicitScrolling: true,
            physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
            onPageChanged: (index) {
              // 使用微任务延迟更新，避免滑动卡顿
              Future.microtask(() {
                if (mounted && _currentCourseIndex != index) {
                  setState(() {
                    _currentCourseIndex = index;
                  });
                }
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                // 使用 RepaintBoundary 隔离重绘
                child: RepaintBoundary(
                  child: _buildCourseCard(
                    theme,
                    colorScheme,
                    courses[index],
                    index,
                    courses.length,
                  ),
                ),
              );
            },
          ),
        ),
        // 页面指示器
        if (courses.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 左滑提示
              Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: _currentCourseIndex > 0
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.outlineVariant,
              ),
              const SizedBox(width: 8),
              // 指示点
              ...List.generate(courses.length, (index) {
                final isActive = index == _currentCourseIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
              const SizedBox(width: 8),
              // 右滑提示
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: _currentCourseIndex < courses.length - 1
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.outlineVariant,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 滑动提示文字
          Text(
            '左右滑动查看全部 ${courses.length} 节课',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCourseCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Course course,
    int index,
    int totalCourses,
  ) {
    // 使用与课程表页面一致的颜色
    final color = CourseColors.getColor(course.name);

    // 计算上课时间
    final startTime = _getSectionTime(course.startSection, true);
    final endTime = _getSectionTime(course.endSection, false);

    // 判断是否正在上课
    final now = DateTime.now();
    final isOngoing = _isOngoingCourse(course, now);

    // 计算课程状态
    final (statusText, statusColor) = _getCourseStatus(course, now);

    return Card(
      elevation: 0,
      color: isOngoing
          ? color.withValues(alpha: 0.08)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isOngoing
              ? color.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isOngoing ? 1.5 : 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showCourseDetail(course),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：状态标签、时间和节次/序号
              Row(
                children: [
                  // 状态标签
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isOngoing) ...[
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        Text(
                          statusText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 上课时间
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(
                          '$startTime - $endTime',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // 课程序号
                  if (totalCourses > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${index + 1}/$totalCourses',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  // 节次
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${course.startSection}-${course.endSection}节',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 中部：课程名称和教师
              Row(
                children: [
                  // 左侧颜色条
                  Container(
                    width: 4,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 课程信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // 教师
                        if (course.teacher != null)
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                course.teacher!,
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
              const SizedBox(height: 12),
              // 底部：上课地点
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 18,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '上课地点',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            course.location ?? '未知',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取课程状态
  (String, Color) _getCourseStatus(Course course, DateTime now) {
    final startTimeStr = _getSectionTime(course.startSection, true);
    final endTimeStr = _getSectionTime(course.endSection, false);

    if (startTimeStr == '--:--' || endTimeStr == '--:--') {
      return ('待定', Colors.grey);
    }

    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');

    final startTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );
    final endTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(endParts[0]),
      int.parse(endParts[1]),
    );

    if (now.isBefore(startTime)) {
      final diff = startTime.difference(now);
      if (diff.inMinutes <= 30) {
        return ('即将开始', Colors.orange);
      }
      return ('未开始', Colors.grey);
    } else if (now.isAfter(endTime)) {
      return ('已结束', Colors.grey);
    } else {
      return ('进行中', Colors.green);
    }
  }

  String _getSectionTime(int section, bool isStart) {
    // 使用动态时间表（与课程表页面同步）
    final times = _sectionTimes[section];
    if (times == null) return '--:--';
    return isStart ? times.$1 : times.$2;
  }

  bool _isOngoingCourse(Course course, DateTime now) {
    final startTimeStr = _getSectionTime(course.startSection, true);
    final endTimeStr = _getSectionTime(course.endSection, false);

    if (startTimeStr == '--:--' || endTimeStr == '--:--') {
      return false;
    }

    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');

    final startTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );
    final endTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(endParts[0]),
      int.parse(endParts[1]),
    );

    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  void _showCourseDetail(Course course) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = CourseColors.getColor(course.name);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 课程名称和颜色标记
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    course.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildDetailRow(
              Icons.person_outline,
              '教师',
              course.teacher ?? '未知',
              color,
            ),
            _buildDetailRow(
              Icons.location_on_outlined,
              '地点',
              course.location ?? '未知',
              color,
            ),
            _buildDetailRow(
              Icons.access_time,
              '时间',
              '${_getSectionTime(course.startSection, true)} - ${_getSectionTime(course.endSection, false)}',
              color,
            ),
            _buildDetailRow(
              Icons.view_agenda_outlined,
              '节次',
              '第${course.startSection}-${course.endSection}节',
              color,
            ),
            _buildDetailRow(
              Icons.date_range,
              '周次',
              course.weekRange ?? '未知',
              color,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color accentColor,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 城市选择器组件
class _CitySelector extends StatefulWidget {
  final Function(String cityPinyin, String cityName) onCitySelected;

  const _CitySelector({required this.onCitySelected});

  @override
  State<_CitySelector> createState() => _CitySelectorState();
}

class _CitySelectorState extends State<_CitySelector> {
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedDistrict;

  List<String> _provinces = [];
  List<String> _cities = [];
  List<String> _districts = [];
  bool _isLoading = true;

  // 用于控制列表滚动位置
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  Future<void> _loadProvinces() async {
    // 确保城市数据已加载
    await ChinaRegionData.init();
    if (mounted) {
      setState(() {
        _provinces = ChinaRegionData.getProvinces();
        _isLoading = false;
      });
    }
  }

  void _onProvinceSelected(String province) {
    setState(() {
      _selectedProvince = province;
      _selectedCity = null;
      _selectedDistrict = null;
      _cities = ChinaRegionData.getCities(province);
      _districts = [];
    });
    // 重置滚动位置到顶部
    _resetScroll();
  }

  void _onCitySelected(String city) {
    setState(() {
      _selectedCity = city;
      _selectedDistrict = null;
      _districts = ChinaRegionData.getDistricts(_selectedProvince!, city);
    });
    // 重置滚动位置到顶部
    _resetScroll();
  }

  void _onDistrictSelected(String district) {
    setState(() {
      _selectedDistrict = district;
    });
  }

  void _resetScroll() {
    // 等待下一帧再滚动，确保列表已经更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _confirmSelection() {
    if (_selectedProvince == null || _selectedCity == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择省份和城市')));
      return;
    }

    final pinyin = ChinaRegionData.getPinyin(
      _selectedProvince!,
      _selectedCity!,
      _selectedDistrict,
    );

    if (pinyin == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('获取城市信息失败')));
      return;
    }

    // 构建显示名称
    String cityName = _selectedCity!;
    if (_selectedDistrict != null && _selectedDistrict!.isNotEmpty) {
      cityName = '$_selectedCity · $_selectedDistrict';
    }

    widget.onCitySelected(pinyin, cityName);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    '选择城市',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                TextButton(
                  onPressed: _confirmSelection,
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 已选择的路径
          if (_selectedProvince != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPathChip(
                    _selectedProvince!,
                    onTap: () {
                      setState(() {
                        _selectedProvince = null;
                        _selectedCity = null;
                        _selectedDistrict = null;
                        _cities = [];
                        _districts = [];
                      });
                    },
                  ),
                  if (_selectedCity != null)
                    _buildPathChip(
                      _selectedCity!,
                      onTap: () {
                        setState(() {
                          _selectedCity = null;
                          _selectedDistrict = null;
                          _districts = [];
                        });
                      },
                    ),
                  if (_selectedDistrict != null)
                    _buildPathChip(
                      _selectedDistrict!,
                      onTap: () {
                        setState(() {
                          _selectedDistrict = null;
                        });
                      },
                    ),
                ],
              ),
            ),

          // 选择列表
          Flexible(child: _buildSelectionList(theme, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildPathChip(String label, {VoidCallback? onTap}) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.close, size: 16, color: colorScheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionList(ThemeData theme, ColorScheme colorScheme) {
    // 加载中状态
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在加载城市数据...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 根据当前选择状态决定显示什么列表
    List<String> items;
    String title;
    void Function(String) onSelected;

    if (_selectedProvince == null) {
      items = _provinces;
      title = '选择省份';
      onSelected = _onProvinceSelected;
    } else if (_selectedCity == null) {
      items = _cities;
      title = '选择城市';
      onSelected = _onCitySelected;
    } else {
      items = _districts;
      title = '选择区县（可选）';
      onSelected = _onDistrictSelected;
    }

    if (items.isEmpty && _selectedCity != null) {
      // 没有区县数据，显示提示
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '已选择：$_selectedCity',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击"确定"完成选择',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            // 性能优化
            cacheExtent: 300,
            addRepaintBoundaries: true,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected =
                  (_selectedProvince == null && item == _selectedProvince) ||
                  (_selectedCity == null && item == _selectedCity) ||
                  (_selectedDistrict != null && item == _selectedDistrict);

              return ListTile(
                title: Text(item),
                trailing: isSelected
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : const Icon(Icons.chevron_right),
                onTap: () => onSelected(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
