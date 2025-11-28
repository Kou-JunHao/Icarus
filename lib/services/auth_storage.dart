/// 认证存储服务
///
/// 处理登录凭据的持久化存储
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 存储的凭据
class StoredCredentials {
  final String username;
  final String password;

  const StoredCredentials({required this.username, required this.password});
}

/// 认证存储服务
class AuthStorage {
  static const String _keyUsername = 'auth_username';
  static const String _keyPassword = 'auth_password';
  static const String _keyRememberMe = 'auth_remember_me';
  static const String _keySemesterStartDate = 'semester_start_date';

  // 缓存相关 keys
  static const String _keyWeatherCache = 'cache_weather';
  static const String _keyWeatherCacheTime = 'cache_weather_time';
  static const String _keyScheduleCache = 'cache_schedule';
  static const String _keyScheduleCacheTime = 'cache_schedule_time';
  static const String _keyGradesCache = 'cache_grades';
  static const String _keyGradesCacheTime = 'cache_grades_time';

  // 天气城市相关 keys
  static const String _keyWeatherCityPinyin = 'weather_city_pinyin';
  static const String _keyWeatherCityName = 'weather_city_name';

  // 缓存时间配置（分钟）
  static const int weatherCacheMinutes = 30; // 天气缓存30分钟
  static const int scheduleCacheMinutes = 480; // 课程表缓存8小时（480分钟）
  static const int gradesCacheMinutes = 21600; // 成绩缓存15天（15*24*60=21600分钟）

