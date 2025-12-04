/// 学习通签到账号管理服务
/// 管理用于分享签到的账号列表
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/xxt_sign.dart';

/// 签到账号管理服务
class XxtSignAccountManager extends ChangeNotifier {
  static const String _keyAccounts = 'xxt_sign_accounts';

  /// 单例模式
  static final XxtSignAccountManager _instance =
      XxtSignAccountManager._internal();
  factory XxtSignAccountManager() => _instance;
  XxtSignAccountManager._internal();

  /// 签到账号列表
  List<XxtSignAccount> _accounts = [];
  List<XxtSignAccount> get accounts => List.unmodifiable(_accounts);

  /// 启用分享签到的账号列表
  List<XxtSignAccount> get enabledAccounts =>
      _accounts.where((a) => a.enableShare).toList();

  /// 是否已初始化
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 初始化
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

      if (accountsJson != null && accountsJson.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(accountsJson);
        _accounts = jsonList
            .map(
              (json) => XxtSignAccount.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        debugPrint('XxtSignAccountManager: 加载了 ${_accounts.length} 个签到账号');
      }
    } catch (e) {
      debugPrint('XxtSignAccountManager: 加载账号失败: $e');
    }
  }

  /// 保存账号列表到存储
  Future<void> _saveAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _accounts.map((a) => a.toJson()).toList();
      await prefs.setString(_keyAccounts, jsonEncode(jsonList));

      debugPrint('XxtSignAccountManager: 保存了 ${_accounts.length} 个签到账号');
    } catch (e) {
      debugPrint('XxtSignAccountManager: 保存账号失败: $e');
    }
  }

  /// 生成唯一 ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (1000 + (DateTime.now().microsecond % 9000)).toString();
  }

  /// 添加签到账号
  Future<XxtSignAccount> addAccount({
    required String username,
    required String password,
    String? nickname,
    bool enableShare = true,
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
        nickname: nickname ?? existing.nickname,
        enableShare: enableShare,
      );
      _accounts[existingIndex] = updated;
      await _saveAccounts();
      notifyListeners();
      return updated;
    }

    // 创建新账号
    final account = XxtSignAccount(
      id: _generateId(),
      username: username,
      password: password,
      nickname: nickname,
      enableShare: enableShare,
      createdAt: DateTime.now(),
    );

    _accounts.add(account);
    await _saveAccounts();
    notifyListeners();

    return account;
  }

  /// 更新签到账号
  Future<bool> updateAccount(XxtSignAccount account) async {
    if (!_initialized) {
      await init();
    }

    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index < 0) return false;

    _accounts[index] = account;
    await _saveAccounts();
    notifyListeners();

    return true;
  }

  /// 删除签到账号
  Future<bool> removeAccount(String accountId) async {
    if (!_initialized) {
      await init();
    }

    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return false;

    _accounts.removeAt(index);
    await _saveAccounts();
    notifyListeners();

    return true;
  }

  /// 切换账号的分享签到状态
  Future<void> toggleShareEnabled(String accountId) async {
    if (!_initialized) {
      await init();
    }

    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index < 0) return;

    final account = _accounts[index];
    _accounts[index] = account.copyWith(enableShare: !account.enableShare);
    await _saveAccounts();
    notifyListeners();
  }

  /// 获取账号
  XxtSignAccount? getAccount(String accountId) {
    try {
      return _accounts.firstWhere((a) => a.id == accountId);
    } catch (_) {
      return null;
    }
  }

  /// 根据用户名获取账号
  XxtSignAccount? getAccountByUsername(String username) {
    try {
      return _accounts.firstWhere((a) => a.username == username);
    } catch (_) {
      return null;
    }
  }

  /// 清除所有账号
  Future<void> clearAllAccounts() async {
    _accounts.clear();
    await _saveAccounts();
    notifyListeners();
  }
}
