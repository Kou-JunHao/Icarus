/// 账号管理页面
/// 支持多账号管理、切换和学习通配置
library;

import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/account_manager.dart';
import 'xxt_sign_accounts_screen.dart';

/// 账号管理页面
class AccountManageScreen extends StatefulWidget {
  final VoidCallback? onAccountSwitch;

  const AccountManageScreen({super.key, this.onAccountSwitch});

  @override
  State<AccountManageScreen> createState() => _AccountManageScreenState();
}

class _AccountManageScreenState extends State<AccountManageScreen> {
  final AccountManager _accountManager = AccountManager();

  @override
  void initState() {
    super.initState();
    _accountManager.addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    _accountManager.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账号管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加账号',
            onPressed: () => _showAddAccountDialog(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 当前账号
          if (_accountManager.activeAccount != null) ...[
            _buildSectionTitle(theme, '当前账号'),
            const SizedBox(height: 8),
            _buildAccountCard(
              theme,
              colorScheme,
              _accountManager.activeAccount!,
              isActive: true,
            ),
            const SizedBox(height: 24),
          ],

          // 其他账号
          if (_accountManager.accounts
              .where((a) => !a.isActive)
              .isNotEmpty) ...[
            _buildSectionTitle(theme, '其他账号'),
            const SizedBox(height: 8),
            ..._accountManager.accounts
                .where((a) => !a.isActive)
                .map(
                  (account) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildAccountCard(
                      theme,
                      colorScheme,
                      account,
                      isActive: false,
                    ),
                  ),
                ),
            const SizedBox(height: 16),
          ],

          // 空状态
          if (_accountManager.accounts.isEmpty) ...[
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 64,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无账号',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右上角添加账号',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 提示信息
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '支持添加多个教务系统账号，可选配置学习通账号。切换账号后需要重新加载。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 签到账号管理入口
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                Icons.people_outline_rounded,
                color: colorScheme.tertiary,
              ),
              title: const Text('签到账号管理'),
              subtitle: Text(
                '管理用于分享签到的学习通账号',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const XxtSignAccountsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAccountCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Account account, {
    required bool isActive,
  }) {
    return Card(
      elevation: 0,
      color: isActive
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: isActive ? null : () => _switchAccount(account),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isActive
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    child: Text(
                      account.name.isNotEmpty
                          ? account.name.substring(0, 1)
                          : '?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isActive
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 账号信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                account.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '当前',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '学号: ${account.username}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 更多操作
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) => _handleMenuAction(value, account),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'xuexitong',
                        child: Row(
                          children: [
                            Icon(
                              account.hasXuexitong
                                  ? Icons.edit_outlined
                                  : Icons.add_circle_outline,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(account.hasXuexitong ? '编辑学习通' : '配置学习通'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: const Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('编辑账号'),
                          ],
                        ),
                      ),
                      if (!isActive)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '删除账号',
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              // 学习通状态
              if (account.hasXuexitong) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 16,
                        color: colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '学习通: ${account.xuexitong!.username}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(String action, Account account) {
    switch (action) {
      case 'xuexitong':
        _showXuexitongDialog(account);
        break;
      case 'edit':
        _showEditAccountDialog(account);
        break;
      case 'delete':
        _showDeleteConfirmDialog(account);
        break;
    }
  }

  Future<void> _switchAccount(Account account) async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换账号'),
        content: Text('确定切换到账号 "${account.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('切换'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _accountManager.switchAccount(account.id);

    if (mounted) {
      // 通知外部进行账号切换（自动登录）
      widget.onAccountSwitch?.call();
    }
  }

  void _showAddAccountDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccountFormSheet(
        title: '添加账号',
        onSave: (username, password, displayName, xuexitong) async {
          await _accountManager.addAccount(
            username: username,
            password: password,
            displayName: displayName,
            xuexitong: xuexitong,
            setAsActive: false,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('账号添加成功'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditAccountDialog(Account account) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccountFormSheet(
        title: '编辑账号',
        account: account,
        onSave: (username, password, displayName, xuexitong) async {
          final updated = account.copyWith(
            username: username,
            password: password,
            displayName: displayName,
            xuexitong: xuexitong,
          );
          await _accountManager.updateAccount(updated);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('账号更新成功'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  void _showXuexitongDialog(Account account) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _XuexitongFormSheet(
        xuexitong: account.xuexitong,
        onSave: (xuexitong) async {
          await _accountManager.updateXuexitong(account.id, xuexitong);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(xuexitong != null ? '学习通配置已保存' : '学习通配置已清除'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(Account account) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 32),
        title: const Text('删除账号'),
        content: Text('确定删除账号 "${account.name}" 吗？\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _accountManager.deleteAccount(account.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('账号已删除'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 账号表单弹窗
class _AccountFormSheet extends StatefulWidget {
  final String title;
  final Account? account;
  final Future<void> Function(
    String username,
    String password,
    String? displayName,
    XuexitongAccount? xuexitong,
  )
  onSave;

  const _AccountFormSheet({
    required this.title,
    this.account,
    required this.onSave,
  });

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _xxtUsernameController;
  late final TextEditingController _xxtPasswordController;

  bool _obscurePassword = true;
  bool _obscureXxtPassword = true;
  bool _showXuexitong = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.account?.username);
    _passwordController = TextEditingController(text: widget.account?.password);
    _displayNameController = TextEditingController(
      text: widget.account?.displayName,
    );
    _xxtUsernameController = TextEditingController(
      text: widget.account?.xuexitong?.username,
    );
    _xxtPasswordController = TextEditingController(
      text: widget.account?.xuexitong?.password,
    );
    _showXuexitong = widget.account?.hasXuexitong ?? false;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _xxtUsernameController.dispose();
    _xxtPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽指示器
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
              // 标题
              Text(
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 教务系统账号
              Text(
                '教务系统账号',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),

              // 学号
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '学号',
                  hintText: '请输入学号',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入学号';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // 密码
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入教务系统密码',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // 显示名称（可选）
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: '显示名称（可选）',
                  hintText: '留空则使用学号',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 24),

              // 学习通配置（可选）
              Row(
                children: [
                  Text(
                    '学习通账号（可选）',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.tertiary,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _showXuexitong,
                    onChanged: (value) =>
                        setState(() => _showXuexitong = value),
                  ),
                ],
              ),

              if (_showXuexitong) ...[
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // 学习通账号
                        TextFormField(
                          controller: _xxtUsernameController,
                          decoration: const InputDecoration(
                            labelText: '学习通账号',
                            hintText: '手机号/学号',
                            prefixIcon: Icon(Icons.school_outlined, size: 20),
                          ),
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        // 学习通密码
                        TextFormField(
                          controller: _xxtPasswordController,
                          decoration: InputDecoration(
                            labelText: '学习通密码',
                            hintText: '请输入学习通密码',
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureXxtPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () =>
                                    _obscureXxtPassword = !_obscureXxtPassword,
                              ),
                            ),
                          ),
                          obscureText: _obscureXxtPassword,
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '学习通账号为可选配置，不填写不影响软件使用',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // 保存按钮
              FilledButton(
                onPressed: _isSaving ? null : _handleSave,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      XuexitongAccount? xuexitong;
      if (_showXuexitong &&
          _xxtUsernameController.text.isNotEmpty &&
          _xxtPasswordController.text.isNotEmpty) {
        xuexitong = XuexitongAccount(
          username: _xxtUsernameController.text.trim(),
          password: _xxtPasswordController.text,
        );
      }

      await widget.onSave(
        _usernameController.text.trim(),
        _passwordController.text,
        _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        xuexitong,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

/// 学习通配置弹窗
class _XuexitongFormSheet extends StatefulWidget {
  final XuexitongAccount? xuexitong;
  final Future<void> Function(XuexitongAccount? xuexitong) onSave;

  const _XuexitongFormSheet({this.xuexitong, required this.onSave});

  @override
  State<_XuexitongFormSheet> createState() => _XuexitongFormSheetState();
}

class _XuexitongFormSheetState extends State<_XuexitongFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _obscurePassword = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.xuexitong?.username,
    );
    _passwordController = TextEditingController(
      text: widget.xuexitong?.password,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽指示器
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
              // 图标和标题
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_rounded,
                    color: colorScheme.tertiary,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '学习通配置',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '配置学习通账号后可使用相关功能',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 学习通账号
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '学习通账号',
                  hintText: '手机号/学号',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // 学习通密码
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '学习通密码',
                  hintText: '请输入学习通密码',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),

              // 提示
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '学习通账号为可选配置，不填写不影响软件正常使用',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 按钮区域
              Row(
                children: [
                  // 清除按钮
                  if (widget.xuexitong != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _handleClear,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error),
                        ),
                        child: const Text('清除配置'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // 保存按钮
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);

    try {
      XuexitongAccount? xuexitong;
      if (_usernameController.text.isNotEmpty &&
          _passwordController.text.isNotEmpty) {
        xuexitong = XuexitongAccount(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      }

      await widget.onSave(xuexitong);

      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleClear() async {
    setState(() => _isSaving = true);

    try {
      await widget.onSave(null);

      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
