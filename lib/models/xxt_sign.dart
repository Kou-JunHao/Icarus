/// 学习通签到模型
/// 独立实现，基于公开 API 文档
library;

/// 签到类型（根据 otherId 区分）
enum XxtSignType {
  /// 普通签到 (otherId = 0, ifphoto = 0)
  normal(0),

  /// 拍照签到 (otherId = 0, ifphoto = 1)
  photo(0),

  /// 二维码签到 (otherId = 2)
  qrcode(2),

  /// 手势签到 (otherId = 3)
  gesture(3),

  /// 位置签到 (otherId = 4)
  location(4),

  /// 密码签到 (otherId = 5)
  password(5);

  final int otherId;
  const XxtSignType(this.otherId);

  /// 获取显示名称
  String get displayName {
    switch (this) {
      case XxtSignType.normal:
        return '普通签到';
      case XxtSignType.photo:
        return '拍照签到';
      case XxtSignType.qrcode:
        return '二维码签到';
      case XxtSignType.gesture:
        return '手势签到';
      case XxtSignType.location:
        return '位置签到';
      case XxtSignType.password:
        return '密码签到';
    }
  }

  /// 从 otherId 获取签到类型
  static XxtSignType fromOtherId(int otherId, {bool requirePhoto = false}) {
    switch (otherId) {
      case 0:
        return requirePhoto ? XxtSignType.photo : XxtSignType.normal;
      case 2:
        return XxtSignType.qrcode;
      case 3:
        return XxtSignType.gesture;
      case 4:
        return XxtSignType.location;
      case 5:
        return XxtSignType.password;
      default:
        return XxtSignType.normal;
    }
  }
}

/// 签退信息
/// 签到活动可能有关联的签退活动
class XxtSignOutInfo {
  /// 主签到活动 ID（如果当前是签退活动，指向主签到）
  final String? signInId;

  /// 签退活动 ID（如果当前是签到活动，指向签退）
  final String? signOutId;

  /// 签退活动发布时间
  final DateTime? signOutPublishTime;

  /// 课程 ID
  final String courseId;

  /// 班级 ID
  final String classId;

  const XxtSignOutInfo({
    this.signInId,
    this.signOutId,
    this.signOutPublishTime,
    required this.courseId,
    required this.classId,
  });

  /// 签退重定向状态
  XxtSignRedirectStatus get redirectStatus {
    if (signInId != null) {
      // 当前是签退活动
      return XxtSignRedirectStatus.signOut;
    } else if (signOutPublishTime != null) {
      if (signOutId == null) {
        // 签退未发布
        return XxtSignRedirectStatus.signInUnpublished;
      } else {
        // 签退已发布
        return XxtSignRedirectStatus.signInPublished;
      }
    }
    return XxtSignRedirectStatus.common;
  }

  /// 是否需要显示签退提示
  bool get shouldShowTips => redirectStatus != XxtSignRedirectStatus.common;

  @override
  String toString() {
    return 'XxtSignOutInfo(signInId: $signInId, signOutId: $signOutId, publishTime: $signOutPublishTime)';
  }
}

/// 签退重定向状态
enum XxtSignRedirectStatus {
  /// 普通签到（没有签退）
  common,

  /// 当前是签退活动，需要跳转到主签到
  signOut,

  /// 当前是签到活动，签退已发布
  signInPublished,

  /// 当前是签到活动，签退未发布
  signInUnpublished,
}

/// 签到活动详情
class XxtSignActivity {
  /// 活动 ID
  final String activeId;

  /// 签到类型
  final XxtSignType signType;

  /// 活动名称
  final String name;

  /// 课程名称
  final String courseName;

  /// 课程 ID
  final String courseId;

  /// 班级 ID
  final String classId;

  /// 开始时间
  final DateTime? startTime;

  /// 结束时间
  final DateTime? endTime;

  /// 是否需要拍照 (otherId=0 时使用)
  final bool requirePhoto;

  /// 二维码是否刷新
  final bool qrcodeRefresh;

  /// 二维码签到是否需要位置
  final bool qrcodeRequireLocation;

  /// 位置签到纬度
  final double? locationLatitude;

  /// 位置签到经度
  final double? locationLongitude;

  /// 位置签到范围（米）
  final int? locationRange;

  /// 密码位数
  final int? passwordLength;

  /// 签退信息
  final XxtSignOutInfo? signOutInfo;

  const XxtSignActivity({
    required this.activeId,
    required this.signType,
    required this.name,
    required this.courseName,
    required this.courseId,
    required this.classId,
    this.startTime,
    this.endTime,
    this.requirePhoto = false,
    this.qrcodeRefresh = false,
    this.qrcodeRequireLocation = false,
    this.locationLatitude,
    this.locationLongitude,
    this.locationRange,
    this.passwordLength,
    this.signOutInfo,
  });

  /// 是否已过期
  bool get isExpired => endTime != null && DateTime.now().isAfter(endTime!);

  /// 获取剩余时间描述
  String get remainingTimeText {
    if (endTime == null) return '进行中';

    final now = DateTime.now();
    final diff = endTime!.difference(now);

    if (diff.isNegative) return '已结束';

    if (diff.inDays > 0) {
      return '剩余 ${diff.inDays} 天';
    } else if (diff.inHours > 0) {
      return '剩余 ${diff.inHours} 小时 ${diff.inMinutes % 60} 分';
    } else if (diff.inMinutes > 0) {
      return '剩余 ${diff.inMinutes} 分钟';
    } else {
      return '即将结束';
    }
  }

