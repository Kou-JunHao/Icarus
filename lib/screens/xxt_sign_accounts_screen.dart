/// 学习通签到账号管理页面
/// 管理用于分享签到的账号列表
library;

import 'package:flutter/material.dart';

import '../models/xxt_sign.dart';
import '../services/xxt_sign_account_manager.dart';
import '../services/xxt_sign_service.dart';

/// 签到账号管理页面
class XxtSignAccountsScreen extends StatefulWidget {
  const XxtSignAccountsScreen({super.key});

  @override
  State<XxtSignAccountsScreen> createState() => _XxtSignAccountsScreenState();
}

class _XxtSignAccountsScreenState extends State<XxtSignAccountsScreen> {
  final XxtSignAccountManager _accountManager = XxtSignAccountManager();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _accountManager.init();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    _accountManager.addListener(_onAccountsChanged);
  }

  @override
  void dispose() {
    _accountManager.removeListener(_onAccountsChanged);
    super.dispose();
  }

  void _onAccountsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addAccount() async {
    final result = await showDialog<XxtSignAccount>(
      context: context,
      builder: (context) => const _AddAccountDialog(),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加账号: ${result.displayName}')));
    }
  }

  Future<void> _editAccount(XxtSignAccount account) async {
    final result = await showDialog<XxtSignAccount>(
      context: context,
      builder: (context) => _AddAccountDialog(account: account),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已更新账号: ${result.displayName}')));
    }
  }

  Future<void> _deleteAccount(XxtSignAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定要删除账号 "${account.displayName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _accountManager.removeAccount(account.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除账号: ${account.displayName}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('签到账号管理'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _accountManager.accounts.isEmpty
          ? _buildEmptyView(theme, colorScheme)
          : _buildAccountList(theme, colorScheme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加账号'),
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
              Icons.people_outline_rounded,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无签到账号',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '添加学习通账号后，可以在签到时同时为多个账号签到',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountList(ThemeData theme, ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _accountManager.accounts.length,
      itemBuilder: (context, index) {
        final account = _accountManager.accounts[index];
        return _AccountCard(
          account: account,
          onToggleShare: () => _accountManager.toggleShareEnabled(account.id),
          onEdit: () => _editAccount(account),
          onDelete: () => _deleteAccount(account),
        );
      },
    );
  }
}

/// 账号卡片
class _AccountCard extends StatelessWidget {
  final XxtSignAccount account;
  final VoidCallback onToggleShare;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AccountCard({
    required this.account,
    required this.onToggleShare,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 头像
              CircleAvatar(
                backgroundColor: account.enableShare
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                child: Text(
                  account.displayName.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: account.enableShare
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.username,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // 分享签到开关
              Column(
                children: [
                  Switch(
                    value: account.enableShare,
                    onChanged: (_) => onToggleShare(),
                  ),
                  Text(
                    '分享签到',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // 删除按钮
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 添加/编辑账号对话框
class _AddAccountDialog extends StatefulWidget {
  final XxtSignAccount? account;

  const _AddAccountDialog({this.account});

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final XxtSignAccountManager _accountManager = XxtSignAccountManager();
  final XxtSignService _signService = XxtSignService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      _usernameController.text = widget.account!.username;
      _passwordController.text = widget.account!.password;
      _nicknameController.text = widget.account!.nickname ?? '';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 验证账号是否有效
      final isValid = await _signService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!isValid) {
        setState(() {
          _isLoading = false;
          _error = '账号或密码错误';
        });
        return;
      }

      // 保存账号
      final account = await _accountManager.addAccount(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        nickname: _nicknameController.text.trim().isNotEmpty
            ? _nicknameController.text.trim()
            : null,
        enableShare: widget.account?.enableShare ?? true,
      );

      if (mounted) {
        Navigator.pop(context, account);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '保存失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(_isEditing ? '编辑账号' : '添加签到账号'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: colorScheme.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '学习通账号',
                  hintText: '手机号/学号',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                keyboardType: TextInputType.text,
                enabled: !_isEditing,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入账号';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: '备注名称（可选）',
                  hintText: '用于区分不同账号',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }
}
