/// 成绩单页面
/// 展示学期成绩和统计信息
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';

/// 成绩单屏幕
class GradesScreen extends StatefulWidget {
  final DataManager dataManager;

  const GradesScreen({super.key, required this.dataManager});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen>
    with AutomaticKeepAliveClientMixin {
  String? _selectedSemester;

  @override
  bool get wantKeepAlive => false; // 禁用以减少内存占用

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.dataManager,
      builder: (context, child) {
        final isLoading =
            widget.dataManager.gradesState == LoadingState.loading;
        final hasError = widget.dataManager.gradesState == LoadingState.error;
        final grades = widget.dataManager.grades;

        // 初始化选中学期
        if (_selectedSemester == null && grades != null && grades.isNotEmpty) {
          _selectedSemester = grades.first.semester;
        }

        final currentGrades = grades?.isNotEmpty == true
            ? grades!.firstWhere(
                (g) => g.semester == _selectedSemester,
                orElse: () => grades.first,
              )
            : null;

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () => widget.dataManager.loadGrades(forceRefresh: true),
            child: CustomScrollView(
              slivers: [
                // 顶部区域
                SliverAppBar(
                  expandedHeight: 120,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      '成绩单',
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
                            : () => widget.dataManager.loadGrades(
                                forceRefresh: true,
                              ),
                      ),
                    ),
                  ],
                ),

                // 内容区域
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 加载状态
                      if (isLoading && grades == null) ...[
                        _buildLoadingState(colorScheme),
                      ],

                      // 错误状态
                      if (hasError && grades == null) ...[
                        _buildErrorState(theme, colorScheme),
                      ],

                      // 数据内容
                      if (grades != null && grades.isNotEmpty) ...[
                        // 学期选择器
                        _buildSemesterSelector(theme, colorScheme, grades),
                        const SizedBox(height: 20),

                        // 统计卡片
                        if (currentGrades != null)
                          _buildStatisticsCard(
                            theme,
                            colorScheme,
                            currentGrades,
                          ),
                        const SizedBox(height: 20),

                        // 成绩列表标题
                        Row(
                          children: [
                            Text(
                              '课程成绩',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${currentGrades?.grades.length ?? 0}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isLoading) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 成绩列表
                        if (currentGrades != null)
                          ...currentGrades.grades.map(
                            (grade) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildGradeCard(theme, colorScheme, grade),
                            ),
                          ),
                      ],

                      // 空状态
                      if (grades != null && grades.isEmpty && !isLoading)
                        _buildEmptyState(theme, colorScheme),

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

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在加载成绩...',
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
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: theme.textTheme.titleLarge?.copyWith(
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  widget.dataManager.loadGrades(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.school_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无成绩数据',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '成绩数据可能还未录入',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  widget.dataManager.loadGrades(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterSelector(
    ThemeData theme,
    ColorScheme colorScheme,
    List<SemesterGrades> grades,
  ) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        // 性能优化
        cacheExtent: 150,
        addRepaintBoundaries: true,
        itemCount: grades.length,
        itemBuilder: (context, index) {
          final semester = grades[index].semester;
          final isSelected = semester == _selectedSemester;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(semester),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedSemester = semester;
                });
              },
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide.none,
              backgroundColor: colorScheme.surfaceContainerHigh,
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatisticsCard(
    ThemeData theme,
    ColorScheme colorScheme,
    SemesterGrades grades,
  ) {
    final avgGpa = grades.averageGpa;
    final totalCredits = grades.totalCredits;
    final earnedCredits = grades.earnedCredits;
    final passRate = grades.grades.isEmpty
        ? 0.0
        : grades.grades.where((g) => g.isPassed).length / grades.grades.length;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // GPA 大字显示
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '平均绩点',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        avgGpa?.toStringAsFixed(2) ?? '--',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                // GPA 进度圆环
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: (avgGpa ?? 0) / 4.0,
                        strokeWidth: 8,
                        backgroundColor: colorScheme.outline.withValues(
                          alpha: 0.2,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary,
                        ),
                        strokeCap: StrokeCap.round,
                      ),
                      Text(
                        '${((avgGpa ?? 0) / 4.0 * 100).toInt()}%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 统计数据行
            Row(
              children: [
                _buildStatItem(
                  theme,
                  colorScheme,
                  Icons.school_outlined,
                  '总学分',
                  totalCredits.toStringAsFixed(1),
                ),
                _buildStatItem(
                  theme,
                  colorScheme,
                  Icons.check_circle_outline,
                  '已获学分',
                  earnedCredits.toStringAsFixed(1),
                ),
                _buildStatItem(
                  theme,
                  colorScheme,
                  Icons.trending_up,
                  '通过率',
                  '${(passRate * 100).toInt()}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    ColorScheme colorScheme,
    IconData icon,
    String label,
    String value,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
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
        ),
      ),
    );
  }

  Widget _buildGradeCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Grade grade,
  ) {
    // 根据成绩确定颜色
    Color scoreColor;
    final numScore = double.tryParse(grade.score);
    if (numScore != null) {
      if (numScore >= 90) {
        scoreColor = Colors.green;
      } else if (numScore >= 80) {
        scoreColor = colorScheme.primary;
      } else if (numScore >= 70) {
        scoreColor = Colors.orange;
      } else if (numScore >= 60) {
        scoreColor = Colors.amber;
      } else {
        scoreColor = colorScheme.error;
      }
    } else {
      // 等级制成绩
      if (grade.score == '优' || grade.score == '优秀') {
        scoreColor = Colors.green;
      } else if (grade.score == '良' || grade.score == '良好') {
        scoreColor = colorScheme.primary;
      } else if (grade.score == '中' || grade.score == '中等') {
        scoreColor = Colors.orange;
      } else if (grade.score == '及格' || grade.score == '合格') {
        scoreColor = Colors.amber;
      } else {
        scoreColor = colorScheme.error;
      }
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showGradeDetail(grade),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 成绩显示
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  grade.score,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 课程信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grade.courseName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildInfoChip(theme, colorScheme, '${grade.credit}学分'),
                        const SizedBox(width: 8),
                        if (grade.gpa != null)
                          _buildInfoChip(theme, colorScheme, '绩点${grade.gpa}'),
                      ],
                    ),
                  ],
                ),
              ),
              // 课程类型
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: grade.courseType == '必修'
                      ? colorScheme.primaryContainer
                      : colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  grade.courseType ?? '未知',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: grade.courseType == '必修'
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, ColorScheme colorScheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.outline.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _showGradeDetail(Grade grade) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            Text(
              grade.courseName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailRow(Icons.score_outlined, '成绩', grade.score),
            if (grade.gpa != null)
              _buildDetailRow(Icons.star_outline, '绩点', grade.gpa.toString()),
            _buildDetailRow(Icons.school_outlined, '学分', '${grade.credit}'),
            if (grade.courseType != null)
              _buildDetailRow(
                Icons.category_outlined,
                '课程性质',
                grade.courseType!,
              ),
            if (grade.examType != null)
              _buildDetailRow(
                Icons.assignment_outlined,
                '考试类型',
                grade.examType!,
              ),
            if (grade.teacher != null)
              _buildDetailRow(Icons.person_outline, '教师', grade.teacher!),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
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
