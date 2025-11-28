/// 成绩模型
library;

/// 单门课程成绩
class Grade {
  /// 课程名称
  final String courseName;

  /// 课程代码
  final String? courseCode;

  /// 成绩
  final String score;

  /// 绩点
  final double? gpa;

  /// 学分
  final double credit;

  /// 课程性质（必修/选修）
  final String? courseType;

  /// 考试性质（正常/补考/重修）
  final String? examType;

  /// 学期
  final String? semester;

  /// 教师
  final String? teacher;

  const Grade({
    required this.courseName,
    this.courseCode,
    required this.score,
    this.gpa,
    required this.credit,
    this.courseType,
    this.examType,
    this.semester,
    this.teacher,
  });

  /// 是否及格
  bool get isPassed {
    // 处理等级制成绩
    if (score == '优' || score == '优秀' || score == '良' || score == '良好') {
      return true;
    }
    if (score == '中' || score == '中等' || score == '及格' || score == '合格') {
      return true;
    }
    if (score == '不及格' || score == '不合格' || score == '差') {
      return false;
    }

    // 处理百分制成绩
    final numScore = double.tryParse(score);
    if (numScore != null) {
      return numScore >= 60;
    }

    return true; // 无法判断时默认及格
  }

  /// 从 JSON 创建
  factory Grade.fromJson(Map<String, dynamic> json) {
    return Grade(
      courseName: json['courseName'] as String,
      courseCode: json['courseCode'] as String?,
      score: json['score'] as String,
      gpa: (json['gpa'] as num?)?.toDouble(),
      credit: (json['credit'] as num).toDouble(),
      courseType: json['courseType'] as String?,
      examType: json['examType'] as String?,
      semester: json['semester'] as String?,
      teacher: json['teacher'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'courseName': courseName,
      'courseCode': courseCode,
      'score': score,
      'gpa': gpa,
      'credit': credit,
      'courseType': courseType,
      'examType': examType,
      'semester': semester,
      'teacher': teacher,
    };
  }

  @override
  String toString() {
    return 'Grade(courseName: $courseName, score: $score, credit: $credit)';
  }
}

/// 学期成绩汇总
class SemesterGrades {
  /// 学期
  final String semester;

  /// 成绩列表
  final List<Grade> grades;

  const SemesterGrades({required this.semester, required this.grades});

  /// 学期总学分
  double get totalCredits {
    return grades.fold(0.0, (sum, g) => sum + g.credit);
  }

  /// 学期已获学分（及格的课程）
  double get earnedCredits {
    return grades
        .where((g) => g.isPassed)
        .fold(0.0, (sum, g) => sum + g.credit);
  }

  /// 学期平均绩点
  double? get averageGpa {
    final gradesWithGpa = grades.where((g) => g.gpa != null).toList();
    if (gradesWithGpa.isEmpty) return null;

    var totalPoints = 0.0;
    var totalCredits = 0.0;

    for (final grade in gradesWithGpa) {
      totalPoints += grade.gpa! * grade.credit;
      totalCredits += grade.credit;
    }

    return totalCredits > 0 ? totalPoints / totalCredits : null;
  }

  /// 从 JSON 创建
  factory SemesterGrades.fromJson(Map<String, dynamic> json) {
    return SemesterGrades(
      semester: json['semester'] as String,
      grades: (json['grades'] as List<dynamic>)
          .map((e) => Grade.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'semester': semester,
      'grades': grades.map((g) => g.toJson()).toList(),
    };
  }
}
