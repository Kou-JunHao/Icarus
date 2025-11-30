/// 学习通未交作业模型
library;

/// 未交作业
class XxtWork {
  /// 作业名称
  final String name;

  /// 作业状态
  final String status;

  /// 剩余时间
  final String remainingTime;

  /// 所属课程
  final String? courseName;

  /// 是否即将截止（24小时内）
  final bool isUrgent;

  /// 是否已超时
  final bool isOverdue;

  const XxtWork({
    required this.name,
    required this.status,
    required this.remainingTime,
    this.courseName,
    this.isUrgent = false,
    this.isOverdue = false,
  });

  /// 从解析的数据创建
  factory XxtWork.fromParsed({
    required String name,
    required String status,
    required String remainingTime,
    String? courseName,
  }) {
    // 判断是否已超时
    bool isOverdue = _checkIsOverdue(remainingTime);

    // 判断是否24小时内截止
    bool isUrgent = false;
    if (!isOverdue) {
      isUrgent = _checkIsUrgent(remainingTime);
    }

    return XxtWork(
      name: name.trim(),
      status: status.trim(),
      remainingTime: remainingTime.trim(),
      courseName: courseName?.trim(),
      isUrgent: isUrgent,
      isOverdue: isOverdue,
    );
  }

  /// 检查是否已过期
  static bool _checkIsOverdue(String remainingTime) {
    final lowerTime = remainingTime.toLowerCase();

    // 检查关键词
    if (lowerTime.contains('已超时') ||
        lowerTime.contains('已截止') ||
        lowerTime.contains('已过期') ||
        lowerTime.contains('超时') ||
        lowerTime.contains('过期') ||
        lowerTime.contains('截止') ||
        lowerTime.contains('逾期') ||
        lowerTime.contains('expired') ||
        lowerTime.contains('overdue')) {
      return true;
    }

    // 检查负数时间（如 "-5小时" 或 "-1天"）
    final negativePattern = RegExp(
      r'-\s*\d+\s*(小时|天|分钟|秒|hour|day|minute|second)',
      caseSensitive: false,
    );
    if (negativePattern.hasMatch(remainingTime)) {
      return true;
    }

    // 检查 "0小时" 或 "0天" 等边界情况
    final zeroTimePattern = RegExp(
      r'^[^\d]*0\s*(小时|天|分钟)',
      caseSensitive: false,
    );
    if (zeroTimePattern.hasMatch(remainingTime)) {
      // 如果只有0小时0分钟，认为已截止
      final hasPositiveTime = RegExp(
        r'[1-9]\d*\s*(小时|天|分钟)',
      ).hasMatch(remainingTime);
      if (!hasPositiveTime) {
        return true;
      }
    }

    return false;
  }

  /// 检查是否即将截止（24小时内）
  static bool _checkIsUrgent(String remainingTime) {
    // 如果包含"天"，检查天数
    if (remainingTime.contains('天')) {
      final daysMatch = RegExp(r'(\d+)\s*天').firstMatch(remainingTime);
      if (daysMatch != null) {
        final days = int.tryParse(daysMatch.group(1) ?? '0') ?? 0;
        // 超过1天就不是紧急
        if (days >= 1) {
          return false;
        }
      }
    }

    // 只有小时，没有天
    if (remainingTime.contains('小时') && !remainingTime.contains('天')) {
      final hoursMatch = RegExp(r'(\d+)\s*小时').firstMatch(remainingTime);
      if (hoursMatch != null) {
        final hours = int.tryParse(hoursMatch.group(1) ?? '0') ?? 0;
        if (hours < 24 && hours >= 0) {
          return true;
        }
      }
    }

    // 只有分钟（没有小时和天），一定是紧急的
    if (remainingTime.contains('分钟') &&
        !remainingTime.contains('小时') &&
        !remainingTime.contains('天')) {
      return true;
    }

    // 只有秒（没有分钟、小时和天），一定是紧急的
    if (remainingTime.contains('秒') &&
        !remainingTime.contains('分钟') &&
        !remainingTime.contains('小时') &&
        !remainingTime.contains('天')) {
      return true;
    }

    return false;
  }

  @override
  String toString() {
    return 'XxtWork(name: $name, status: $status, remainingTime: $remainingTime, isUrgent: $isUrgent, isOverdue: $isOverdue)';
  }
}

/// 学习通作业查询结果
class XxtWorkResult {
  /// 是否成功
  final bool success;

  /// 错误信息
  final String? error;

  /// 未交作业列表
  final List<XxtWork> works;

  /// 是否需要登录
  final bool needLogin;

  const XxtWorkResult({
    required this.success,
    this.error,
    this.works = const [],
    this.needLogin = false,
  });

  /// 成功结果
  factory XxtWorkResult.success(List<XxtWork> works) {
    return XxtWorkResult(success: true, works: works);
  }

  /// 失败结果
  factory XxtWorkResult.failure(String error, {bool needLogin = false}) {
    return XxtWorkResult(success: false, error: error, needLogin: needLogin);
  }

  /// 获取紧急作业（24小时内截止）
  List<XxtWork> get urgentWorks => works.where((w) => w.isUrgent).toList();

  /// 是否有紧急作业
  bool get hasUrgentWorks => urgentWorks.isNotEmpty;

  /// 未交作业数量
  int get workCount => works.length;
}
