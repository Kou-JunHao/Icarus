/// 数据管理器
/// 统一管理教务系统数据的获取和缓存
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'auth_storage.dart';
import 'jwxt_service.dart';
import 'widget_service.dart';
import 'notification_service.dart';

/// 数据加载状态
enum LoadingState { idle, loading, loaded, error }

/// 数据管理器
/// 提供数据缓存和刷新功能
class DataManager extends ChangeNotifier {
  final JwxtService jwxtService;

  // 是否启用延迟刷新模式（无感登录时使用）
  bool _delayedRefreshMode = false;
  static const int _delayedRefreshSeconds = 10; // 延迟刷新时间（秒）

  DataManager({required this.jwxtService});

  /// 设置延迟刷新模式
  void setDelayedRefreshMode(bool enabled) {
    _delayedRefreshMode = enabled;
  }

  // 用户信息
  User? _user;
  User? get user => _user;
  LoadingState _userState = LoadingState.idle;
  LoadingState get userState => _userState;

  // 课程表
  Schedule? _schedule;
  Schedule? get schedule => _schedule;
  LoadingState _scheduleState = LoadingState.idle;
  LoadingState get scheduleState => _scheduleState;

  // 当前周次
  int _currentWeek = 1;
  int get currentWeek => _currentWeek;

  // 成绩
  List<SemesterGrades>? _grades;
  List<SemesterGrades>? get grades => _grades;
  LoadingState _gradesState = LoadingState.idle;
  LoadingState get gradesState => _gradesState;

  // 可用学期列表
  List<String> _semesters = [];
  List<String> get semesters => _semesters;

  // 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // 是否已初始化
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 初始化数据（登录成功后调用）
  /// [delayedRefresh] 是否延迟刷新数据（无感登录模式）
  Future<void> initialize({bool delayedRefresh = false}) async {
    // 避免重复初始化
    if (_initialized) {
      debugPrint('DataManager 已经初始化，跳过');
      return;
    }
    _initialized = true;
    _delayedRefreshMode = delayedRefresh;

    // 先从缓存加载数据（立即显示）
    await Future.wait([
      _loadUserFromCache(),
      _loadScheduleFromCache(),
      _loadGradesFromCache(),
    ]);

    if (delayedRefresh) {
      // 延迟刷新模式：等待一段时间后再从网络刷新
      debugPrint('延迟 $_delayedRefreshSeconds 秒后刷新数据...');
      Future.delayed(Duration(seconds: _delayedRefreshSeconds), () {
        if (!_disposed) {
          _refreshDataFromNetwork();
        }
      });
    } else {
      // 立即刷新模式
      await _refreshDataFromNetwork();
    }
  }

  bool _disposed = false;

  /// 从网络刷新数据
  Future<void> _refreshDataFromNetwork() async {
    await Future.wait([
      loadUserInfo(forceRefresh: true),
      loadSchedule(forceRefresh: true),
      loadGrades(forceRefresh: true),
    ]);
  }

  /// 从缓存加载用户信息
  Future<bool> _loadUserFromCache() async {
    try {
      final (cacheData, isValid) = await AuthStorage.getUserCache();
      if (cacheData != null) {
        final json = jsonDecode(cacheData) as Map<String, dynamic>;
        _user = User.fromJson(json);
        _userState = LoadingState.loaded;
        debugPrint('使用用户信息缓存数据 (有效: $isValid)');
        notifyListeners();
        return isValid; // 返回缓存是否有效，无效时需要刷新
      }
    } catch (e) {
      debugPrint('读取用户信息缓存失败: $e');
    }
    return false;
  }

  /// 保存用户信息到缓存
  Future<void> _saveUserToCache(User user) async {
    try {
      final json = jsonEncode(user.toJson());
      await AuthStorage.saveUserCache(json);
    } catch (e) {
      debugPrint('保存用户信息缓存失败: $e');
    }
  }

  /// 加载用户信息
  Future<void> loadUserInfo({bool forceRefresh = false}) async {
    if (_userState == LoadingState.loading) return;

    // 非强制刷新时，先尝试从缓存加载
    if (!forceRefresh) {
      if (_user != null) return; // 内存中已有数据

      // 尝试从持久化缓存加载
      final (cacheData, isValid) = await AuthStorage.getUserCache();
      if (cacheData != null) {
        try {
          final json = jsonDecode(cacheData) as Map<String, dynamic>;
          _user = User.fromJson(json);
          _userState = LoadingState.loaded;
          notifyListeners();

          // 如果缓存无效（超过30天），在后台刷新
          if (!isValid) {
            debugPrint('用户信息缓存已过期，后台刷新...');
            _refreshUserInBackground();
          }
          return;
        } catch (e) {
          debugPrint('解析用户信息缓存失败: $e');
        }
      }
    }

    _userState = LoadingState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await jwxtService.getUserInfo();
      if (user != null) {
        _user = user;
        _userState = LoadingState.loaded;
        // 保存到缓存
        await _saveUserToCache(user);
      } else {
        // 如果获取详细信息失败，使用基本信息
        _user = jwxtService.currentUser;
        _userState = _user != null ? LoadingState.loaded : LoadingState.error;
        if (_user != null) {
          await _saveUserToCache(_user!);
        }
      }
    } catch (e) {
      _errorMessage = '加载用户信息失败: $e';
      _userState = LoadingState.error;
      debugPrint(_errorMessage);
    }

