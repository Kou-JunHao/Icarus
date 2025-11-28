/// 个人中心页面
/// 用户信息和设置选项
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../services/services.dart';

/// 个人中心屏幕
class ProfileScreen extends StatefulWidget {
  final DataManager dataManager;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.dataManager,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => false; // 禁用以减少内存占用

  bool _notificationEnabled = false;
  int _notificationMinutesBefore = 15;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final enabled = await NotificationService().isNotificationEnabled();
    final minutes = await NotificationService().getMinutesBefore();
    if (mounted) {
      setState(() {
        _notificationEnabled = enabled;
        _notificationMinutesBefore = minutes;
      });
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
        final isLoading = widget.dataManager.userState == LoadingState.loading;
        final user = widget.dataManager.user;

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () =>
                widget.dataManager.loadUserInfo(forceRefresh: true),
            child: CustomScrollView(
              slivers: [
                // 顶部区域
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: colorScheme.primary,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colorScheme.primary, colorScheme.secondary],
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 头像
                            Hero(
                              tag: 'user_avatar',
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: colorScheme.onPrimary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: isLoading
                                      ? CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colorScheme.primary,
                                        )
                                      : Text(
                                          user?.name?.isNotEmpty == true
                                              ? user!.name!.substring(0, 1)
                                              : '?',
                                          style: theme.textTheme.headlineLarge
                                              ?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 姓名
                            Text(
                              user?.name ?? '加载中...',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // 学号
                            Text(
                              user?.studentId ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onPrimary.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 内容区域
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 基本信息卡片
                      _buildSectionTitle(theme, '基本信息'),
                      const SizedBox(height: 12),
                      _buildInfoCard(theme, colorScheme, user),
                      const SizedBox(height: 24),

                      // 学业概览
                      _buildSectionTitle(theme, '学业概览'),
                      const SizedBox(height: 12),
                      _buildAcademicCard(theme, colorScheme),
                      const SizedBox(height: 24),

                      // 设置选项
                      _buildSectionTitle(theme, '设置'),
                      const SizedBox(height: 12),
                      _buildSettingsCard(theme, colorScheme),
                      const SizedBox(height: 24),

                      // 其他选项
                      _buildSectionTitle(theme, '其他'),
                      const SizedBox(height: 12),
                      _buildOtherCard(theme, colorScheme),
                      const SizedBox(height: 24),

                      // 退出登录按钮
                      _buildLogoutButton(theme, colorScheme),

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

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, ColorScheme colorScheme, User? user) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _buildInfoRow(
              theme,
              colorScheme,
              Icons.school_outlined,
              '学院',
              user?.college ?? '加载中...',
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildInfoRow(
              theme,
              colorScheme,
              Icons.book_outlined,
              '专业',
              user?.major ?? '加载中...',
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildInfoRow(
              theme,
              colorScheme,
              Icons.people_outline,
              '班级',
              user?.className ?? '加载中...',
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildInfoRow(
              theme,
              colorScheme,
              Icons.calendar_today_outlined,
              '入学年份',
              user?.enrollmentYear ?? '加载中...',
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildInfoRow(
              theme,
              colorScheme,
              Icons.workspace_premium_outlined,
              '学习层次',
              user?.studyLevel ?? '加载中...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    ColorScheme colorScheme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 24, color: colorScheme.primary),
          const SizedBox(width: 16),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicCard(ThemeData theme, ColorScheme colorScheme) {
    final overallGpa = widget.dataManager.calculateOverallGpa();
    final totalCredits = widget.dataManager.calculateTotalCredits();

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: _buildAcademicItem(
                theme,
                colorScheme,
                Icons.stars_outlined,
                '总绩点',
                overallGpa?.toStringAsFixed(2) ?? '--',
              ),
            ),
            Container(
              width: 1,
              height: 50,
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _buildAcademicItem(
                theme,
                colorScheme,
                Icons.school_outlined,
                '已修学分',
                totalCredits > 0 ? totalCredits.toStringAsFixed(1) : '--',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademicItem(
    ThemeData theme,
    ColorScheme colorScheme,
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      children: [
        Icon(icon, size: 28, color: colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
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

  Widget _buildSettingsCard(ThemeData theme, ColorScheme colorScheme) {
    final themeService = ThemeService();

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _buildSettingItem(
              theme,
              colorScheme,
              Icons.palette_outlined,
              '主题设置',
              themeService.themeModeDisplayName,
              onTap: () => _showThemeDialog(),
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildSettingItem(
              theme,
              colorScheme,
              Icons.notifications_outlined,
              '通知设置',
              _notificationEnabled ? '已开启' : '已关闭',
              onTap: () => _showNotificationDialog(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _buildSettingItem(
              theme,
              colorScheme,
              Icons.info_outline,
              '关于应用',
              '版本 1.0.0',
              onTap: () => _showAboutDialog(),
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildSettingItem(
              theme,
              colorScheme,
              Icons.feedback_outlined,
              '反馈问题',
              'skkk@skkk.uno',
              onTap: () => _launchFeedbackEmail(),
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildSettingItem(
              theme,
              colorScheme,
              Icons.privacy_tip_outlined,
              '隐私政策',
              '',
              onTap: () {},
            ),
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),
            _buildSettingItem(
              theme,
              colorScheme,
              Icons.article_outlined,
              '开源许可',
              '',
              onTap: () => _showLicensesPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(
    ThemeData theme,
    ColorScheme colorScheme,
    IconData icon,
    String title,
    String subtitle, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(ThemeData theme, ColorScheme colorScheme) {
    return FilledButton.tonal(
      onPressed: () => _showLogoutConfirmDialog(),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.5),
        foregroundColor: colorScheme.error,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Text('退出登录'),
    );
  }

  void _showThemeDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final themeService = ThemeService();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '主题设置',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildThemeOption(
              context,
              '跟随系统',
              Icons.brightness_auto,
              ThemeMode.system,
              themeService.themeMode == ThemeMode.system,
            ),
            _buildThemeOption(
              context,
              '浅色模式',
              Icons.light_mode_outlined,
              ThemeMode.light,
              themeService.themeMode == ThemeMode.light,
            ),
            _buildThemeOption(
              context,
              '深色模式',
              Icons.dark_mode_outlined,
              ThemeMode.dark,
              themeService.themeMode == ThemeMode.dark,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    String title,
    IconData icon,
    ThemeMode mode,
    bool isSelected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeService = ThemeService();

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? colorScheme.primary : null,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: colorScheme.primary)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: () {
        themeService.setThemeMode(mode);
        Navigator.pop(context);
        // 刷新当前页面以更新显示
        setState(() {});
      },
    );
  }

  Future<void> _launchFeedbackEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'skkk@skkk.uno',
      queryParameters: {'subject': '伊卡洛斯 - 问题反馈'},
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开邮件应用')));
      }
    }
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: '伊卡洛斯',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 SKKK. MIT License.',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.flight,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      children: [const Text('伊卡洛斯是一款校园服务聚合应用，帮助学生更便捷地管理课程和成绩。')],
    );
  }

  void _showLicensesPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Theme(
          data: Theme.of(context),
          child: const LicensePage(
            applicationName: '伊卡洛斯',
            applicationVersion: '1.0.0',
            applicationLegalese: '© 2025 SKKK. MIT License.',
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmDialog() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.dataManager.clearCache();
              widget.onLogout();
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _showNotificationDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final notificationService = NotificationService();

    // 可选的提前时间选项
    final minutesOptions = [5, 10, 15, 20, 30];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '通知设置',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              // 通知开关
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  title: const Text('课程提醒'),
                  subtitle: const Text('上课前发送通知提醒'),
                  value: _notificationEnabled,
                  onChanged: (value) async {
                    if (value) {
                      // 请求通知权限
                      final granted = await notificationService
                          .requestPermission();
                      if (!granted) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('请在系统设置中允许通知权限'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                        return;
                      }
                    }

                    await notificationService.setNotificationEnabled(value);
                    setModalState(() {
                      _notificationEnabled = value;
                    });
                    setState(() {});

                    // 如果启用了通知，立即安排通知
                    if (value && widget.dataManager.schedule != null) {
                      await notificationService.scheduleCourseNotifications(
                        schedule: widget.dataManager.schedule!,
                        currentWeek: widget.dataManager.currentWeek,
                      );
                    } else if (!value) {
                      // 如果关闭了通知，取消所有已安排的通知
                      await notificationService.cancelAllNotifications();
                    }
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 提前时间选择
              if (_notificationEnabled) ...[
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '提前提醒时间',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: minutesOptions.map((minutes) {
                            final isSelected =
                                minutes == _notificationMinutesBefore;
                            return ChoiceChip(
                              label: Text('$minutes 分钟'),
                              selected: isSelected,
                              onSelected: (selected) async {
                                if (selected) {
                                  await notificationService.setMinutesBefore(
                                    minutes,
                                  );
                                  setModalState(() {
                                    _notificationMinutesBefore = minutes;
                                  });
                                  setState(() {});

                                  // 重新安排通知
                                  if (widget.dataManager.schedule != null) {
                                    await notificationService
                                        .scheduleCourseNotifications(
                                          schedule:
                                              widget.dataManager.schedule!,
                                          currentWeek:
                                              widget.dataManager.currentWeek,
                                        );
                                  }
                                }
                              },
                              selectedColor: colorScheme.primary,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 测试通知按钮
                OutlinedButton.icon(
                  onPressed: () async {
                    await notificationService.showTestNotification();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已发送测试通知'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('发送测试通知'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
