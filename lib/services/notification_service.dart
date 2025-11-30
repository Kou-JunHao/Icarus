/// 通知服务
/// 处理课程提醒通知
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../models/models.dart';
import 'auth_storage.dart';

/// 通知服务
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // 通知设置 keys
  static const String _keyNotificationEnabled = 'notification_enabled';
  static const String _keyNotificationMinutesBefore =
      'notification_minutes_before';

  // 默认提前分钟数
  static const int defaultMinutesBefore = 15;

  // 通知渠道
  static const String _channelId = 'course_reminder';
  static const String _channelName = '课程提醒';
  static const String _channelDescription = '课程开始前的提醒通知';

  bool _isInitialized = false;
  static bool _tzInitialized = false;

  /// 初始化时区数据（延迟加载，减少启动内存）
  static void _initializeTimezone() {
    if (_tzInitialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    _tzInitialized = true;
  }

  /// 初始化通知服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android 初始化设置
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS 初始化设置
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 创建通知渠道 (Android 8.0+)
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    _isInitialized = true;
    debugPrint('通知服务初始化完成');
  }

  /// 通知点击回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('通知被点击: ${response.payload}');
    // 可以在这里处理点击通知后的跳转逻辑
  }

  /// 请求通知权限
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    } else if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  /// 检查通知权限
  Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidPlugin?.areNotificationsEnabled() ?? false;
    }
    return true; // iOS 默认返回 true
  }

  /// 获取通知是否启用
  Future<bool> isNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationEnabled) ?? false;
  }

  /// 设置通知是否启用
  Future<void> setNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationEnabled, enabled);
  }

  /// 获取提前通知的分钟数
  Future<int> getMinutesBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyNotificationMinutesBefore) ?? defaultMinutesBefore;
  }

  /// 设置提前通知的分钟数
  Future<void> setMinutesBefore(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNotificationMinutesBefore, minutes);
  }

  /// 为课程安排通知
  /// [schedule] 课程表
  /// [currentWeek] 当前周次
  Future<void> scheduleCourseNotifications({
    required Schedule schedule,
    required int currentWeek,
  }) async {
    if (!_isInitialized) await initialize();
    // 延迟初始化时区数据
    _initializeTimezone();

    final isEnabled = await isNotificationEnabled();
    if (!isEnabled) {
      debugPrint('通知未启用，跳过安排通知');
      return;
    }

    final hasPermission = await checkPermission();
    if (!hasPermission) {
      debugPrint('没有通知权限，跳过安排通知');
      return;
    }

    // 取消所有已安排的通知
    await cancelAllNotifications();

    // 获取提前通知的分钟数
    final minutesBefore = await getMinutesBefore();

    // 获取时间表
    final settings = await AuthStorage.getScheduleSettings();
    final customTimetable = await AuthStorage.getCustomTimetable();
    final sectionTimes =
        customTimetable ?? AuthStorage.generateTimetable(settings);

    final now = DateTime.now();
    final todayWeekday = now.weekday;

    // 为本周剩余的课程安排通知
    int notificationId = 0;

    for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
      final targetWeekday = ((todayWeekday - 1 + dayOffset) % 7) + 1;
      final targetDate = now.add(Duration(days: dayOffset));

      // 获取该天的课程
      final courses = schedule.getCoursesForDay(currentWeek, targetWeekday);

      for (final course in courses) {
        // 获取课程开始时间
        final startTime = sectionTimes[course.startSection];
        if (startTime == null) continue;

        final timeParts = startTime.$1.split(':');
        if (timeParts.length != 2) continue;

        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;

        // 计算通知时间（课程开始前 N 分钟）
        var notifyTime = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          hour,
          minute,
        ).subtract(Duration(minutes: minutesBefore));

        // 如果通知时间已过，跳过
        if (notifyTime.isBefore(now)) continue;

        // 安排通知
        await _scheduleNotification(
          id: notificationId++,
          title: '课程提醒',
          body:
              '${course.name} 将在 $minutesBefore 分钟后开始\n📍 ${course.location ?? '未知地点'}',
          scheduledTime: notifyTime,
          payload: course.name,
        );

        debugPrint('已安排通知: ${course.name} at $notifyTime');
      }
    }

    debugPrint('共安排了 $notificationId 个课程通知');
  }

  /// 安排单个通知
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(body),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  /// 为作业安排通知
  Future<void> scheduleWorkNotification({
    required int id,
    required String workName,
    String? courseName,
    required int hoursRemaining,
    required DateTime scheduledTime,
  }) async {
    if (!_isInitialized) await initialize();
    _initializeTimezone();

    final isEnabled = await isNotificationEnabled();
    if (!isEnabled) return;

    final hasPermission = await checkPermission();
    if (!hasPermission) return;

    final courseInfo = courseName != null ? '[$courseName] ' : '';
    final body = '$courseInfo$workName\n⏰ 距离截止还有 $hoursRemaining 小时，请尽快完成！';

    final androidDetails = AndroidNotificationDetails(
      'work_reminder',
      '作业提醒',
      channelDescription: '作业截止前的提醒通知',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(body),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notifications.zonedSchedule(
      id,
      '📚 作业即将截止',
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'work_$workName',
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );

    debugPrint('已安排作业通知: $workName, 时间: $scheduledTime');
  }

  /// 立即显示通知（用于测试）
  Future<void> showTestNotification() async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notifications.show(999, '测试通知', '这是一条测试通知，说明通知功能正常工作', details);
  }

  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    debugPrint('已取消所有通知');
  }

  /// 取消指定 ID 的通知
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  /// 获取待处理的通知列表
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}