  /// 保存登录凭据
  static Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyPassword, password);
    await prefs.setBool(_keyRememberMe, true);
  }

  /// 获取保存的凭据
  static Future<StoredCredentials?> getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_keyRememberMe) ?? false;

    if (!rememberMe) {
      return null;
    }

    final username = prefs.getString(_keyUsername);
    final password = prefs.getString(_keyPassword);

    if (username == null || password == null) {
      return null;
    }

    return StoredCredentials(username: username, password: password);
  }

  /// 清除保存的凭据
  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyPassword);
    await prefs.setBool(_keyRememberMe, false);
  }

  /// 检查是否有保存的凭据
  static Future<bool> hasCredentials() async {
    final credentials = await getCredentials();
    return credentials != null;
  }

  /// 保存开学日期
  static Future<void> saveSemesterStartDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySemesterStartDate, date.toIso8601String());
  }

  /// 获取开学日期
  static Future<DateTime?> getSemesterStartDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_keySemesterStartDate);
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  /// 根据开学日期计算当前周次
  static Future<int> calculateCurrentWeek() async {
    final startDate = await getSemesterStartDate();
    if (startDate == null) return 1;

    final now = DateTime.now();
    final difference = now.difference(startDate).inDays;

    if (difference < 0) return 1; // 还没开学

    final week = (difference ~/ 7) + 1;
    return week.clamp(1, 25);
  }

  // 周末显示模式 key
  static const String _keyWeekendMode = 'schedule_weekend_mode';

  /// 保存周末显示模式
  /// 0: 自动（根据是否有周末课程）
  /// 1: 始终显示5天（周一到周五）
  /// 2: 始终显示7天（周一到周日）
  static Future<void> saveWeekendMode(int mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWeekendMode, mode);
  }

  /// 获取周末显示模式
  static Future<int> getWeekendMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyWeekendMode) ?? 0; // 默认自动
  }

  // 课程表设置 keys
  static const String _keyCustomTimetable = 'custom_timetable';
  static const String _keyScheduleSettings = 'schedule_settings';

  /// 课程表设置数据类
  static const defaultScheduleSettings = ScheduleSettings(
    morningStartTime: '08:20',
    afternoonStartTime: '14:00',
    eveningStartTime: '18:00',
    morningSections: 4,
    afternoonSections: 4,
    eveningSections: 4,
    classDuration: 45,
    shortBreak: 5,
    longBreak: 20,
    longBreakInterval: 2, // 每2节课一次大课间
    showNonCurrentWeekCourses: false, // 默认不显示非本周课程
  );

  /// 保存课程表设置
  static Future<void> saveScheduleSettings(ScheduleSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyScheduleSettings, settings.toStorageString());
  }

  /// 获取课程表设置
  static Future<ScheduleSettings> getScheduleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_keyScheduleSettings);
    if (data == null || data.isEmpty) return defaultScheduleSettings;
    return ScheduleSettings.fromStorageString(data) ?? defaultScheduleSettings;
  }

  /// 根据设置生成时间表
  static Map<int, (String, String)> generateTimetable(
    ScheduleSettings settings,
  ) {
    final result = <int, (String, String)>{};
    int section = 1;

    // 生成上午课程时间
    var currentTime = _parseTime(settings.morningStartTime);
    for (int i = 0; i < settings.morningSections; i++) {
      final endTime = currentTime.add(
        Duration(minutes: settings.classDuration),
      );
      result[section] = (_formatTime(currentTime), _formatTime(endTime));
      section++;
      // 计算下一节课开始时间
      if (i < settings.morningSections - 1) {
        final isLongBreak = (i + 1) % settings.longBreakInterval == 0;
        currentTime = endTime.add(
          Duration(
            minutes: isLongBreak ? settings.longBreak : settings.shortBreak,
          ),
        );
      }
    }

    // 生成下午课程时间
    currentTime = _parseTime(settings.afternoonStartTime);
    for (int i = 0; i < settings.afternoonSections; i++) {
      final endTime = currentTime.add(
        Duration(minutes: settings.classDuration),
      );
      result[section] = (_formatTime(currentTime), _formatTime(endTime));
      section++;
      if (i < settings.afternoonSections - 1) {
        final isLongBreak = (i + 1) % settings.longBreakInterval == 0;
        currentTime = endTime.add(
          Duration(
            minutes: isLongBreak ? settings.longBreak : settings.shortBreak,
          ),
        );
      }
    }

    // 生成晚上课程时间
    currentTime = _parseTime(settings.eveningStartTime);
    for (int i = 0; i < settings.eveningSections; i++) {
      final endTime = currentTime.add(
        Duration(minutes: settings.classDuration),
      );
      result[section] = (_formatTime(currentTime), _formatTime(endTime));
      section++;
      if (i < settings.eveningSections - 1) {
        final isLongBreak = (i + 1) % settings.longBreakInterval == 0;
        currentTime = endTime.add(
          Duration(
            minutes: isLongBreak ? settings.longBreak : settings.shortBreak,
          ),
        );
      }
    }

    return result;
  }

  static DateTime _parseTime(String time) {
    final parts = time.split(':');
    return DateTime(2024, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
  }

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 保存自定义时间表
  /// 格式: "1,08:00,08:45;2,08:50,09:35;..."
  static Future<void> saveCustomTimetable(
    Map<int, (String, String)> timetable,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = timetable.entries
        .map((e) => '${e.key},${e.value.$1},${e.value.$2}')
        .join(';');
    await prefs.setString(_keyCustomTimetable, entries);
  }

  /// 获取自定义时间表
  static Future<Map<int, (String, String)>?> getCustomTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_keyCustomTimetable);
    if (data == null || data.isEmpty) return null;

    try {
      final result = <int, (String, String)>{};
      for (final entry in data.split(';')) {
        final parts = entry.split(',');
        if (parts.length == 3) {
          final section = int.parse(parts[0]);
          result[section] = (parts[1], parts[2]);
        }
      }
      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }

  /// 清除自定义时间表（恢复默认）
  static Future<void> clearCustomTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCustomTimetable);
  }

  /// 清除课程表设置（恢复默认）
  static Future<void> clearScheduleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyScheduleSettings);
  }

  // ==================== 天气缓存 ====================

  /// 保存天气缓存
  static Future<void> saveWeatherCache(String jsonData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeatherCache, jsonData);
    await prefs.setString(
      _keyWeatherCacheTime,
      DateTime.now().toIso8601String(),
    );
  }

  /// 获取天气缓存
  static Future<(String?, bool)> getWeatherCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_keyWeatherCache);
    final timeStr = prefs.getString(_keyWeatherCacheTime);

    if (data == null || timeStr == null) {
      return (null, false);
    }

    final cachedAt = DateTime.tryParse(timeStr);
    if (cachedAt == null) {
      return (data, false);
    }

    final isValid =
        DateTime.now().difference(cachedAt).inMinutes < weatherCacheMinutes;
    return (data, isValid);
  }

  /// 清除天气缓存
  static Future<void> clearWeatherCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWeatherCache);
    await prefs.remove(_keyWeatherCacheTime);
  }

  // ==================== 天气城市设置 ====================

  /// 保存天气城市设置
  /// [cityPinyin] 城市拼音（用于 API 请求）
  /// [cityName] 城市显示名称（用于 UI 显示）
  static Future<void> saveWeatherCity(
    String cityPinyin,
    String cityName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeatherCityPinyin, cityPinyin);
    await prefs.setString(_keyWeatherCityName, cityName);
    // 更换城市后清除旧的天气缓存
    await clearWeatherCache();
  }

  /// 获取天气城市拼音（用于 API 请求）
  static Future<String?> getWeatherCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWeatherCityPinyin);
  }

  /// 获取天气城市显示名称
  static Future<String?> getWeatherCityName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWeatherCityName);
  }

  /// 清除天气城市设置
  static Future<void> clearWeatherCity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWeatherCityPinyin);
    await prefs.remove(_keyWeatherCityName);
  }

  // ==================== 课程表缓存 ====================

  /// 保存课程表缓存
  static Future<void> saveScheduleCache(String jsonData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyScheduleCache, jsonData);
    await prefs.setString(
      _keyScheduleCacheTime,
      DateTime.now().toIso8601String(),
    );
  }

  /// 获取课程表缓存
  static Future<(String?, bool)> getScheduleCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_keyScheduleCache);
    final timeStr = prefs.getString(_keyScheduleCacheTime);

    if (data == null || timeStr == null) {
      return (null, false);
    }

    final cachedAt = DateTime.tryParse(timeStr);
    if (cachedAt == null) {
      return (data, false);
    }

    final isValid =
        DateTime.now().difference(cachedAt).inMinutes < scheduleCacheMinutes;
    return (data, isValid);
  }

  /// 清除课程表缓存
  static Future<void> clearScheduleCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyScheduleCache);
    await prefs.remove(_keyScheduleCacheTime);
  }

  /// 清除所有数据缓存
  static Future<void> clearAllDataCache() async {
    await clearWeatherCache();
    await clearScheduleCache();
    await clearGradesCache();
  }

  // ==================== 成绩缓存 ====================

  /// 保存成绩缓存
  static Future<void> saveGradesCache(String jsonData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGradesCache, jsonData);
    await prefs.setString(
      _keyGradesCacheTime,
      DateTime.now().toIso8601String(),
    );
  }

  /// 获取成绩缓存
  /// 返回 (缓存数据, 是否有效)
  static Future<(String?, bool)> getGradesCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_keyGradesCache);
    final timeStr = prefs.getString(_keyGradesCacheTime);

    if (data == null || timeStr == null) {
      return (null, false);
    }

    final cachedAt = DateTime.tryParse(timeStr);
    if (cachedAt == null) {
      return (data, false);
    }

    final isValid =
        DateTime.now().difference(cachedAt).inMinutes < gradesCacheMinutes;
    return (data, isValid);
  }

  /// 清除成绩缓存
  static Future<void> clearGradesCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGradesCache);
    await prefs.remove(_keyGradesCacheTime);
  }
}

