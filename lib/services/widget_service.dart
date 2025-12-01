/// 桌面小组件服务
/// 管理今日课程和未交作业小组件的数据更新
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/models.dart';
import '../models/xxt_work.dart';
import 'auth_storage.dart';

/// 小组件服务
class WidgetService {
  // 小组件相关常量
  static const String appGroupId = 'group.uno.skkk.icarus';

  // 今日课程小组件
  static const String androidWidgetName = 'TodayCoursesWidgetProvider';
  static const String iOSWidgetName = 'TodayCoursesWidget';

  // 未交作业小组件
  static const String androidWorksWidgetName = 'PendingWorksWidgetProvider';
  static const String iOSWorksWidgetName = 'PendingWorksWidget';

  // 今日课程小组件数据 keys
  static const String keyTodayCourses = 'today_courses';
  static const String keyCurrentWeek = 'current_week';
  static const String keyLastUpdate = 'last_update';
  static const String keySemester = 'semester';

  // 未交作业小组件数据 keys
  static const String keyPendingWorks = 'pending_works';
  static const String keyWorksCount = 'works_count';
  static const String keyWorksLastUpdate = 'works_last_update';
  static const String keyWorksNeedLogin = 'works_need_login';

  /// 初始化小组件服务
  static Future<void> initialize() async {
    try {
      // 设置 App Group ID (iOS)
      await HomeWidget.setAppGroupId(appGroupId);

      // 尝试从缓存更新小组件（应用启动时）
      await updateWidgetFromCache();

      debugPrint('小组件服务初始化成功');
    } catch (e) {
      debugPrint('小组件服务初始化失败: $e');
    }
  }

