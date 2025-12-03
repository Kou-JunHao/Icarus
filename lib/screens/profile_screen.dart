/// 个人中心页面
/// 用户信息和设置选项
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../services/services.dart';
import 'update_dialog.dart';
import 'account_manage_screen.dart';

/// 个人中心屏幕
class ProfileScreen extends StatefulWidget {
  final DataManager dataManager;
  final VoidCallback onLogout;
  final VoidCallback? onSwitchAccount;

  const ProfileScreen({
    super.key,
    required this.dataManager,
    required this.onLogout,
    this.onSwitchAccount,
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
  bool _workNotificationEnabled = true;
  bool _isAcademicExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final enabled = await NotificationService().isNotificationEnabled();
    final minutes = await NotificationService().getMinutesBefore();
    final workEnabled = await AuthStorage.isWorkNotificationEnabled();
    if (mounted) {
      setState(() {
        _notificationEnabled = enabled;
        _notificationMinutesBefore = minutes;
        _workNotificationEnabled = workEnabled;
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
            child: ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 80,
              ),
              children: [
                // 顶部用户信息
                _buildUserHeader(theme, colorScheme, user, isLoading),
                const SizedBox(height: 16),

                // 学业概览（可折叠）
                _buildAcademicCard(theme, colorScheme),
                const SizedBox(height: 12),

                // 基本信息
                _buildInfoCard(theme, colorScheme, user),
                const SizedBox(height: 12),

                // 设置
                _buildSettingsCard(theme, colorScheme),
                const SizedBox(height: 12),

                // 其他
                _buildOtherCard(theme, colorScheme),
                const SizedBox(height: 16),

                // 退出登录
                _buildLogoutButton(theme, colorScheme),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建用户头部信息
  Widget _buildUserHeader(
    ThemeData theme,
    ColorScheme colorScheme,
    User? user,
    bool isLoading,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 左侧信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 姓名
                  Text(
                    user?.name ?? '加载中...',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 学号
                  Text(
                    user?.studentId ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 学院/专业
                  Text(
                    '${user?.college ?? ''} · ${user?.major ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 右侧加载指示器
            if (isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, ColorScheme colorScheme, User? user) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildCompactInfoRow(
            theme,
            colorScheme,
            '班级',
            user?.className ?? '--',
          ),
          _buildCompactInfoRow(
            theme,
            colorScheme,
            '入学年份',
            user?.enrollmentYear ?? '--',
          ),
          _buildCompactInfoRow(
            theme,
            colorScheme,
            '学习层次',
            user?.studyLevel ?? '--',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoRow(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
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
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 头部（可点击展开/收起）
          InkWell(
            onTap: () =>
                setState(() => _isAcademicExpanded = !_isAcademicExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '学业概览',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // 简要信息
                  if (!_isAcademicExpanded) ...[
                    Text(
                      'GPA ${overallGpa?.toStringAsFixed(2) ?? '--'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: _isAcademicExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开内容
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildAcademicItem(
                      theme,
                      colorScheme,
                      '总绩点',
                      overallGpa?.toStringAsFixed(2) ?? '--',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: _buildAcademicItem(
                      theme,
                      colorScheme,
                      '已修学分',
                      totalCredits > 0 ? totalCredits.toStringAsFixed(1) : '--',
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _isAcademicExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicItem(
    ThemeData theme,
    ColorScheme colorScheme,
    String label,
    String value,
  ) {
    return Column(
      children: [
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildSettingItem(
            theme,
            colorScheme,
            Icons.manage_accounts_outlined,
            '账号管理',
            '多账号切换',
            onTap: () => _openAccountManage(),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
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
            indent: 16,
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
    );
  }

  /// 打开账号管理页面
  void _openAccountManage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountManageScreen(
          onAccountSwitch: () {
            // 账号切换后调用自动登录（而不是登出）
            Navigator.pop(context); // 先关闭账号管理页面
            widget.onSwitchAccount?.call();
          },
        ),
      ),
    );
  }

  Widget _buildOtherCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildSettingItem(
            theme,
            colorScheme,
            Icons.info_outline,
            '关于应用',
            '版本 ${UpdateService.currentVersion}',
            onTap: () => _showAboutDialog(),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
          _buildSettingItem(
            theme,
            colorScheme,
            Icons.system_update_outlined,
            '检查更新',
            '',
            onTap: () => _checkForUpdate(),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
          _buildSettingItem(
            theme,
            colorScheme,
            Icons.feedback_outlined,
            '反馈问题',
            '',
            onTap: () => _showFeedbackDialog(),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
          _buildSettingItem(
            theme,
            colorScheme,
            Icons.privacy_tip_outlined,
            '隐私政策',
            '',
            onTap: () => _showPrivacyPolicy(),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
          _buildSettingItem(
            theme,
            colorScheme,
            Icons.favorite_outline,
            '支持我',
            '',
            onTap: () => _showSupportDialog(),
          ),
        ],
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
      showDragHandle: false,
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

  /// 显示反馈弹窗
  void _showFeedbackDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
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
            // 标题
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.feedback_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  '反馈问题',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '选择你喜欢的方式向我们反馈',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // 反馈方式选项
            // 邮件反馈
            _buildFeedbackOption(
              theme,
              colorScheme,
              '发送邮件',
              'skkk@skkk.uno',
              Icons.email_outlined,
              colorScheme.primary,
              () async {
                Navigator.pop(context);
                // 使用手动构建的 mailto URL，避免编码问题
                final emailUrl =
                    'mailto:skkk@skkk.uno?subject=${Uri.encodeComponent('伊卡洛斯 - 问题反馈')}';
                final uri = Uri.parse(emailUrl);
                try {
                  final launched = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('无法打开邮件应用'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('无法打开邮件应用'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            // GitHub Issue
            _buildFeedbackOption(
              theme,
              colorScheme,
              '提交 Issue',
              'GitHub',
              Icons.bug_report_outlined,
              const Color(0xFF24292F),
              () {
                Navigator.pop(context);
                _launchUrl('https://github.com/Kou-JunHao/Icarus/issues/new');
              },
            ),
            const SizedBox(height: 20),
            Text(
              '感谢您的反馈！',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// 构建反馈选项
  Widget _buildFeedbackOption(
    ThemeData theme,
    ColorScheme colorScheme,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
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
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// 检查应用更新
  Future<void> _checkForUpdate() async {
    final colorScheme = Theme.of(context).colorScheme;

    // 显示检查中提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorScheme.onInverseSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text('正在检查更新...'),
          ],
        ),
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdate(
        ignoreSkipped: true,
      );

      if (!mounted) return;

      // 隐藏检查中提示
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (updateInfo != null) {
        // 显示更新对话框
        UpdateDialog.show(context, updateInfo: updateInfo);
      } else {
        // 已是最新版本
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 12),
                Text('当前已是最新版本'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAboutDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isScrollControlled: true,
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
            // 应用图标 - 使用前景图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorScheme.primary, colorScheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/app_icon_foreground.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 应用名称
            Text(
              '伊卡洛斯',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // 版本号
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v${UpdateService.currentVersion}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 应用描述
            Text(
              '伊卡洛斯是一款校园服务聚合应用，帮助学生更便捷地管理课程和成绩。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // 作者和项目地址
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // 作者
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '作者',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'SKKK',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 项目地址
                  InkWell(
                    onTap: () =>
                        _launchUrl('https://github.com/Kou-JunHao/Icarus'),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.code_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '项目地址',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'GitHub',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 开源许可证按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showLicensePage(
                    context: context,
                    applicationName: '伊卡洛斯',
                    applicationVersion: UpdateService.currentVersion,
                    applicationIcon: Container(
                      width: 64,
                      height: 64,
                      margin: const EdgeInsets.only(top: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colorScheme.primary, colorScheme.tertiary],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/app_icon_foreground.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('开源许可证'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 版权信息
            Text(
              '© 2025 SKKK. MIT License.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// 打开 URL
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 显示支持弹窗
  void _showSupportDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isScrollControlled: true,
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
            // 标题
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_rounded, color: Colors.red[400], size: 28),
                const SizedBox(width: 8),
                Text(
                  '支持我',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '如果这个应用对你有帮助，可以请我喝杯咖啡 ☕',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // 支持方式选项
            Row(
              children: [
                // 微信支付
                Expanded(
                  child: _buildSupportOption(
                    theme,
                    colorScheme,
                    '微信支付',
                    const Color(0xFF07C160),
                    Icons.chat_rounded,
                    () => _showQRCodeDialog(
                      '微信支付',
                      'assets/wechat_pay.png',
                      const Color(0xFF07C160),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 支付宝
                Expanded(
                  child: _buildSupportOption(
                    theme,
                    colorScheme,
                    '支付宝',
                    const Color(0xFF1677FF),
                    Icons.account_balance_wallet_rounded,
                    () => _showQRCodeDialog(
                      '支付宝',
                      'assets/alipay.png',
                      const Color(0xFF1677FF),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Buy me a Coffee
            SizedBox(
              width: double.infinity,
              child: _buildSupportOption(
                theme,
                colorScheme,
                'Buy me a Coffee',
                const Color(0xFFFFDD00),
                Icons.coffee_rounded,
                () {
                  Navigator.pop(context);
                  _launchUrl('https://buymeacoffee.com/skkk');
                },
                isWide: true,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '感谢您的支持！',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// 构建支持选项按钮
  Widget _buildSupportOption(
    ThemeData theme,
    ColorScheme colorScheme,
    String title,
    Color color,
    IconData icon,
    VoidCallback onTap, {
    bool isWide = false,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: isWide ? 16 : 20,
            horizontal: 16,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示二维码弹窗
  void _showQRCodeDialog(String title, String imagePath, Color color) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Navigator.pop(context); // 先关闭支持弹窗

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isScrollControlled: true,
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
            // 标题
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 20),
            // 二维码图片
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          size: 48,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '图片加载失败',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title == '支付宝' ? '请使用支付宝扫一扫' : '请使用微信扫一扫',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            // 返回按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showSupportDialog(); // 返回支持弹窗
                },
                child: const Text('返回'),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// 显示隐私政策弹窗
  void _showPrivacyPolicy() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // 拖拽指示器和标题
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.privacy_tip_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            '隐私政策',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 隐私政策内容
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        null,
                        '本应用尊重并保护用户的个人信息安全。为了向您提供课程表查询、成绩查询等服务，本隐私政策将向您说明我们如何处理您的个人信息。请在使用本应用前仔细阅读并理解本政策内容。',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '一、我们收集的信息及用途',
                        '本应用仅在必须时收集以下信息，用于登录学校教务系统及学习通平台，查询您的个人学业数据：\n\n'
                            '• 学号、密码：仅用于登录学校教务系统，以便获取您的课程表、成绩等信息。\n\n'
                            '• 学习通账号、密码（可选）：仅用于登录学习通平台，以便获取未交作业、进行中活动等信息。\n\n'
                            '上述信息不会保存到服务器，不会上传或共享，仅在本地设备存储和使用。\n\n'
                            '通过教务系统获取的信息包括：用户姓名、班级、专业、入学年份、课程表信息、成绩信息。\n\n'
                            '通过学习通平台获取的信息包括：课程列表、作业信息、活动信息（签到、测验等）。\n\n'
                            '上述数据仅用于展示与提供学习相关服务。',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '二、数据的存储方式',
                        '• 本应用不建立任何服务器数据库，不进行云端存储。\n'
                            '• 所有从教务系统和学习通获取的信息仅存储在用户本地设备。\n'
                            '• 学习通账号密码以加密方式存储在本地。\n'
                            '• 您可随时在本地删除应用数据或清除学习通配置，即可清除所有本地存储的信息。',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '三、数据的使用范围',
                        '我们获取并处理的所有信息仅用于以下目的：\n\n'
                            '• 查询并展示课程表\n'
                            '• 查询并展示成绩\n'
                            '• 查询并展示学习通未交作业\n'
                            '• 查询并展示学习通进行中活动（签到、测验等）\n'
                            '• 提供作业截止和活动结束提醒通知\n'
                            '• 提供与学业相关的功能服务\n\n'
                            '不会用于任何广告、分析、统计、用户画像、销售或其它与提供服务无关的用途。',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '四、我们不会进行的行为',
                        '本应用郑重承诺：\n\n'
                            '• 不会将任何信息上传至服务器\n'
                            '• 不会与任何第三方共享您的数据\n'
                            '• 不会用于广告或营销\n'
                            '• 不会存储、分析或传播用户的隐私信息\n'
                            '• 不会收集与服务无关的个人信息',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '五、数据安全',
                        '由于本应用不进行服务器存储，确保您的数据安全主要依赖您本地设备的安全性。\n\n'
                            '应用仅在必要时与学校教务系统和学习通平台通信，不会与其他服务器通信。\n\n'
                            '与学习通平台的通信采用 HTTPS 加密传输，登录凭证安全可靠。',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '六、您的权利',
                        '您拥有以下权利：\n\n'
                            '• 随时删除本地存储的全部数据\n'
                            '• 停止使用本应用，即可终止所有数据处理\n'
                            '• 随时查看、更新或清除在本地保存的个人信息',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '七、政策更新',
                        '根据功能调整或法律法规变化，本政策可能适时更新。更新后的政策会在应用中同步展示。',
                      ),
                      _buildPrivacySection(
                        theme,
                        colorScheme,
                        '八、联系我们',
                        '如您对本隐私政策或个人信息保护有任何疑问，可通过应用内联系方式向我们反馈。',
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建隐私政策章节
  Widget _buildPrivacySection(
    ThemeData theme,
    ColorScheme colorScheme,
    String? title,
    String content,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
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
            // 警告图标
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.logout_rounded,
                size: 32,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            // 标题
            Text(
              '确认退出登录',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // 提示内容
            Text(
              '退出登录后，本地缓存的数据将被清除。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // 按钮区域
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.dataManager.clearCache();
                      widget.onLogout();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('退出登录'),
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

  void _showNotificationDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final notificationService = NotificationService();

    // 可选的提前时间选项
    final minutesOptions = [5, 10, 15, 20, 30];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
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
              // 课程通知开关
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
              const SizedBox(height: 12),
              // 作业通知开关
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  title: const Text('作业提醒'),
                  subtitle: const Text('作业截止前发送通知提醒'),
                  value: _workNotificationEnabled,
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

                    await AuthStorage.setWorkNotificationEnabled(value);
                    setModalState(() {
                      _workNotificationEnabled = value;
                    });
                    setState(() {});
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
