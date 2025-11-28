/// 用户模型
library;

class User {
  /// 学号
  final String studentId;

  /// 姓名
  final String? name;

  /// 学院
  final String? college;

  /// 专业
  final String? major;

  /// 班级
  final String? className;

  /// 入学年份
  final String? enrollmentYear;

  /// 学习层次（本科/专科等）
  final String? studyLevel;

  const User({
    required this.studentId,
    this.name,
    this.college,
    this.major,
    this.className,
    this.enrollmentYear,
    this.studyLevel,
  });

  /// 从 JSON 创建
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      studentId: json['studentId'] as String,
      name: json['name'] as String?,
      college: json['college'] as String?,
      major: json['major'] as String?,
      className: json['className'] as String?,
      enrollmentYear: json['enrollmentYear'] as String?,
      studyLevel: json['studyLevel'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'name': name,
      'college': college,
      'major': major,
      'className': className,
      'enrollmentYear': enrollmentYear,
      'studyLevel': studyLevel,
    };
  }

  /// 复制并修改
  User copyWith({
    String? studentId,
    String? name,
    String? college,
    String? major,
    String? className,
    String? enrollmentYear,
    String? studyLevel,
  }) {
    return User(
      studentId: studentId ?? this.studentId,
      name: name ?? this.name,
      college: college ?? this.college,
      major: major ?? this.major,
      className: className ?? this.className,
      enrollmentYear: enrollmentYear ?? this.enrollmentYear,
      studyLevel: studyLevel ?? this.studyLevel,
    );
  }

  @override
  String toString() {
    return 'User(studentId: $studentId, name: $name)';
  }
}