  /// 更新小组件数据
  static Future<void> updateWidget({
    required Schedule? schedule,
    required int currentWeek,
  }) async {
    try {
      if (schedule == null) {
        debugPrint('课程表为空，跳过小组件更新');
        return;
      }

      // 获取今日星期几
      final now = DateTime.now();
      final weekday = now.weekday;

      // 获取今日课程
      final todayCourses = schedule.getCoursesForDay(currentWeek, weekday);

      // 获取时间表
      final settings = await AuthStorage.getScheduleSettings();
      final customTimetable = await AuthStorage.getCustomTimetable();
      final timetable =
          customTimetable ?? AuthStorage.generateTimetable(settings);

      // 转换为小组件数据格式
      final coursesData = todayCourses.map((course) {
        final startTime = timetable[course.startSection];
        final endTime = timetable[course.endSection];
        return {
          'name': course.name,
          'location': course.location ?? '',
          'teacher': course.teacher ?? '',
          'startSection': course.startSection,
          'endSection': course.endSection,
          'startTime': startTime?.$1 ?? '',
          'endTime': endTime?.$2 ?? '',
        };
      }).toList();

      // 保存数据到小组件
      await HomeWidget.saveWidgetData<String>(
        keyTodayCourses,
        jsonEncode(coursesData),
      );
      await HomeWidget.saveWidgetData<int>(keyCurrentWeek, currentWeek);
      await HomeWidget.saveWidgetData<String>(
        keySemester,
        schedule.semester ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        keyLastUpdate,
        now.toIso8601String(),
      );

      // 通知小组件更新
      await HomeWidget.updateWidget(
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

      debugPrint('小组件更新成功: ${todayCourses.length} 节课');
    } catch (e) {
      debugPrint('小组件更新失败: $e');
    }
  }

  /// 从缓存更新小组件
  static Future<void> updateWidgetFromCache() async {
    try {
      // 从缓存读取课程表数据
      final (cacheData, _) = await AuthStorage.getScheduleCache();
      if (cacheData == null) {
        debugPrint('没有课程表缓存数据');
        return;
      }

      final json = jsonDecode(cacheData) as Map<String, dynamic>;
      final schedule = Schedule.fromJson(json);
      final currentWeek = await AuthStorage.calculateCurrentWeek();

      await updateWidget(schedule: schedule, currentWeek: currentWeek);
    } catch (e) {
      debugPrint('从缓存更新小组件失败: $e');
    }
  }

  /// 清除小组件数据
  static Future<void> clearWidget() async {
    try {
      await HomeWidget.saveWidgetData<String>(keyTodayCourses, '[]');
      await HomeWidget.saveWidgetData<int>(keyCurrentWeek, 0);
      await HomeWidget.saveWidgetData<String>(keySemester, '');
      await HomeWidget.saveWidgetData<String>(keyLastUpdate, '');

      await HomeWidget.updateWidget(
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

      debugPrint('小组件数据已清除');
    } catch (e) {
      debugPrint('清除小组件数据失败: $e');
    }
  }

  // ==================== 未交作业小组件 ====================

  /// 更新未交作业小组件数据
  static Future<void> updateWorksWidget({
    required List<XxtWork> works,
    required bool needLogin,
  }) async {
    try {
      final now = DateTime.now();

      // 过滤掉已超时作业，并按剩余时间排序（紧急的在前）
      final filteredWorks = works.where((w) => !w.isOverdue).toList()
        ..sort((a, b) {
          // 紧急作业优先
          if (a.isUrgent && !b.isUrgent) return -1;
          if (!a.isUrgent && b.isUrgent) return 1;
          // 然后按剩余时间排序（解析时间字符串）
          return _compareRemainingTime(a.remainingTime, b.remainingTime);
        });

      // 转换为小组件数据格式
      final worksData = filteredWorks.map((work) {
        return {
          'name': work.name,
          'courseName': work.courseName ?? '',
          'remainingTime': work.remainingTime,
          'isUrgent': work.isUrgent,
          'isOverdue': work.isOverdue,
        };
      }).toList();

      // 保存数据到小组件
      await HomeWidget.saveWidgetData<String>(
        keyPendingWorks,
        jsonEncode(worksData),
      );
      await HomeWidget.saveWidgetData<int>(keyWorksCount, filteredWorks.length);
      await HomeWidget.saveWidgetData<String>(
        keyWorksLastUpdate,
        now.toIso8601String(),
      );
      await HomeWidget.saveWidgetData<bool>(keyWorksNeedLogin, needLogin);

      // 通知小组件更新
      await HomeWidget.updateWidget(
        androidName: androidWorksWidgetName,
        iOSName: iOSWorksWidgetName,
      );

      debugPrint('作业小组件更新成功: ${filteredWorks.length} 项作业');
    } catch (e) {
      debugPrint('作业小组件更新失败: $e');
    }
  }

  /// 比较剩余时间字符串
  static int _compareRemainingTime(String a, String b) {
    final aMinutes = _parseRemainingTimeToMinutes(a);
    final bMinutes = _parseRemainingTimeToMinutes(b);
    return aMinutes.compareTo(bMinutes);
  }

  /// 将剩余时间字符串解析为分钟数
  static int _parseRemainingTimeToMinutes(String time) {
    if (time.isEmpty || time == '未设置截止时间') {
      return 999999; // 无截止时间放到最后
    }

    int totalMinutes = 0;

    // 解析天数
    final daysMatch = RegExp(r'(\d+)\s*天').firstMatch(time);
    if (daysMatch != null) {
      totalMinutes += (int.tryParse(daysMatch.group(1) ?? '0') ?? 0) * 24 * 60;
    }

    // 解析小时数
    final hoursMatch = RegExp(r'(\d+)\s*小时').firstMatch(time);
    if (hoursMatch != null) {
      totalMinutes += (int.tryParse(hoursMatch.group(1) ?? '0') ?? 0) * 60;
    }

    // 解析分钟数
    final minutesMatch = RegExp(r'(\d+)\s*分钟?').firstMatch(time);
    if (minutesMatch != null) {
      totalMinutes += int.tryParse(minutesMatch.group(1) ?? '0') ?? 0;
    }

    return totalMinutes;
  }

  /// 更新作业小组件为需要登录状态
  static Future<void> updateWorksWidgetNeedLogin() async {
    try {
      await HomeWidget.saveWidgetData<String>(keyPendingWorks, '[]');
      await HomeWidget.saveWidgetData<int>(keyWorksCount, 0);
      await HomeWidget.saveWidgetData<String>(keyWorksLastUpdate, '');
      await HomeWidget.saveWidgetData<bool>(keyWorksNeedLogin, true);

      await HomeWidget.updateWidget(
        androidName: androidWorksWidgetName,
        iOSName: iOSWorksWidgetName,
      );

      debugPrint('作业小组件设置为需要登录状态');
    } catch (e) {
      debugPrint('更新作业小组件状态失败: $e');
    }
  }

  /// 清除作业小组件数据
  static Future<void> clearWorksWidget() async {
    try {
      await HomeWidget.saveWidgetData<String>(keyPendingWorks, '[]');
      await HomeWidget.saveWidgetData<int>(keyWorksCount, 0);
      await HomeWidget.saveWidgetData<String>(keyWorksLastUpdate, '');
      await HomeWidget.saveWidgetData<bool>(keyWorksNeedLogin, true);

      await HomeWidget.updateWidget(
        androidName: androidWorksWidgetName,
        iOSName: iOSWorksWidgetName,
      );

      debugPrint('作业小组件数据已清除');
    } catch (e) {
      debugPrint('清除作业小组件数据失败: $e');
    }
  }

  /// 清除所有小组件数据
  static Future<void> clearAllWidgets() async {
    await clearWidget();
    await clearWorksWidget();
  }

  /// 检查小组件点击事件
  static Future<Uri?> checkForWidgetLaunch() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (e) {
      debugPrint('检查小组件启动事件失败: $e');
      return null;
    }
  }

  /// 注册小组件点击回调
  static void registerInteractivityCallback(Function(Uri?) callback) {
    HomeWidget.widgetClicked.listen(callback);
  }
}
