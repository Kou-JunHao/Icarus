/// 课程表页面
/// 完整周视图的课程表展示
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../models/models.dart';
import '../services/services.dart';

/// 平滑的页面滑动物理效果
/// 优化滑动响应速度和动画流畅度
class _SmoothPagePhysics extends ScrollPhysics {
  const _SmoothPagePhysics({super.parent});

  @override
  _SmoothPagePhysics applyTo(ScrollPhysics? ancestor) {
    return _SmoothPagePhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
    mass: 0.5, // 降低质量使动画更快
    stiffness: 200, // 提高刚度使响应更灵敏
    damping: 30, // 适度阻尼防止过度弹跳
  );

  @override
  double get minFlingVelocity => 50.0; // 降低最小滑动速度阈值

  @override
  double get maxFlingVelocity => 8000.0;

  @override
  double get dragStartDistanceMotionThreshold => 3.0; // 更快响应拖动
}

/// 课程颜色配置 - Material 3 风格配色
class CourseColors {
  static const List<Color> palette = [
    Color(0xFF6750A4), // Primary Purple
    Color(0xFF625B71), // Secondary
    Color(0xFF7D5260), // Tertiary
    Color(0xFF006A6A), // Teal
    Color(0xFFBA1A1A), // Error Red
    Color(0xFF4A6741), // Green
    Color(0xFF8B5000), // Orange
    Color(0xFF006493), // Blue
    Color(0xFF984061), // Pink
    Color(0xFF5B5B8A), // Indigo
  ];

  static Color getColor(String name) {
    return palette[name.hashCode.abs() % palette.length];
  }
}

/// 课程表屏幕
class ScheduleScreen extends StatefulWidget {
  final DataManager dataManager;

  const ScheduleScreen({super.key, required this.dataManager});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  int _selectedWeek = 1;
  final ScrollController _weekScrollController = ScrollController();
  PageController? _schedulePageController; // 课程表滑动控制器
  bool _showTimeColumn = true; // 是否显示时间列
  bool _isPageAnimating = false; // 防止滑动时重复更新

  // 返回本周按钮动画
  AnimationController? _backToWeekAnimController;
  bool _isBackToWeekAnimating = false;

  // 课程表配置
  int _totalSections = 12; // 总节数（动态）
  static const double _headerHeight = 44.0;
  static const double _timeColumnWidth = 42.0;
  static const double _sectionHeight = 52.0;

  // 课程表设置
  ScheduleSettings _scheduleSettings = AuthStorage.defaultScheduleSettings;

  // 当前使用的时间表
  Map<int, (String, String)> _sectionTimes = {};

  // 缓存计算结果
  Map<int, List<DateTime>>? _cachedWeekDates;
  int? _cachedWeekDatesKey;

  @override
  bool get wantKeepAlive => false; // 禁用以减少内存占用

