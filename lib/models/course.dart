/// 课程模型
library;

import 'package:flutter/material.dart';

/// 课程信息
class Course {
  /// 课程名称
  final String name;

  /// 教师
  final String? teacher;

  /// 上课地点
  final String? location;

  /// 星期几 (1-7)
  final int weekday;

  /// 开始节次
  final int startSection;

  /// 结束节次
  final int endSection;

  /// 周次范围 (如 "1-16周")
  final String? weekRange;

  /// 周次列表
  final List<int> weeks;

  /// 课程颜色（用于UI显示）
  final Color? color;

  const Course({
    required this.name,
    this.teacher,
    this.location,
    required this.weekday,
    required this.startSection,
    required this.endSection,
    this.weekRange,
    this.weeks = const [],
    this.color,
  });

  /// 节次数量
  int get sectionCount => endSection - startSection + 1;

  /// 从 JSON 创建
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      name: json['name'] as String,
      teacher: json['teacher'] as String?,
      location: json['location'] as String?,
      weekday: json['weekday'] as int,
      startSection: json['startSection'] as int,
      endSection: json['endSection'] as int,
      weekRange: json['weekRange'] as String?,
      weeks: (json['weeks'] as List<dynamic>?)?.cast<int>() ?? [],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'teacher': teacher,
      'location': location,
      'weekday': weekday,
      'startSection': startSection,
      'endSection': endSection,
      'weekRange': weekRange,
      'weeks': weeks,
    };
  }

  /// 检查是否在指定周次上课
  bool isInWeek(int week) {
    return weeks.contains(week);
  }

  @override
  String toString() {
    return 'Course(name: $name, weekday: $weekday, sections: $startSection-$endSection)';
  }
}

/// 课程表（一周的课程安排）
class Schedule {
  /// 学期信息
  final String? semester;

  /// 当前周次
  final int currentWeek;

  /// 总周数
  final int totalWeeks;

  /// 所有课程
  final List<Course> courses;

  const Schedule({
    this.semester,
    this.currentWeek = 1,
    this.totalWeeks = 20,
    this.courses = const [],
  });

  /// 获取指定周次和星期的课程
  List<Course> getCoursesForDay(int week, int weekday) {
    return courses
        .where((c) => c.weekday == weekday && c.isInWeek(week))
        .toList()
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
  }

  /// 获取指定周次的所有课程
  List<Course> getCoursesForWeek(int week) {
    return courses.where((c) => c.isInWeek(week)).toList();
  }

  /// 从 JSON 创建
  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      semester: json['semester'] as String?,
      currentWeek: json['currentWeek'] as int? ?? 1,
      totalWeeks: json['totalWeeks'] as int? ?? 20,
      courses:
          (json['courses'] as List<dynamic>?)
              ?.map((e) => Course.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'semester': semester,
      'currentWeek': currentWeek,
      'totalWeeks': totalWeeks,
      'courses': courses.map((c) => c.toJson()).toList(),
    };
  }
}