    notifyListeners();
  }

  /// 后台刷新用户信息（不影响UI状态）
  Future<void> _refreshUserInBackground() async {
    try {
      final user = await jwxtService.getUserInfo();
      if (user != null) {
        _user = user;
        await _saveUserToCache(user);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('后台刷新用户信息失败: $e');
    }
  }

  /// 从缓存加载课程表
  Future<bool> _loadScheduleFromCache() async {
    try {
      final (cacheData, isValid) = await AuthStorage.getScheduleCache();
      if (cacheData != null) {
        final json = jsonDecode(cacheData) as Map<String, dynamic>;
        _schedule = Schedule.fromJson(json);
        _currentWeek = await AuthStorage.calculateCurrentWeek();
        _scheduleState = LoadingState.loaded;
        debugPrint('使用课程表缓存数据 (有效: $isValid)');
        notifyListeners();
        return isValid;
      }
    } catch (e) {
      debugPrint('读取课程表缓存失败: $e');
    }
    return false;
  }

  /// 保存课程表到缓存
  Future<void> _saveScheduleToCache(Schedule schedule) async {
    try {
      final json = jsonEncode(schedule.toJson());
      await AuthStorage.saveScheduleCache(json);
    } catch (e) {
      debugPrint('保存课程表缓存失败: $e');
    }
  }

  /// 加载课程表
  Future<void> loadSchedule({bool forceRefresh = false, String? xnxq}) async {
    if (_scheduleState == LoadingState.loading) return;

    // 非强制刷新且没有指定学期时，先尝试从缓存加载
    if (!forceRefresh && xnxq == null) {
      if (_schedule != null) return; // 内存中已有数据

      // 尝试从持久化缓存加载
      final cacheLoaded = await _loadScheduleFromCache();
      if (cacheLoaded && _schedule != null) {
        _scheduleState = LoadingState.loaded;
        notifyListeners();
        return;
      }
    }

    _scheduleState = LoadingState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final schedule = await jwxtService.getSchedule(xnxq: xnxq);
      if (schedule != null) {
        _schedule = schedule;
        _scheduleState = LoadingState.loaded;

        // 获取当前周次
        _currentWeek = await jwxtService.fetchCurrentWeek();

        // 保存到缓存（仅当是当前学期时）
        if (xnxq == null) {
          await _saveScheduleToCache(schedule);
        }

        // 更新桌面小组件
        await _updateWidget();

        // 安排课程通知
        await _scheduleCourseNotifications();
      } else {
        // 网络获取失败时，尝试使用过期缓存
        final (cacheData, _) = await AuthStorage.getScheduleCache();
        if (cacheData != null) {
          final json = jsonDecode(cacheData) as Map<String, dynamic>;
          _schedule = Schedule.fromJson(json);
          _currentWeek = await AuthStorage.calculateCurrentWeek();
          _scheduleState = LoadingState.loaded;
          debugPrint('使用过期的课程表缓存');
          // 使用缓存数据也更新小组件
          await _updateWidget();
          // 安排课程通知
          await _scheduleCourseNotifications();
        } else {
          _scheduleState = LoadingState.error;
          _errorMessage = '获取课程表失败';
        }
      }
    } catch (e) {
      // 网络异常时尝试使用过期缓存
      final (cacheData, _) = await AuthStorage.getScheduleCache();
      if (cacheData != null) {
        final json = jsonDecode(cacheData) as Map<String, dynamic>;
        _schedule = Schedule.fromJson(json);
        _currentWeek = await AuthStorage.calculateCurrentWeek();
        _scheduleState = LoadingState.loaded;
        debugPrint('网络异常，使用过期的课程表缓存');
        // 安排课程通知
        await _scheduleCourseNotifications();
      } else {
        _errorMessage = '加载课程表失败: $e';
        _scheduleState = LoadingState.error;
        debugPrint(_errorMessage);
      }
    }

    notifyListeners();
  }

  /// 从缓存加载成绩
  Future<bool> _loadGradesFromCache() async {
    try {
      final (cacheData, isValid) = await AuthStorage.getGradesCache();
      if (cacheData != null) {
        final jsonList = jsonDecode(cacheData) as List<dynamic>;
        _grades = jsonList
            .map((e) => SemesterGrades.fromJson(e as Map<String, dynamic>))
            .toList();
        _gradesState = LoadingState.loaded;
        debugPrint('使用成绩缓存数据 (有效: $isValid)');
        notifyListeners();
        return isValid;
      }
    } catch (e) {
      debugPrint('读取成绩缓存失败: $e');
    }
    return false;
  }

  /// 保存成绩到缓存
  Future<void> _saveGradesToCache(List<SemesterGrades> grades) async {
    try {
      final json = jsonEncode(grades.map((e) => e.toJson()).toList());
      await AuthStorage.saveGradesCache(json);
    } catch (e) {
      debugPrint('保存成绩缓存失败: $e');
    }
  }

  /// 加载成绩
  Future<void> loadGrades({bool forceRefresh = false, String? kksj}) async {
    if (_gradesState == LoadingState.loading) return;

    // 非强制刷新且没有指定学期时，先尝试从缓存加载
    if (!forceRefresh && kksj == null) {
      if (_grades != null) return; // 内存中已有数据

      // 尝试从持久化缓存加载
      final cacheLoaded = await _loadGradesFromCache();
      if (cacheLoaded && _grades != null) {
        _gradesState = LoadingState.loaded;
        notifyListeners();
        return;
      }
    }

    _gradesState = LoadingState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // 获取可用学期列表
      if (_semesters.isEmpty) {
        _semesters = await jwxtService.getAvailableSemesters();
      }

      final grades = await jwxtService.getGrades(kksj: kksj);
      if (grades != null) {
        _grades = grades;
        _gradesState = LoadingState.loaded;

        // 保存到缓存（仅当是获取所有学期时）
        if (kksj == null) {
          await _saveGradesToCache(grades);
        }
      } else {
        // 网络获取失败时，尝试使用过期缓存
        final (cacheData, _) = await AuthStorage.getGradesCache();
        if (cacheData != null) {
          final jsonList = jsonDecode(cacheData) as List<dynamic>;
          _grades = jsonList
              .map((e) => SemesterGrades.fromJson(e as Map<String, dynamic>))
              .toList();
          _gradesState = LoadingState.loaded;
          debugPrint('使用过期的成绩缓存');
        } else {
          _gradesState = LoadingState.error;
          _errorMessage = '获取成绩失败';
        }
      }
    } catch (e) {
      // 网络异常时尝试使用过期缓存
      final (cacheData, _) = await AuthStorage.getGradesCache();
      if (cacheData != null) {
        final jsonList = jsonDecode(cacheData) as List<dynamic>;
        _grades = jsonList
            .map((e) => SemesterGrades.fromJson(e as Map<String, dynamic>))
            .toList();
        _gradesState = LoadingState.loaded;
        debugPrint('网络异常，使用过期的成绩缓存');
      } else {
        _errorMessage = '加载成绩失败: $e';
        _gradesState = LoadingState.error;
        debugPrint(_errorMessage);
      }
    }

    notifyListeners();
  }

  /// 刷新所有数据
  Future<void> refreshAll() async {
    await Future.wait([
      loadUserInfo(forceRefresh: true),
      loadSchedule(forceRefresh: true),
      loadGrades(forceRefresh: true),
    ]);
  }

  /// 更新桌面小组件
  Future<void> _updateWidget() async {
    try {
      await WidgetService.updateWidget(
        schedule: _schedule,
        currentWeek: _currentWeek,
      );
    } catch (e) {
      debugPrint('更新桌面小组件失败: $e');
    }
  }

  /// 安排课程通知
  Future<void> _scheduleCourseNotifications() async {
    if (_schedule == null) return;
    try {
      await NotificationService().scheduleCourseNotifications(
        schedule: _schedule!,
        currentWeek: _currentWeek,
      );
    } catch (e) {
      debugPrint('安排课程通知失败: $e');
    }
  }

  /// 获取今日课程
  List<Course> getTodayCourses() {
    if (_schedule == null) return [];

    final now = DateTime.now();
    final weekday = now.weekday;
    return _schedule!.getCoursesForDay(_currentWeek, weekday);
  }

  /// 获取指定日期的课程
  List<Course> getCoursesForDay(int week, int weekday) {
    if (_schedule == null) return [];
    return _schedule!.getCoursesForDay(week, weekday);
  }

  /// 获取最新学期成绩
  SemesterGrades? getLatestSemesterGrades() {
    if (_grades == null || _grades!.isEmpty) return null;
    return _grades!.first;
  }

  /// 获取指定学期成绩
  SemesterGrades? getSemesterGrades(String semester) {
    if (_grades == null) return null;
    return _grades!.firstWhere(
      (g) => g.semester == semester,
      orElse: () => _grades!.first,
    );
  }

  /// 计算总平均绩点
  double? calculateOverallGpa() {
    if (_grades == null || _grades!.isEmpty) return null;

    var totalPoints = 0.0;
    var totalCredits = 0.0;

    for (final semester in _grades!) {
      for (final grade in semester.grades) {
        if (grade.gpa != null) {
          totalPoints += grade.gpa! * grade.credit;
          totalCredits += grade.credit;
        }
      }
    }

    return totalCredits > 0 ? totalPoints / totalCredits : null;
  }

  /// 计算总学分
  double calculateTotalCredits() {
    if (_grades == null) return 0;

    var total = 0.0;
    for (final semester in _grades!) {
      total += semester.earnedCredits;
    }
    return total;
  }

  /// 清除所有缓存数据
  void clearCache() {
    _user = null;
    _schedule = null;
    _grades = null;
    _semesters = [];
    _currentWeek = 1;
    _userState = LoadingState.idle;
    _scheduleState = LoadingState.idle;
    _gradesState = LoadingState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clearCache();
    super.dispose();
  }
}
