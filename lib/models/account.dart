/// 账号模型
/// 支持多账号管理和学习通账号配置
library;

/// 账号类型
enum AccountType {
  /// 教务系统账号
  jwxt,
}

/// 学习通账号配置（可选）
class XuexitongAccount {
  /// 学习通账号（手机号/学号）
  final String username;

  /// 学习通密码
  final String password;

  const XuexitongAccount({required this.username, required this.password});

  factory XuexitongAccount.fromJson(Map<String, dynamic> json) {
    return XuexitongAccount(
      username: json['username'] as String,
      password: json['password'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'username': username, 'password': password};
  }

  XuexitongAccount copyWith({String? username, String? password}) {
    return XuexitongAccount(
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

/// 用户账号
class Account {
  /// 唯一标识符
  final String id;

  /// 账号类型
  final AccountType type;

  /// 学号/用户名
  final String username;

  /// 密码
  final String password;

  /// 显示名称（用户姓名或自定义名称）
  final String? displayName;

  /// 学校名称
  final String? schoolName;

  /// 学习通账号（可选）
  final XuexitongAccount? xuexitong;

  /// 创建时间
  final DateTime createdAt;

  /// 最后登录时间
  final DateTime? lastLoginAt;

  /// 是否为当前活跃账号
  final bool isActive;

  const Account({
    required this.id,
    this.type = AccountType.jwxt,
    required this.username,
    required this.password,
    this.displayName,
    this.schoolName,
    this.xuexitong,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = false,
  });

  /// 从 JSON 创建
  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      type: AccountType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AccountType.jwxt,
      ),
      username: json['username'] as String,
      password: json['password'] as String,
      displayName: json['displayName'] as String?,
      schoolName: json['schoolName'] as String?,
      xuexitong: json['xuexitong'] != null
          ? XuexitongAccount.fromJson(json['xuexitong'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.parse(json['lastLoginAt'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'username': username,
      'password': password,
      'displayName': displayName,
      'schoolName': schoolName,
      'xuexitong': xuexitong?.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'isActive': isActive,
    };
  }

  /// 复制并修改
  Account copyWith({
    String? id,
    AccountType? type,
    String? username,
    String? password,
    String? displayName,
    String? schoolName,
    XuexitongAccount? xuexitong,
    bool clearXuexitong = false,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
  }) {
    return Account(
      id: id ?? this.id,
      type: type ?? this.type,
      username: username ?? this.username,
      password: password ?? this.password,
      displayName: displayName ?? this.displayName,
      schoolName: schoolName ?? this.schoolName,
      xuexitong: clearXuexitong ? null : (xuexitong ?? this.xuexitong),
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// 获取显示名称
  String get name => displayName ?? username;

  /// 是否配置了学习通
  bool get hasXuexitong => xuexitong != null;

  @override
  String toString() {
    return 'Account(id: $id, username: $username, displayName: $displayName, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Account && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