  @override
  void initState() {
    super.initState();
    // 加载课程表设置和时间表
    _loadScheduleSettings();
    // 初始化选中周为当前周
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentWeek = widget.dataManager.currentWeek;
      setState(() {
        _selectedWeek = currentWeek;
        // 初始化 PageController，设置初始页为当前周
        _schedulePageController = PageController(initialPage: currentWeek - 1);
      });
      _scrollToWeek(currentWeek);
    });
  }

  /// 加载课程表设置和时间表
  Future<void> _loadScheduleSettings() async {
    // 首先加载设置
    final settings = await AuthStorage.getScheduleSettings();
    // 检查是否有自定义时间表
    final customTimetable = await AuthStorage.getCustomTimetable();

    if (mounted) {
      setState(() {
        _scheduleSettings = settings;
        _totalSections = settings.totalSections;
        // 优先使用自定义时间表，否则根据设置生成
        _sectionTimes =
            customTimetable ?? AuthStorage.generateTimetable(settings);
      });
    }

    // 检查是否设置了学期开始日期
    _checkSemesterStartDate();
  }

  /// 检查学期开始日期是否已设置，未设置则提示用户
  Future<void> _checkSemesterStartDate() async {
    final startDate = await AuthStorage.getSemesterStartDate();
    if (startDate == null && mounted) {
      // 延迟显示提示，避免页面加载时立即弹出
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showSemesterStartDatePrompt();
      }
    }
  }

  /// 显示学期开始日期设置提示
  void _showSemesterStartDatePrompt() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isDismissible: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示器
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // 图标
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 32,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            // 标题
            Text(
              '设置学期开始日期',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // 说明
            Text(
              '设置学期开始日期后，可以自动计算当前周次，让课程表更加准确。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // 按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('稍后设置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showScheduleSettings();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('立即设置'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// 根据当前设置重新生成时间表
  void _regenerateTimetable() {
    setState(() {
      _totalSections = _scheduleSettings.totalSections;
      _sectionTimes = AuthStorage.generateTimetable(_scheduleSettings);
    });
    // 保存生成的时间表
    AuthStorage.saveCustomTimetable(_sectionTimes);
  }

  /// 显示时间表编辑器
  void _showTimetableEditor() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 创建临时编辑用的时间表副本
    final editingTimes = Map<int, (String, String)>.from(_sectionTimes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
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
              // 标题栏
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        '编辑时间表',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        // 保存并关闭
                        await AuthStorage.saveCustomTimetable(editingTimes);
                        setState(() {
                          _sectionTimes = Map.from(editingTimes);
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ),
              // 重置按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          editingTimes.clear();
                          editingTimes.addAll(
                            AuthStorage.generateTimetable(_scheduleSettings),
                          );
                        });
                      },
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('恢复默认'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '点击时间可编辑',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // 时间表列表
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _totalSections,
                  itemBuilder: (context, index) {
                    final section = index + 1;
                    final times = editingTimes[section] ?? ('--:--', '--:--');

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0,
                      color: colorScheme.surfaceContainerHigh,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            // 节次
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$section',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // 开始时间
                            Expanded(
                              child: _buildTimeButton(
                                context,
                                theme,
                                colorScheme,
                                '开始',
                                times.$1,
                                (newTime) {
                                  setModalState(() {
                                    editingTimes[section] = (newTime, times.$2);
                                  });
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            // 结束时间
                            Expanded(
                              child: _buildTimeButton(
                                context,
                                theme,
                                colorScheme,
                                '结束',
                                times.$2,
                                (newTime) {
                                  setModalState(() {
                                    editingTimes[section] = (times.$1, newTime);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建时间选择按钮
  Widget _buildTimeButton(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String time,
    Function(String) onChanged,
  ) {
    return InkWell(
      onTap: () => _showTimePicker(context, time, onChanged),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant, width: 1),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示时间选择器
  Future<void> _showTimePicker(
    BuildContext context,
    String currentTime,
    Function(String) onChanged,
  ) async {
    // 解析当前时间
    final parts = currentTime.split(':');
    final hour = parts.length >= 1 ? int.tryParse(parts[0]) ?? 8 : 8;
    final minute = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final newTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      onChanged(newTime);
    }
  }

  @override
  void dispose() {
    _weekScrollController.dispose();
    _schedulePageController?.dispose();
    _backToWeekAnimController?.dispose();
    super.dispose();
  }

  void _scrollToWeek(int week, {bool animatePageView = true}) {
    // 滚动周选择器
    if (_weekScrollController.hasClients) {
      final offset = (week - 1) * 52.0 - 100;
      _weekScrollController.animateTo(
        offset.clamp(0, _weekScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
    // 滚动课程表 PageView
    if (animatePageView && _schedulePageController?.hasClients == true) {
      final currentPage = _schedulePageController!.page?.round() ?? 0;
      final targetPage = week - 1;
      final pageDistance = (targetPage - currentPage).abs();

      // 如果跨度超过3页，直接跳转避免卡顿
      if (pageDistance > 3) {
        _schedulePageController!.jumpToPage(targetPage);
      } else {
        _isPageAnimating = true;
        _schedulePageController!
            .animateToPage(
              targetPage,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              Future.delayed(const Duration(milliseconds: 50), () {
                _isPageAnimating = false;
              });
            });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.dataManager,
      builder: (context, child) {
        final isLoading =
            widget.dataManager.scheduleState == LoadingState.loading;
        final hasError = widget.dataManager.scheduleState == LoadingState.error;
        final schedule = widget.dataManager.schedule;
        final currentWeek = widget.dataManager.currentWeek;

        // 确保选中周不超过总周数
        final totalWeeks = schedule?.totalWeeks ?? 20;
        if (_selectedWeek > totalWeeks) {
          _selectedWeek = currentWeek;
        }

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Column(
            children: [
              // 顶部区域
              _buildHeader(
                theme,
                colorScheme,
                schedule,
                currentWeek,
                totalWeeks,
                isLoading,
              ),
              // 周次选择器
              _buildWeekSelector(theme, colorScheme, totalWeeks, currentWeek),
              // 课程表主体（支持左右滑动切换周数）
              Expanded(
                child: isLoading
                    ? _buildLoadingState(colorScheme)
                    : hasError
                    ? _buildErrorState(theme, colorScheme)
                    : schedule == null
                    ? _buildEmptyState(theme, colorScheme)
                    : _buildSwipeableSchedule(
                        theme,
                        colorScheme,
                        schedule,
                        totalWeeks,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    Schedule? schedule,
    int currentWeek,
    int totalWeeks,
    bool isLoading,
  ) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showWeekPicker(totalWeeks, currentWeek),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '第 $_selectedWeek 周',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                        if (_selectedWeek == currentWeek)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '本周',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      schedule?.semester ?? '加载中...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 返回本周按钮 - 带缩小移动动画
            _buildBackToWeekButton(colorScheme, currentWeek),
            // 刷新按钮
            IconButton(
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: isLoading
                  ? null
                  : () => widget.dataManager.loadSchedule(forceRefresh: true),
              tooltip: '刷新',
            ),
            // 设置按钮
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => _showScheduleSettings(),
              tooltip: '课程表设置',
            ),
          ],
        ),
      ),
    );
  }

  /// 构建返回本周按钮，带缩小移动动画
  Widget _buildBackToWeekButton(ColorScheme colorScheme, int currentWeek) {
    final showButton = _selectedWeek != currentWeek && !_isBackToWeekAnimating;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axis: Axis.horizontal,
            child: child,
          ),
        );
      },
      child: showButton
          ? Padding(
              key: const ValueKey('back_to_week_btn'),
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => _animateBackToCurrentWeek(currentWeek),
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('返回本周'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('empty')),
    );
  }

  /// 执行返回本周的动画
  void _animateBackToCurrentWeek(int currentWeek) {
    // 设置动画状态
    setState(() {
      _isBackToWeekAnimating = true;
    });

    // 同时执行周切换
    setState(() {
      _selectedWeek = currentWeek;
    });
    _scrollToWeek(currentWeek);

    // 动画完成后重置状态
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isBackToWeekAnimating = false;
        });
      }
    });
  }

  void _showWeekPicker(int totalWeeks, int currentWeek) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择周次',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedWeek = currentWeek;
                      });
                      _scrollToWeek(currentWeek);
                    },
                    child: const Text('返回本周'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 周次网格
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: totalWeeks,
                itemBuilder: (context, index) {
                  final week = index + 1;
                  final isSelected = week == _selectedWeek;
                  final isCurrent = week == currentWeek;

                  return Material(
                    color: isSelected
                        ? colorScheme.primary
                        : isCurrent
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedWeek = week;
                        });
                        _scrollToWeek(week);
                      },
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$week',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: isSelected
                                    ? colorScheme.onPrimary
                                    : isCurrent
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isCurrent && !isSelected)
                              Text(
                                '本周',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekSelector(
    ThemeData theme,
    ColorScheme colorScheme,
    int totalWeeks,
    int currentWeek,
  ) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 2),
      child: ListView.builder(
        controller: _weekScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // 性能优化：添加缓存
        cacheExtent: 200,
        // 性能优化：添加重绘边界
        addRepaintBoundaries: true,
        itemCount: totalWeeks,
        itemBuilder: (context, index) {
          final week = index + 1;
          final isSelected = week == _selectedWeek;
          final isCurrent = week == currentWeek;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Material(
              color: isSelected
                  ? colorScheme.primary
                  : isCurrent
                  ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                  : colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedWeek = week;
                  });
                  _scrollToWeek(week);
                },
                child: SizedBox(
                  width: 40,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$week',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isSelected
                                ? colorScheme.onPrimary
                                : isCurrent
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isCurrent && !isSelected)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '正在加载课程表...',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '加载失败',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.dataManager.errorMessage ?? '请检查网络连接后重试',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () =>
                  widget.dataManager.loadSchedule(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_note_rounded,
                size: 56,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无课程数据',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '尝试刷新或检查网络连接',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () =>
                  widget.dataManager.loadSchedule(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建可滑动切换周数的课程表
  Widget _buildSwipeableSchedule(
    ThemeData theme,
    ColorScheme colorScheme,
    Schedule schedule,
    int totalWeeks,
  ) {
    // 如果 PageController 还没初始化，先显示当前周
    if (_schedulePageController == null) {
      return _buildScheduleTable(theme, colorScheme, schedule, _selectedWeek);
    }

    return PageView.builder(
      controller: _schedulePageController,
      // 使用更流畅的物理效果
      physics: const _SmoothPagePhysics(),
      // 预加载相邻页面以提升滑动流畅度
      allowImplicitScrolling: true,
      itemCount: totalWeeks,
      onPageChanged: (index) {
        if (_isPageAnimating) return;
        final newWeek = index + 1;
        if (_selectedWeek == newWeek) return;

        // 直接更新状态
        setState(() {
          _selectedWeek = newWeek;
        });
        // 只滚动周选择器，不滚动 PageView
        _scrollToWeek(newWeek, animatePageView: false);
      },
      itemBuilder: (context, index) {
        final week = index + 1;
        // 使用 RepaintBoundary 隔离每个页面的重绘
        return RepaintBoundary(
          child: _buildScheduleTable(theme, colorScheme, schedule, week),
        );
      },
    );
  }

  Widget _buildScheduleTable(
    ThemeData theme,
    ColorScheme colorScheme,
    Schedule schedule,
    int displayWeek,
  ) {
    final now = DateTime.now();
    final todayWeekday = now.weekday;
    final currentWeek = widget.dataManager.currentWeek;

    // 判断周六周日是否有课程（针对显示的周）
    final hasWeekendCourses = _hasCoursesOnWeekend(schedule, displayWeek);
    final displayDays = hasWeekendCourses ? 7 : 5;
    // 周末时使用更短的名称
    final weekdayNames = hasWeekendCourses
        ? ['一', '二', '三', '四', '五', '六', '日']
        : ['一', '二', '三', '四', '五'];

    // 获取显示周的日期
    final weekDates = _getWeekDates(displayWeek, currentWeek);

    // 计算课程表总高度
    final tableHeight = _sectionHeight * _totalSections;

    // 计算时间列实际宽度
    final timeColWidth = _showTimeColumn ? _timeColumnWidth : 24.0;

    // 判断当天高亮（仅当显示的是当前周时）
    final isCurrentWeek = displayWeek == currentWeek;

    return RefreshIndicator(
      onRefresh: () => widget.dataManager.loadSchedule(forceRefresh: true),
      color: colorScheme.primary,
      child: SingleChildScrollView(
        // 性能优化：使用 ClampingScrollPhysics 减少弹性计算
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            children: [
              // 星期标题行 - 带日期
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    // 左上角 - 时间/节次切换按钮（长按编辑时间表）
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showTimeColumn = !_showTimeColumn;
                        });
                      },
                      onLongPress: () => _showTimetableEditor(),
                      child: SizedBox(
                        width: timeColWidth,
                        height: _headerHeight,
                        child: Center(
                          child: Icon(
                            _showTimeColumn ? Icons.schedule : Icons.tag,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    // 星期标题
                    ...List.generate(displayDays, (index) {
                      final isToday =
                          (index + 1) == todayWeekday && isCurrentWeek;
                      final date = weekDates.length > index
                          ? weekDates[index]
                          : null;

                      return Expanded(
                        child: Container(
                          height: _headerHeight,
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: BoxDecoration(
                            color: isToday
                                ? colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                weekdayNames[index],
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isToday
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: hasWeekendCourses ? 12 : 13,
                                ),
                              ),
                              if (date != null)
                                Text(
                                  '${date.day}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isToday
                                        ? colorScheme.onPrimary.withValues(
                                            alpha: 0.85,
                                          )
                                        : colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              // 课程表格 - 使用 Stack 布局
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧时间/节次列
                    SizedBox(
                      width: timeColWidth,
                      height: tableHeight,
                      child: Column(
                        children: List.generate(_totalSections, (index) {
                          final section = index + 1;
                          final times = _sectionTimes[section];
                          return SizedBox(
                            height: _sectionHeight,
                            child: Center(
                              child: _showTimeColumn && times != null
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          times.$1.substring(0, 5),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        Container(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '$section',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 9,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          times.$2.substring(0, 5),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.7),
                                                fontSize: 8,
                                              ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      '$section',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 10,
                                          ),
                                    ),
                            ),
                          );
                        }),
                      ),
                    ),
                    // 课程区域
                    Expanded(
                      child: SizedBox(
                        height: tableHeight,
                        child: Row(
                          children: List.generate(displayDays, (dayIndex) {
                            final weekday = dayIndex + 1;
                            final isToday =
                                weekday == todayWeekday && isCurrentWeek;

                            return Expanded(
                              child: _buildDayColumn(
                                theme,
                                colorScheme,
                                schedule,
                                weekday,
                                isToday,
                                displayWeek,
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建某一天的课程列
  Widget _buildDayColumn(
    ThemeData theme,
    ColorScheme colorScheme,
    Schedule schedule,
    int weekday,
    bool isToday,
    int displayWeek,
  ) {
    // 获取这一天的所有本周课程
    final currentWeekCourses = schedule.courses
        .where((c) => c.weekday == weekday && c.isInWeek(displayWeek))
        .toList();

    // 如果开启了显示非本周课程，获取非本周的课程（周六周日除外）
    List<Course> nonCurrentWeekCourses = [];
    if (_scheduleSettings.showNonCurrentWeekCourses && weekday <= 5) {
      // 只在周一到周五显示非本周课程
      nonCurrentWeekCourses = schedule.courses
          .where((c) => c.weekday == weekday && !c.isInWeek(displayWeek))
          .toList();
    }

    final tableHeight = _sectionHeight * _totalSections;

    return SizedBox(
      height: tableHeight,
      child: Stack(
        children: [
          // 背景格子 - 使用 RepaintBoundary 隔离
          RepaintBoundary(
            child: Column(
              children: List.generate(_totalSections, (index) {
                return Container(
                  height: _sectionHeight,
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.3),
                    border: Border(
                      bottom: index < _totalSections - 1
                          ? BorderSide(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.1,
                              ),
                              width: 0.5,
                            )
                          : BorderSide.none,
                    ),
                  ),
                );
              }),
            ),
          ),
          // 非本周课程卡片（先绘制，在底层）
          ...nonCurrentWeekCourses.map((course) {
            // 检查是否与本周课程时间冲突
            final hasConflict = currentWeekCourses.any(
              (c) =>
                  (course.startSection <= c.endSection &&
                  course.endSection >= c.startSection),
            );
            // 如果有冲突，不显示非本周课程
            if (hasConflict) return const SizedBox.shrink();

            final top = (course.startSection - 1) * _sectionHeight;
            final height = course.sectionCount * _sectionHeight;

            return Positioned(
              top: top,
              left: 0,
              right: 0,
              height: height,
              child: RepaintBoundary(
                child: _buildCourseCell(
                  theme,
                  colorScheme,
                  course,
                  height,
                  isToday,
                  isNonCurrentWeek: true,
                ),
              ),
            );
          }),
          // 本周课程卡片（后绘制，在上层）
          ...currentWeekCourses.map((course) {
            final top = (course.startSection - 1) * _sectionHeight;
            final height = course.sectionCount * _sectionHeight;

            return Positioned(
              top: top,
              left: 0,
              right: 0,
              height: height,
              child: RepaintBoundary(
                child: _buildCourseCell(
                  theme,
                  colorScheme,
                  course,
                  height,
                  isToday,
                  isNonCurrentWeek: false,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 获取指定周的日期列表（带缓存）
  List<DateTime> _getWeekDates(int selectedWeek, int currentWeek) {
    // 使用缓存避免重复计算
    final cacheKey = selectedWeek * 100 + currentWeek;
    if (_cachedWeekDatesKey == cacheKey && _cachedWeekDates != null) {
      return _cachedWeekDates![selectedWeek] ??
          _calculateWeekDates(selectedWeek, currentWeek);
    }

    final dates = _calculateWeekDates(selectedWeek, currentWeek);
    _cachedWeekDatesKey = cacheKey;
    _cachedWeekDates = {selectedWeek: dates};
    return dates;
  }

  List<DateTime> _calculateWeekDates(int selectedWeek, int currentWeek) {
    final now = DateTime.now();
    final todayWeekday = now.weekday;
    // 计算当前周的周一
    final currentMonday = now.subtract(Duration(days: todayWeekday - 1));
    // 计算选中周的周一
    final weekDiff = selectedWeek - currentWeek;
    final selectedMonday = currentMonday.add(Duration(days: weekDiff * 7));

    return List.generate(
      7,
      (index) => selectedMonday.add(Duration(days: index)),
    );
  }

  /// 检查选中周的周六周日是否有课程
  bool _hasCoursesOnWeekend(Schedule schedule, int week) {
    // 只检查本周是否有周末课程（周末不显示非本周课程）
    return schedule.courses.any(
      (c) => (c.weekday == 6 || c.weekday == 7) && c.isInWeek(week),
    );
  }

  Widget _buildCourseCell(
    ThemeData theme,
    ColorScheme colorScheme,
    Course course,
    double height,
    bool isToday, {
    bool isNonCurrentWeek = false,
  }) {
    final color = CourseColors.getColor(course.name);

    // 本周课程使用更饱和的颜色，非本周课程使用更淡的颜色，增强对比
    final displayColor = isNonCurrentWeek
        ? color.withValues(alpha: 0.35)
        : color;
    final bgColor = isNonCurrentWeek
        ? Color.lerp(color, colorScheme.surface, 0.95)! // 非本周更淡
        : Color.lerp(color, colorScheme.surface, 0.78)!; // 本周更饱和
    final borderColor = isNonCurrentWeek
        ? Color.lerp(color, colorScheme.surface, 0.8)!
        : Color.lerp(color, colorScheme.surface, 0.4)!; // 本周边框更明显

    return Container(
      height: height,
      margin: const EdgeInsets.all(0.5), // 极小间距用于视觉分隔
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _showCourseDetail(course),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(
                color: isToday && !isNonCurrentWeek
                    ? color.withValues(alpha: 0.6)
                    : borderColor.withValues(
                        alpha: isNonCurrentWeek ? 0.3 : 0.2,
                      ),
                width: isToday && !isNonCurrentWeek ? 1.0 : 0.5,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight - 6;
                // 非本周课程需要额外空间显示标签，所以降低阈值
                final showLocation =
                    availableHeight > (isNonCurrentWeek ? 45 : 35);
                final showTeacher =
                    availableHeight > (isNonCurrentWeek ? 65 : 55);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 非本周标签
                    if (isNonCurrentWeek) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '非本周',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 7,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    // 课程名称
                    Expanded(
                      flex: showTeacher ? 2 : (showLocation ? 2 : 1),
                      child: Text(
                        course.name,
                        style: TextStyle(
                          color: displayColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          height: 1.15,
                        ),
                        maxLines: isNonCurrentWeek
                            ? (showTeacher ? 1 : (showLocation ? 2 : 2))
                            : (showTeacher ? 2 : (showLocation ? 2 : 3)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 教师名称 - 优先显示教师
                    if (showTeacher && course.teacher != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 8,
                            color: displayColor.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 1),
                          Expanded(
                            child: Text(
                              course.teacher!,
                              style: TextStyle(
                                color: displayColor.withValues(alpha: 0.8),
                                fontSize: 8,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // 教室位置
                    if (showLocation && course.location != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 8,
                            color: displayColor.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 1),
                          Expanded(
                            child: Text(
                              course.location!,
                              style: TextStyle(
                                color: displayColor.withValues(alpha: 0.7),
                                fontSize: 8,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
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
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示器
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 课程名称头部
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 颜色标识
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '第${course.startSection}-${course.endSection}节',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 详情信息
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: Icons.person_rounded,
                      label: '授课教师',
                      value: course.teacher ?? '未知',
                      color: color,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      icon: Icons.location_on_rounded,
                      label: '上课地点',
                      value: course.location ?? '未知',
                      color: color,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      icon: Icons.calendar_month_rounded,
                      label: '上课周次',
                      value:
                          course.weekRange ??
                          '${course.weeks.first}-${course.weeks.last}周',
                      color: color,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      icon: Icons.schedule_rounded,
                      label: '上课时间',
                      value: _getCourseTimeString(course),
                      color: color,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取课程时间字符串
  String _getCourseTimeString(Course course) {
    final weekdayName = _getWeekdayName(course.weekday);
    final startTime = _sectionTimes[course.startSection];
    final endTime = _sectionTimes[course.endSection];

    if (startTime != null && endTime != null) {
      return '$weekdayName ${startTime.$1}-${endTime.$2}';
    }
    return weekdayName;
  }

  String _getWeekdayName(int weekday) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekday >= 1 && weekday <= 7 ? names[weekday - 1] : '未知';
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 显示课程表设置
  void _showScheduleSettings() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 创建临时编辑用的设置副本
    var editingSettings = _scheduleSettings;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
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
              // 标题栏
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        '课程表设置',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        // 保存设置
                        await AuthStorage.saveScheduleSettings(editingSettings);
                        // 根据设置生成新时间表
                        final newTimetable = AuthStorage.generateTimetable(
                          editingSettings,
                        );
                        await AuthStorage.saveCustomTimetable(newTimetable);

                        setState(() {
                          _scheduleSettings = editingSettings;
                          _totalSections = editingSettings.totalSections;
                          _sectionTimes = newTimetable;
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ),
              // 重置按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          editingSettings = AuthStorage.defaultScheduleSettings;
                        });
                      },
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('恢复默认'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${editingSettings.totalSections} 节课',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // 设置列表
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // 学期设置区（移到最上方）
                    _buildSettingsSection(
                      theme,
                      colorScheme,
                      '学期设置',
                      Icons.calendar_month_rounded,
                      [
                        _buildSemesterStartDateItem(
                          context,
                          theme,
                          colorScheme,
                          setModalState,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 时间设置区
                    _buildSettingsSection(
                      theme,
                      colorScheme,
                      '时间设置',
                      Icons.schedule_rounded,
                      [
                        _buildTimeSettingItem(
                          theme,
                          colorScheme,
                          '上午开始',
                          editingSettings.morningStartTime,
                          (time) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                morningStartTime: time,
                              );
                            });
                          },
                        ),
                        _buildTimeSettingItem(
                          theme,
                          colorScheme,
                          '下午开始',
                          editingSettings.afternoonStartTime,
                          (time) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                afternoonStartTime: time,
                              );
                            });
                          },
                        ),
                        _buildTimeSettingItem(
                          theme,
                          colorScheme,
                          '晚上开始',
                          editingSettings.eveningStartTime,
                          (time) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                eveningStartTime: time,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 节数设置区
                    _buildSettingsSection(
                      theme,
                      colorScheme,
                      '节数设置',
                      Icons.view_agenda_rounded,
                      [
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '上午节数',
                          editingSettings.morningSections,
                          1,
                          6,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                morningSections: value,
                              );
                            });
                          },
                        ),
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '下午节数',
                          editingSettings.afternoonSections,
                          1,
                          6,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                afternoonSections: value,
                              );
                            });
                          },
                        ),
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '晚上节数',
                          editingSettings.eveningSections,
                          0,
                          6,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                eveningSections: value,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 课时设置区
                    _buildSettingsSection(
                      theme,
                      colorScheme,
                      '课时设置',
                      Icons.timer_rounded,
                      [
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '每节课时长',
                          editingSettings.classDuration,
                          30,
                          60,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                classDuration: value,
                              );
                            });
                          },
                          suffix: '分钟',
                        ),
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '小课间',
                          editingSettings.shortBreak,
                          0,
                          20,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                shortBreak: value,
                              );
                            });
                          },
                          suffix: '分钟',
                        ),
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '大课间',
                          editingSettings.longBreak,
                          10,
                          40,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                longBreak: value,
                              );
                            });
                          },
                          suffix: '分钟',
                        ),
                        _buildNumberSettingItem(
                          theme,
                          colorScheme,
                          '大课间间隔',
                          editingSettings.longBreakInterval,
                          1,
                          4,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                longBreakInterval: value,
                              );
                            });
                          },
                          suffix: '节课',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 显示设置区
                    _buildSettingsSection(
                      theme,
                      colorScheme,
                      '显示设置',
                      Icons.visibility_rounded,
                      [
                        _buildSwitchSettingItem(
                          theme,
                          colorScheme,
                          '显示非本周课程',
                          '以降低对比度方式显示其他周的课程',
                          editingSettings.showNonCurrentWeekCourses,
                          (value) {
                            setModalState(() {
                              editingSettings = editingSettings.copyWith(
                                showNonCurrentWeekCourses: value,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 其他操作
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHigh,
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.edit_calendar_rounded,
                              color: colorScheme.primary,
                            ),
                            title: const Text('编辑详细时间表'),
                            subtitle: const Text('微调每节课的具体时间'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(context);
                              _showTimetableEditor();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 预览时间表
                    _buildTimetablePreview(theme, colorScheme, editingSettings),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建设置分区
  Widget _buildSettingsSection(
    ThemeData theme,
    ColorScheme colorScheme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  /// 构建时间设置项
  Widget _buildTimeSettingItem(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String time,
    Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              final parts = time.split(':');
              final hour = int.tryParse(parts[0]) ?? 8;
              final minute = int.tryParse(parts[1]) ?? 0;

              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: hour, minute: minute),
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                final newTime =
                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                onChanged(newTime);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                time,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建数字设置项
  Widget _buildNumberSettingItem(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    int value,
    int min,
    int max,
    Function(int) onChanged, {
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          // 减少按钮
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
            iconSize: 24,
            color: value > min
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            visualDensity: VisualDensity.compact,
          ),
          // 数值显示
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              suffix != null ? '$value' : '$value',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // 增加按钮
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
            iconSize: 24,
            color: value < max
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            visualDensity: VisualDensity.compact,
          ),
          if (suffix != null)
            Text(
              suffix,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// 构建开关设置项
  Widget _buildSwitchSettingItem(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
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
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 构建学期开始日期设置项
  Widget _buildSemesterStartDateItem(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    StateSetter setModalState,
  ) {
    return FutureBuilder<DateTime?>(
      future: AuthStorage.getSemesterStartDate(),
      builder: (context, snapshot) {
        final startDate = snapshot.data;
        final displayText = startDate != null
            ? '${startDate.year}年${startDate.month}月${startDate.day}日'
            : '未设置';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '学期开始日期',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '用于计算当前周次',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _showSemesterStartDatePicker(
                  context,
                  startDate,
                  setModalState,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: startDate != null
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示学期开始日期选择器
  Future<void> _showSemesterStartDatePicker(
    BuildContext context,
    DateTime? currentDate,
    StateSetter setModalState,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      helpText: '选择学期开始日期',
    );

    if (picked != null && mounted) {
      // 保存开学日期
      await AuthStorage.saveSemesterStartDate(picked);

      // 刷新 UI
      setModalState(() {});

      // 刷新课程表以更新当前周
      widget.dataManager.loadSchedule(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已设置学期开始日期: ${picked.month}月${picked.day}日'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 构建时间表预览
  Widget _buildTimetablePreview(
    ThemeData theme,
    ColorScheme colorScheme,
    ScheduleSettings settings,
  ) {
    final previewTimetable = AuthStorage.generateTimetable(settings);
    final morningEnd = settings.morningSections;
    final afternoonEnd = morningEnd + settings.afternoonSections;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.preview_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '时间表预览',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 上午
            if (settings.morningSections > 0) ...[
              _buildPeriodLabel(
                theme,
                colorScheme,
                '上午',
                Icons.wb_sunny_outlined,
              ),
              ...List.generate(settings.morningSections, (i) {
                final section = i + 1;
                final times = previewTimetable[section];
                return _buildPreviewRow(theme, colorScheme, section, times);
              }),
            ],
            // 下午
            if (settings.afternoonSections > 0) ...[
              const SizedBox(height: 8),
              _buildPeriodLabel(
                theme,
                colorScheme,
                '下午',
                Icons.wb_twilight_outlined,
              ),
              ...List.generate(settings.afternoonSections, (i) {
                final section = morningEnd + i + 1;
                final times = previewTimetable[section];
                return _buildPreviewRow(theme, colorScheme, section, times);
              }),
            ],
            // 晚上
            if (settings.eveningSections > 0) ...[
              const SizedBox(height: 8),
              _buildPeriodLabel(
                theme,
                colorScheme,
                '晚上',
                Icons.nightlight_outlined,
              ),
              ...List.generate(settings.eveningSections, (i) {
                final section = afternoonEnd + i + 1;
                final times = previewTimetable[section];
                return _buildPreviewRow(theme, colorScheme, section, times);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodLabel(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(
    ThemeData theme,
    ColorScheme colorScheme,
    int section,
    (String, String)? times,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$section',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            times != null ? '${times.$1} - ${times.$2}' : '--:-- - --:--',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