/// 课程表设置数据类
class ScheduleSettings {
  final String morningStartTime;
  final String afternoonStartTime;
  final String eveningStartTime;
  final int morningSections;
  final int afternoonSections;
  final int eveningSections;
  final int classDuration; // 每节课时长（分钟）
  final int shortBreak; // 小课间（分钟）
  final int longBreak; // 大课间（分钟）
  final int longBreakInterval; // 每几节课一次大课间
  final bool showNonCurrentWeekCourses; // 是否显示非本周课程

  const ScheduleSettings({
    required this.morningStartTime,
    required this.afternoonStartTime,
    required this.eveningStartTime,
    required this.morningSections,
    required this.afternoonSections,
    required this.eveningSections,
    required this.classDuration,
    required this.shortBreak,
    required this.longBreak,
    required this.longBreakInterval,
    this.showNonCurrentWeekCourses = false,
  });

  int get totalSections =>
      morningSections + afternoonSections + eveningSections;

  ScheduleSettings copyWith({
    String? morningStartTime,
    String? afternoonStartTime,
    String? eveningStartTime,
    int? morningSections,
    int? afternoonSections,
    int? eveningSections,
    int? classDuration,
    int? shortBreak,
    int? longBreak,
    int? longBreakInterval,
    bool? showNonCurrentWeekCourses,
  }) {
    return ScheduleSettings(
      morningStartTime: morningStartTime ?? this.morningStartTime,
      afternoonStartTime: afternoonStartTime ?? this.afternoonStartTime,
      eveningStartTime: eveningStartTime ?? this.eveningStartTime,
      morningSections: morningSections ?? this.morningSections,
      afternoonSections: afternoonSections ?? this.afternoonSections,
      eveningSections: eveningSections ?? this.eveningSections,
      classDuration: classDuration ?? this.classDuration,
      shortBreak: shortBreak ?? this.shortBreak,
      longBreak: longBreak ?? this.longBreak,
      longBreakInterval: longBreakInterval ?? this.longBreakInterval,
      showNonCurrentWeekCourses:
          showNonCurrentWeekCourses ?? this.showNonCurrentWeekCourses,
    );
  }

  String toStorageString() {
    return '$morningStartTime|$afternoonStartTime|$eveningStartTime|'
        '$morningSections|$afternoonSections|$eveningSections|'
        '$classDuration|$shortBreak|$longBreak|$longBreakInterval|'
        '${showNonCurrentWeekCourses ? 1 : 0}';
  }

  static ScheduleSettings? fromStorageString(String data) {
    try {
      final parts = data.split('|');
      // 兼容旧版本（10个字段）和新版本（11个字段）
      if (parts.length < 10) return null;
      return ScheduleSettings(
        morningStartTime: parts[0],
        afternoonStartTime: parts[1],
        eveningStartTime: parts[2],
        morningSections: int.parse(parts[3]),
        afternoonSections: int.parse(parts[4]),
        eveningSections: int.parse(parts[5]),
        classDuration: int.parse(parts[6]),
        shortBreak: int.parse(parts[7]),
        longBreak: int.parse(parts[8]),
        longBreakInterval: int.parse(parts[9]),
        showNonCurrentWeekCourses: parts.length > 10 && parts[10] == '1',
      );
    } catch (e) {
      return null;
    }
  }
}
