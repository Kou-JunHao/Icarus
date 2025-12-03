/// 学习通活动模型
/// 用于存储进行中的活动（签到、随堂练习、分组任务等）
library;

/// 活动类型
enum XxtActivityType {
  /// 签到
  signIn,

  /// 随堂练习/测验
  quiz,

  /// 分组任务
  groupTask,

  /// 投票/问卷
  vote,

  /// 讨论
  discussion,

  /// 直播
  live,

  /// 其他
  other,
}

/// 活动类型扩展
extension XxtActivityTypeExtension on XxtActivityType {
  /// 获取显示名称
  String get displayName {
    switch (this) {
      case XxtActivityType.signIn:
        return '签到';
      case XxtActivityType.quiz:
        return '测验';
      case XxtActivityType.groupTask:
        return '分组任务';
      case XxtActivityType.vote:
        return '投票';
      case XxtActivityType.discussion:
        return '讨论';
      case XxtActivityType.live:
        return '直播';
      case XxtActivityType.other:
        return '其他';
    }
  }

  /// 获取图标名称
  String get iconName {
    switch (this) {
      case XxtActivityType.signIn:
        return 'location_on';
      case XxtActivityType.quiz:
        return 'quiz';
      case XxtActivityType.groupTask:
        return 'group';
      case XxtActivityType.vote:
        return 'how_to_vote';
      case XxtActivityType.discussion:
        return 'forum';
      case XxtActivityType.live:
        return 'videocam';
      case XxtActivityType.other:
        return 'assignment';
    }
  }
}

/// 活动状态
enum XxtActivityStatus {
  /// 未知状态
  unknown,

  /// 已完成（已签到/已提交）
  completed,

  /// 未完成（未签到/未提交）
  pending,
}

/// 活动状态扩展
extension XxtActivityStatusExtension on XxtActivityStatus {
  /// 获取显示名称
  String get displayName {
    switch (this) {
      case XxtActivityStatus.unknown:
        return '';
      case XxtActivityStatus.completed:
        return '已完成';
      case XxtActivityStatus.pending:
        return '未完成';
    }
  }

  /// 是否已完成
  bool get isCompleted => this == XxtActivityStatus.completed;

  /// 是否未完成
  bool get isPending => this == XxtActivityStatus.pending;
}

/// 学习通活动
class XxtActivity {
  /// 活动类型
  final XxtActivityType type;

  /// 活动名称
  final String name;

  /// 原始类型字符串
  final String rawType;

  /// 活动ID
  final String? activeId;

  /// 活动类型编号（2=签到, 35=分组任务, 42=随堂练习）
  final String? activeType;

  /// 结束时间（如果有）
  final DateTime? endTime;

  /// 活动状态
  final XxtActivityStatus status;

  const XxtActivity({
    required this.type,
    required this.name,
    required this.rawType,
    this.activeId,
    this.activeType,
    this.endTime,
    this.status = XxtActivityStatus.unknown,
  });

  /// 从解析的数据创建
  factory XxtActivity.fromParsed({
    required String typeName,
    required String name,
    String? activeId,
    String? activeType,
    DateTime? endTime,
    XxtActivityStatus status = XxtActivityStatus.unknown,
  }) {
    return XxtActivity(
      type: _parseActivityType(typeName),
      name: name.trim(),
      rawType: typeName.trim(),
      activeId: activeId,
      activeType: activeType,
      endTime: endTime,
      status: status,
    );
  }

  /// 创建带有更新状态的副本
  XxtActivity copyWith({
    XxtActivityType? type,
    String? name,
    String? rawType,
    String? activeId,
    String? activeType,
    DateTime? endTime,
    XxtActivityStatus? status,
  }) {
    return XxtActivity(
      type: type ?? this.type,
      name: name ?? this.name,
      rawType: rawType ?? this.rawType,
      activeId: activeId ?? this.activeId,
      activeType: activeType ?? this.activeType,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
    );
  }

  /// 解析活动类型
  static XxtActivityType _parseActivityType(String typeName) {
    final lower = typeName.toLowerCase();

    if (lower.contains('签到') || lower.contains('sign')) {
      return XxtActivityType.signIn;
    }
    if (lower.contains('测验') ||
        lower.contains('练习') ||
        lower.contains('quiz') ||
        lower.contains('考试')) {
      return XxtActivityType.quiz;
    }
    if (lower.contains('分组') ||
        lower.contains('小组') ||
        lower.contains('group')) {
      return XxtActivityType.groupTask;
    }
    if (lower.contains('投票') ||
        lower.contains('问卷') ||
        lower.contains('vote') ||
        lower.contains('调查')) {
      return XxtActivityType.vote;
    }
    if (lower.contains('讨论') || lower.contains('discuss')) {
      return XxtActivityType.discussion;
    }
    if (lower.contains('直播') || lower.contains('live')) {
      return XxtActivityType.live;
    }

    return XxtActivityType.other;
  }

