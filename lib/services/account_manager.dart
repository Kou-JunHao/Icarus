/// 账号管理服务
/// 处理多账号的存储、切换和管理
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

/// 账号管理服务
class AccountManager extends ChangeNotifier {
  static const String _keyAccounts = 'accounts_list';
  static const String _keyActiveAccountId = 'active_account_id';

  /// 单例模式
  static final AccountManager _instance = AccountManager._internal();
  factory AccountManager() => _instance;
  AccountManager._internal();

  /// 所有账号列表
  List<Account> _accounts = [];
  List<Account> get accounts => List.unmodifiable(_accounts);

  /// 当前活跃账号
  Account? _activeAccount;
  Account? get activeAccount => _activeAccount;

  /// 是否已初始化
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 初始化账号管理器
  Future<void> init() async {
    if (_initialized) return;

    await _loadAccounts();
    _initialized = true;
  }

  /// 从存储加载账号列表
  Future<void> _loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJson = prefs.getString(_keyAccounts);
      final activeId = prefs.getString(_keyActiveAccountId);

      debugPrint('AccountManager: 加载账号数据...');
      debugPrint('AccountManager: accountsJson = $accountsJson');
      debugPrint('AccountManager: activeId = $activeId');

      if (accountsJson != null && accountsJson.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(accountsJson);
        _accounts = jsonList
            .map((json) => Account.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('AccountManager: 解析了 ${_accounts.length} 个账号');
        for (final account in _accounts) {
          debugPrint(
            'AccountManager: 账号 ${account.username}, hasXuexitong=${account.hasXuexitong}, xuexitong=${account.xuexitong}',
          );
        }

        // 设置活跃账号
        if (activeId != null && _accounts.isNotEmpty) {
          final activeIndex = _accounts.indexWhere((a) => a.id == activeId);
          if (activeIndex >= 0) {
            _activeAccount = _accounts[activeIndex];
          } else {
            _activeAccount = _accounts.first;
          }
          // 更新活跃状态
          _accounts = _accounts.map((a) {
            return a.copyWith(isActive: a.id == _activeAccount!.id);
          }).toList();
        } else if (_accounts.isNotEmpty) {
          _activeAccount = _accounts.first;
          _accounts[0] = _accounts[0].copyWith(isActive: true);
        }

        debugPrint('AccountManager: 活跃账号 = $_activeAccount');
      }

      debugPrint('AccountManager: 加载完成，共 ${_accounts.length} 个账号');
    } catch (e) {
      debugPrint('AccountManager: 加载账号失败: $e');
    }
  }

  /// 保存账号列表到存储
  Future<void> _saveAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _accounts.map((a) => a.toJson()).toList();
      await prefs.setString(_keyAccounts, jsonEncode(jsonList));

      if (_activeAccount != null) {
        await prefs.setString(_keyActiveAccountId, _activeAccount!.id);
      } else {
        await prefs.remove(_keyActiveAccountId);
      }

      debugPrint('保存了 ${_accounts.length} 个账号');
    } catch (e) {
      debugPrint('保存账号失败: $e');
    }
  }

  /// 生成唯一 ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (1000 + (DateTime.now().microsecond % 9000)).toString();
  }

  /// 添加新账号
  Future<Account> addAccount({
    required String username,
    required String password,
    String? displayName,
    String? schoolName,
    XuexitongAccount? xuexitong,
    bool setAsActive = true,
  }) async {
    // 确保已初始化
    if (!_initialized) {
      await init();
    }

    // 检查是否已存在相同用户名的账号
    final existingIndex = _accounts.indexWhere((a) => a.username == username);

    if (existingIndex >= 0) {
      // 更新现有账号
      final existing = _accounts[existingIndex];
      final updated = existing.copyWith(
        password: password,
        displayName: displayName ?? existing.displayName,
        schoolName: schoolName ?? existing.schoolName,
        xuexitong: xuexitong,
        lastLoginAt: DateTime.now(),
        isActive: setAsActive,
      );
      _accounts[existingIndex] = updated;

      if (setAsActive) {
        await switchAccount(updated.id);
      } else {
        await _saveAccounts();
        notifyListeners();
      }

      return updated;
    }

    // 创建新账号
    final account = Account(
      id: _generateId(),
      username: username,
      password: password,
      displayName: displayName,
      schoolName: schoolName,
      xuexitong: xuexitong,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      isActive: setAsActive,
    );

    // 如果设为活跃账号，先将其他账号设为非活跃
    if (setAsActive) {
      _accounts = _accounts.map((a) => a.copyWith(isActive: false)).toList();
      _activeAccount = account;
    }

    _accounts.add(account);
    await _saveAccounts();
    notifyListeners();

    return account;
  }

  /// 更新账号信息
  Future<void> updateAccount(Account account) async {
    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index < 0) return;

    _accounts[index] = account;

    if (account.isActive) {
      _activeAccount = account;
    }

    await _saveAccounts();
    notifyListeners();
  }

  /// 删除账号
  Future<void> deleteAccount(String accountId) async {
    final account = _accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => throw Exception('账号不存在'),
    );

    _accounts.removeWhere((a) => a.id == accountId);

    // 如果删除的是活跃账号，切换到第一个账号
    if (account.isActive && _accounts.isNotEmpty) {
      _accounts[0] = _accounts[0].copyWith(isActive: true);
      _activeAccount = _accounts[0];
    } else if (_accounts.isEmpty) {
      _activeAccount = null;
    }

    await _saveAccounts();
    notifyListeners();
  }

  /// 切换账号
  Future<Account?> switchAccount(String accountId) async {
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return null;

    // 更新所有账号的活跃状态
    _accounts = _accounts.map((a) {
      return a.copyWith(
        isActive: a.id == accountId,
        lastLoginAt: a.id == accountId ? DateTime.now() : a.lastLoginAt,
      );
    }).toList();

    _activeAccount = _accounts[index];

    await _saveAccounts();
    notifyListeners();

    return _activeAccount;
  }

  /// 更新账号的学习通配置
  Future<void> updateXuexitong(
    String accountId,
    XuexitongAccount? xuexitong,
  ) async {
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return;

    _accounts[index] = _accounts[index].copyWith(
      xuexitong: xuexitong,
      clearXuexitong: xuexitong == null,
    );

    if (_activeAccount?.id == accountId) {
      _activeAccount = _accounts[index];
    }

    await _saveAccounts();
    notifyListeners();
  }

  /// 更新账号显示名称
  Future<void> updateDisplayName(String accountId, String? displayName) async {
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return;

    _accounts[index] = _accounts[index].copyWith(displayName: displayName);

    if (_activeAccount?.id == accountId) {
      _activeAccount = _accounts[index];
    }

    await _saveAccounts();
    notifyListeners();
  }

  /// 获取账号
  Account? getAccount(String accountId) {
    try {
      return _accounts.firstWhere((a) => a.id == accountId);
    } catch (_) {
      return null;
    }
  }

  /// 根据用户名获取账号
  Account? getAccountByUsername(String username) {
    try {
      return _accounts.firstWhere((a) => a.username == username);
    } catch (_) {
      return null;
    }
  }

  /// 是否有多个账号
  bool get hasMultipleAccounts => _accounts.length > 1;

  /// 账号数量
  int get accountCount => _accounts.length;

  /// 清除所有账号
  Future<void> clearAll() async {
    _accounts.clear();
    _activeAccount = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccounts);
    await prefs.remove(_keyActiveAccountId);

    notifyListeners();
  }
}