  @override
  String toString() {
    return 'XxtSignActivity(activeId: $activeId, type: $signType, name: $name)';
  }
}

/// 签到结果
class XxtSignResult {
  /// 是否成功
  final bool success;

  /// 结果类型
  final XxtSignResultType type;

  /// 消息
  final String message;

  /// 是否需要验证码
  final bool needCaptcha;

  const XxtSignResult({
    required this.success,
    required this.type,
    required this.message,
    this.needCaptcha = false,
  });

  /// 成功
  factory XxtSignResult.success() {
    return const XxtSignResult(
      success: true,
      type: XxtSignResultType.success,
      message: '签到成功',
    );
  }

  /// 迟到
  factory XxtSignResult.late() {
    return const XxtSignResult(
      success: true,
      type: XxtSignResultType.late,
      message: '签到成功（迟到）',
    );
  }

  /// 已签到
  factory XxtSignResult.alreadySigned() {
    return const XxtSignResult(
      success: true,
      type: XxtSignResultType.alreadySigned,
      message: '您已签到过了',
    );
  }

  /// 需要验证码
  factory XxtSignResult.needValidate() {
    return const XxtSignResult(
      success: false,
      type: XxtSignResultType.needCaptcha,
      message: '需要验证码',
      needCaptcha: true,
    );
  }

  /// 失败
  factory XxtSignResult.failed(String error) {
    return XxtSignResult(
      success: false,
      type: XxtSignResultType.failed,
      message: error,
    );
  }

  /// 用户不在班级
  factory XxtSignResult.notInClass() {
    return const XxtSignResult(
      success: false,
      type: XxtSignResultType.notInClass,
      message: '用户不在班级',
    );
  }
}

/// 签到结果类型
enum XxtSignResultType {
  /// 成功
  success,

  /// 迟到
  late,

  /// 已签到
  alreadySigned,

  /// 需要验证码
  needCaptcha,

  /// 失败
  failed,

  /// 用户不在班级
  notInClass,
}

/// 位置信息
class XxtLocation {
  /// 纬度
  final double latitude;

  /// 经度
  final double longitude;

  /// 地址
  final String address;

  const XxtLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  /// 转换为 JSON 字符串（用于二维码签到的 location 参数）
  String toJsonString() {
    return '{"result":1,"latitude":"$latitude","longitude":"$longitude","address":"$address"}';
  }

  @override
  String toString() {
    return 'XxtLocation(lat: $latitude, lng: $longitude, addr: $address)';
  }
}

/// 滑动验证码数据
/// 基于公开 API 端点实现
class XxtCaptchaData {
  /// 验证码 ID
  final String captchaId;

  /// 类型 (slide)
  final String type;

  /// 版本
  final String version;

  /// Token
  final String token;

  /// 验证码 Key
  final String captchaKey;

  /// IV
  final String iv;

  /// 背景图 URL
  final String shadeImageUrl;

  /// 滑块图 URL
  final String cutoutImageUrl;

  const XxtCaptchaData({
    required this.captchaId,
    required this.type,
    required this.version,
    required this.token,
    required this.captchaKey,
    required this.iv,
    required this.shadeImageUrl,
    required this.cutoutImageUrl,
  });
}

/// 签到账号（用于分享签到）
class XxtSignAccount {
  /// 唯一标识符
  final String id;

  /// 学习通账号（手机号/学号）
  final String username;

  /// 学习通密码
  final String password;

  /// 备注名称（用户昵称）
  final String? nickname;

  /// 是否启用分享签到
  final bool enableShare;

  /// 创建时间
  final DateTime createdAt;

  const XxtSignAccount({
    required this.id,
    required this.username,
    required this.password,
    this.nickname,
    this.enableShare = true,
    required this.createdAt,
  });

  /// 从 JSON 创建
  factory XxtSignAccount.fromJson(Map<String, dynamic> json) {
    return XxtSignAccount(
      id: json['id'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      nickname: json['nickname'] as String?,
      enableShare: json['enableShare'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'nickname': nickname,
      'enableShare': enableShare,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改
  XxtSignAccount copyWith({
    String? id,
    String? username,
    String? password,
    String? nickname,
    bool? enableShare,
    DateTime? createdAt,
  }) {
    return XxtSignAccount(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      nickname: nickname ?? this.nickname,
      enableShare: enableShare ?? this.enableShare,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 获取显示名称
  String get displayName => nickname ?? username;

  @override
  String toString() {
    return 'XxtSignAccount(id: $id, username: $username, nickname: $nickname)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is XxtSignAccount && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 单个账号的签到结果
class XxtSignAccountResult {
  /// 账号
  final XxtSignAccount account;

  /// 签到结果
  final XxtSignResult result;

  const XxtSignAccountResult({required this.account, required this.result});
}

/// 分享签到结果（多账号）
class XxtShareSignResult {
  /// 各账号签到结果
  final List<XxtSignAccountResult> results;

  /// 总成功数
  int get successCount => results.where((r) => r.result.success).length;

  /// 总失败数
  int get failedCount => results.length - successCount;

  /// 是否全部成功
  bool get allSuccess => failedCount == 0;

  const XxtShareSignResult({required this.results});
}