  /// 是否已过期
  bool get isExpired => endTime != null && DateTime.now().isAfter(endTime!);

  /// 是否即将过期（30分钟内）
  bool get isUrgent {
    if (endTime == null) return false;
    final diff = endTime!.difference(DateTime.now());
    return diff.inMinutes <= 30 && diff.inMinutes > 0;
  }

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

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'name': name,
      'rawType': rawType,
      'activeId': activeId,
      'activeType': activeType,
      'endTime': endTime?.toIso8601String(),
      'status': status.index,
    };
  }

  /// 从 JSON 创建
  factory XxtActivity.fromJson(Map<String, dynamic> json) {
    return XxtActivity(
      type: XxtActivityType.values[json['type'] as int],
      name: json['name'] as String,
      rawType: json['rawType'] as String,
      activeId: json['activeId'] as String?,
      activeType: json['activeType'] as String?,
      endTime: json['endTime'] != null
          ? DateTime.tryParse(json['endTime'] as String)
          : null,
      status: json['status'] != null
          ? XxtActivityStatus.values[json['status'] as int]
          : XxtActivityStatus.unknown,
    );
  }

  @override
  String toString() {
    return 'XxtActivity(type: $type, name: $name, activeId: $activeId, status: $status, endTime: $endTime)';
  }
}

/// 课程活动信息
class XxtCourseActivities {
  /// 课程名称
  final String courseName;

  /// 课程ID
  final String courseId;

  /// 班级ID
  final String classId;

  /// 进行中的活动列表
  final List<XxtActivity> activities;

  const XxtCourseActivities({
    required this.courseName,
    required this.courseId,
    required this.classId,
    required this.activities,
  });

  /// 活动数量
  int get activityCount => activities.length;

  /// 是否有活动
  bool get hasActivities => activities.isNotEmpty;

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'courseName': courseName,
      'courseId': courseId,
      'classId': classId,
      'activities': activities.map((a) => a.toJson()).toList(),
    };
  }

  /// 从 JSON 创建
  factory XxtCourseActivities.fromJson(Map<String, dynamic> json) {
    return XxtCourseActivities(
      courseName: json['courseName'] as String,
      courseId: json['courseId'] as String,
      classId: json['classId'] as String,
      activities: (json['activities'] as List)
          .map((a) => XxtActivity.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() {
    return 'XxtCourseActivities(course: $courseName, activities: ${activities.length})';
  }
}

/// 活动查询结果
class XxtActivityResult {
  /// 是否成功
  final bool success;

  /// 错误信息
  final String? error;

  /// 有活动的课程列表
  final List<XxtCourseActivities> courseActivities;

  /// 是否需要登录
  final bool needLogin;

  const XxtActivityResult({
    required this.success,
    this.error,
    this.courseActivities = const [],
    this.needLogin = false,
  });

  /// 成功结果
  factory XxtActivityResult.success(List<XxtCourseActivities> activities) {
    return XxtActivityResult(success: true, courseActivities: activities);
  }

  /// 失败结果
  factory XxtActivityResult.failure(String error, {bool needLogin = false}) {
    return XxtActivityResult(
      success: false,
      error: error,
      needLogin: needLogin,
    );
  }

  /// 获取所有活动的总数
  int get totalActivityCount {
    return courseActivities.fold(0, (sum, c) => sum + c.activityCount);
  }

  /// 是否有进行中的活动
  bool get hasActivities => totalActivityCount > 0;

  /// 获取所有签到活动
  List<XxtActivity> get signInActivities {
    return courseActivities
        .expand((c) => c.activities)
        .where((a) => a.type == XxtActivityType.signIn)
        .toList();
  }

  /// 是否有签到活动
  bool get hasSignIn => signInActivities.isNotEmpty;

  /// 按活动类型分组
  Map<XxtActivityType, List<XxtActivity>> get activitiesByType {
    final map = <XxtActivityType, List<XxtActivity>>{};
    for (final course in courseActivities) {
      for (final activity in course.activities) {
        map.putIfAbsent(activity.type, () => []).add(activity);
      }
    }
    return map;
  }
}
