/// 学习通服务
/// 处理学习通登录、未交作业查询和进行中活动查询
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/xxt_work.dart';
import '../models/xxt_activity.dart';
import 'account_manager.dart';
import 'auth_storage.dart';

/// 学习通服务
class XxtService {
  static final XxtService _instance = XxtService._internal();
  factory XxtService() => _instance;
  XxtService._internal();

  final Dio _dio = Dio();

  /// 当前登录的 Cookie
  String? _cookie;

  /// 登录 URL
  static const String _loginUrl = 'https://passport2.chaoxing.com/fanyalogin';

  /// 作业列表 URL
  static const String _workListUrl =
      'https://mooc1-api.chaoxing.com/work/stu-work';

  /// 登录学习通
  Future<bool> login(String username, String password) async {
    try {
      // 使用 URL 编码的字符串
      final formData =
          'fid=-1&uname=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&refer=${Uri.encodeComponent('http://i.mooc.chaoxing.com')}';

      final response = await _dio.post(
        _loginUrl,
        data: formData,
        options: Options(
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36',
          },
          responseType: ResponseType.json, // 明确指定响应类型
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      debugPrint('学习通登录响应: ${response.data}');
      debugPrint('学习通登录响应类型: ${response.data.runtimeType}');
      debugPrint('学习通响应 Cookie: ${response.headers['set-cookie']}');

      // 解析响应数据
      dynamic result = response.data;

      // 如果是字符串，尝试解析为 JSON
      if (result is String) {
        try {
          result = await _parseJson(result);
        } catch (e) {
          debugPrint('JSON 解析失败: $e');
        }
      }

      // 检查登录状态
      bool loginSuccess = false;
      if (result is Map) {
        loginSuccess = result['status'] == true;
      }

      if (loginSuccess) {
        // 提取 Cookie
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _cookie = _parseCookies(cookies);
          debugPrint('学习通登录成功，Cookie: $_cookie');
          return true;
        } else {
          debugPrint('学习通登录成功但未获取到 Cookie');
          // 即使没有新 Cookie，登录也可能成功（使用现有会话）
          return true;
        }
      }

      final errorMsg = result is Map
          ? (result['mes'] ?? result['msg'] ?? '未知错误')
          : '响应格式错误';
      debugPrint('学习通登录失败: $errorMsg');
      return false;
    } catch (e, stackTrace) {
      debugPrint('学习通登录异常: $e');
      debugPrint('堆栈: $stackTrace');
      return false;
    }
  }

  /// 解析 JSON 字符串
  dynamic _parseJson(String jsonStr) {
    return jsonDecode(jsonStr);
  }

  /// 解析 Set-Cookie 头
  String _parseCookies(List<String> setCookieHeaders) {
    final cookies = <String>[];
    for (final header in setCookieHeaders) {
      // 提取 cookie 名称和值（忽略其他属性如 path, expires 等）
      final cookiePart = header.split(';').first.trim();
      if (cookiePart.contains('=')) {
        cookies.add(cookiePart);
      }
    }
    return cookies.join('; ');
  }

  /// 获取作业列表页面 HTML
  Future<String?> _getWorkListHtml() async {
    if (_cookie == null || _cookie!.isEmpty) {
      return null;
    }

    try {
      final response = await _dio.get(
        _workListUrl,
        options: Options(
          headers: {
            'Cookie': _cookie,
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Host': 'mooc1-api.chaoxing.com',
          },
        ),
      );

      return response.data?.toString();
    } catch (e) {
      debugPrint('获取作业列表失败: $e');
      return null;
    }
  }

  /// 解析作业列表 HTML
  List<XxtWork> _parseWorkList(String html) {
    final works = <XxtWork>[];

    try {
      final document = html_parser.parse(html);

      // 查找所有元素的 aria-label 属性
      final allElements = document.querySelectorAll('[aria-label]');

      for (final element in allElements) {
        final ariaLabel = element.attributes['aria-label'] ?? '';

        // 检查是否包含未提交的作业
        if (!ariaLabel.contains('作业状态未提交')) {
          continue;
        }

        // 解析作业名称
        String workName = '';
        final nameMatch = RegExp(r'作业名称(.+?)作业状态').firstMatch(ariaLabel);
        if (nameMatch != null) {
          workName = nameMatch.group(1) ?? '';
        }

        if (workName.isEmpty) continue;

        // 解析作业状态
        const workStatus = '未提交';

        // 解析所属课程
        String? courseName;
        final courseMatch = RegExp(
          r'所属课程(.+?)(?:剩余时间|$)',
        ).firstMatch(ariaLabel);
        if (courseMatch != null) {
          courseName = courseMatch.group(1)?.trim();
        }

        // 解析剩余时间
        String remainingTime = '未设置截止时间';
        if (ariaLabel.contains('时间剩余')) {
          // 匹配 "时间剩余" 后面的内容直到引号结束
          final timeMatch = RegExp(r'时间剩余(.+?)(?:"|$)').firstMatch(ariaLabel);
          if (timeMatch != null) {
            remainingTime =
                timeMatch.group(1)?.replaceAll('"', '').trim() ?? remainingTime;
          }
        }

        works.add(
          XxtWork.fromParsed(
            name: workName,
            status: workStatus,
            remainingTime: remainingTime,
            courseName: courseName,
          ),
        );
      }
    } catch (e) {
      debugPrint('解析作业列表失败: $e');
    }

    return works;
  }

  /// 检查页面是否为作业列表页面（而非登录页面）
  bool _isWorkListPage(String html) {
    final document = html_parser.parse(html);
    final title = document.querySelector('title')?.text ?? '';
    return title.contains('作业列表');
  }

  /// 获取未交作业（使用账号管理器中的学习通账号）
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<XxtWorkResult> getUnfinishedWorks({bool forceRefresh = false}) async {
    // 获取当前活跃账号的学习通配置
    final accountManager = AccountManager();

    // 确保账号管理器已初始化
    if (!accountManager.isInitialized) {
      await accountManager.init();
    }

    final activeAccount = accountManager.activeAccount;

    debugPrint('XxtService: activeAccount = $activeAccount');
    debugPrint('XxtService: hasXuexitong = ${activeAccount?.hasXuexitong}');
    debugPrint('XxtService: xuexitong = ${activeAccount?.xuexitong}');

    if (activeAccount == null) {
      return XxtWorkResult.failure('请先登录教务系统账号', needLogin: true);
    }

    if (!activeAccount.hasXuexitong) {
      return XxtWorkResult.failure('请先配置学习通账号', needLogin: true);
    }

    // 尝试从缓存加载（如果不是强制刷新）
    if (!forceRefresh) {
      final (cacheData, isValid) = await AuthStorage.getWorksCache();
      if (cacheData != null && isValid) {
        try {
          final works = _parseWorksFromCache(cacheData);
          debugPrint('从缓存加载作业列表: ${works.length} 项');
          return XxtWorkResult.success(works);
        } catch (e) {
          debugPrint('解析作业缓存失败: $e');
        }
      }
    }

    // 从网络获取
    final result = await getUnfinishedWorksWithCredentials(
      activeAccount.xuexitong!.username,
      activeAccount.xuexitong!.password,
    );

    // 如果成功，保存到缓存
    if (result.success) {
      try {
        final cacheData = _serializeWorksToCache(result.works);
        await AuthStorage.saveWorksCache(cacheData);
        debugPrint('作业列表已缓存: ${result.works.length} 项');
      } catch (e) {
        debugPrint('保存作业缓存失败: $e');
      }
    }

    return result;
  }

  /// 将作业列表序列化为缓存字符串
  String _serializeWorksToCache(List<XxtWork> works) {
    final list = works
        .map(
          (w) => {
            'name': w.name,
            'status': w.status,
            'remainingTime': w.remainingTime,
            'courseName': w.courseName,
          },
        )
        .toList();
    return jsonEncode(list);
  }

  /// 从缓存字符串解析作业列表
  List<XxtWork> _parseWorksFromCache(String cacheData) {
    final list = jsonDecode(cacheData) as List;
    return list
        .map(
          (item) => XxtWork.fromParsed(
            name: item['name'] ?? '',
            status: item['status'] ?? '未提交',
            remainingTime: item['remainingTime'] ?? '未知',
            courseName: item['courseName'],
          ),
        )
        .toList();
  }

  /// 使用指定的账号密码获取未交作业
  Future<XxtWorkResult> getUnfinishedWorksWithCredentials(
    String username,
    String password,
  ) async {
    try {
      // 先尝试获取作业列表（如果有缓存的 Cookie）
      String? html = await _getWorkListHtml();

      // 如果没有 Cookie 或页面不是作业列表，尝试登录
      if (html == null || !_isWorkListPage(html)) {
        // 尝试登录
        final loginSuccess = await login(username, password);
        if (!loginSuccess) {
          return XxtWorkResult.failure('学习通登录失败，请检查账号密码', needLogin: true);
        }

        // 重新获取作业列表
        html = await _getWorkListHtml();
        if (html == null || !_isWorkListPage(html)) {
          return XxtWorkResult.failure('获取作业列表失败');
        }
      }

      // 解析作业列表
      final works = _parseWorkList(html);
      return XxtWorkResult.success(works);
    } catch (e) {
      debugPrint('获取未交作业异常: $e');
      return XxtWorkResult.failure('获取失败: $e');
    }
  }

  /// 清除登录状态
  void clearSession() {
    _cookie = null;
  }

  // ========== 进行中活动相关方法 ==========

  /// 课程列表 URL
  static const String _courseListUrl =
      'http://mooc1-1.chaoxing.com/visit/courselistdata';

  /// 活动检查 URL 模板
  static const String _activityCheckUrl =
      'https://mobilelearn.chaoxing.com/widget/pcpick/stu/index';

  /// 获取课程列表（使用 HTML 解析）
  Future<List<Map<String, String>>> _getCourseList() async {
    if (_cookie == null || _cookie!.isEmpty) {
      return [];
    }

    try {
      final response = await _dio.post(
        _courseListUrl,
        data: 'courseType=1&courseFolderId=0&courseFolderSize=0',
        options: Options(
          headers: {
            'Cookie': _cookie,
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );

      final html = response.data?.toString();
      if (html == null || html.isEmpty) return [];

      final document = html_parser.parse(html);
      final courses = <Map<String, String>>[];

      for (final li in document.querySelectorAll('li.course.clearfix')) {
        // 跳过已结课的课程
        final reviewDiv = li.querySelector('.course-cover .ui-open-review');
        if (reviewDiv != null && reviewDiv.text.contains('已开启结课模式')) {
          continue;
        }

        final courseId = li.attributes['courseid'];
        final classId = li.attributes['clazzid'];
        final nameSpan = li.querySelector('span.course-name');

        if (courseId != null && classId != null && nameSpan != null) {
          courses.add({
            'name': nameSpan.text.trim(),
            'courseId': courseId,
            'classId': classId,
          });
        }
      }

      debugPrint('获取到 ${courses.length} 门课程');
      return courses;
    } catch (e) {
      debugPrint('获取课程列表失败: $e');
      return [];
    }
  }

  /// 获取活动结束时间（通过 API）
  Future<DateTime?> _getActivityEndTime(String activeId) async {
    if (_cookie == null || _cookie!.isEmpty) return null;

    try {
      final url =
          'https://mobilelearn.chaoxing.com/v2/apis/active/getActiveEndtime'
          '?DB_STRATEGY=PRIMARY_KEY&STRATEGY_PARA=activeId&activeId=$activeId';

      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Cookie': _cookie,
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      if (response.data is Map) {
        final data = response.data as Map;
        final innerData = data['data'];
        if (innerData is Map && innerData['endtime'] != null) {
          final endtimeMs = innerData['endtime'];
          if (endtimeMs is int && endtimeMs > 0) {
            return DateTime.fromMillisecondsSinceEpoch(endtimeMs);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('获取活动结束时间失败: activeId=$activeId, $e');
      return null;
    }
  }

  /// 检查活动状态（签到/练习是否已完成）
  Future<XxtActivityStatus> _checkActivityStatus(
    String activeId,
    String activeType,
  ) async {
    if (_cookie == null || _cookie!.isEmpty) return XxtActivityStatus.unknown;

    try {
      String url;

      // activeType: 2=签到, 42=随堂练习
      if (activeType == '2') {
        // 签到状态 - 使用 preSign API
        url =
            'https://mobilelearn.chaoxing.com/newsign/preSign?general=1&sys=1&ls=1&appType=15&isTeacherViewOpen=0'
            '&activeId=$activeId';

        final response = await _dio.get(
          url,
          options: Options(
            headers: {
              'Cookie': _cookie,
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            receiveTimeout: const Duration(seconds: 5),
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );

        final body = response.data?.toString() ?? '';
        // 检查是否已签到：如果页面不包含签到按钮，说明已签到
        if (body.contains('签到成功') ||
            (!body.contains('请先拍照') &&
                !body.contains('onclick="send()"') &&
                !body.contains('class="qd_btn"'))) {
          return XxtActivityStatus.completed;
        }
        return XxtActivityStatus.pending;
      } else if (activeType == '42') {
        // 练习状态
        url =
            'https://mobilelearn.chaoxing.com/v2/apis/studentQuestion/getAnswerResult?activeId=$activeId';

        final response = await _dio.get(
          url,
          options: Options(
            headers: {
              'Cookie': _cookie,
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            receiveTimeout: const Duration(seconds: 5),
          ),
        );

        Map<String, dynamic>? data;
        if (response.data is Map) {
          data = response.data as Map<String, dynamic>;
        } else if (response.data is String) {
          data = jsonDecode(response.data as String) as Map<String, dynamic>;
        }

        if (data != null) {
          final innerData = data['data'];
          if (innerData is Map) {
            // 使用 isAnswered 字段判断是否已提交
            final isAnswered = innerData['isAnswered'];
            debugPrint('练习 isAnswered: $isAnswered');
            if (isAnswered == true) {
              return XxtActivityStatus.completed;
            }
          }
        }
        return XxtActivityStatus.pending;
      }

      return XxtActivityStatus.unknown;
    } catch (e) {
      debugPrint('检查活动状态失败: activeId=$activeId, $e');
      return XxtActivityStatus.unknown;
    }
  }

  /// 从 onclick 属性提取 activeId 和 activeType
  ({String? activeId, String? activeType}) _parseActiveDetail(String? onclick) {
    if (onclick == null || onclick.isEmpty) {
      return (activeId: null, activeType: null);
    }

    final match = RegExp(r'activeDetail\((\d+),(\d+)').firstMatch(onclick);
    if (match != null) {
      return (activeId: match.group(1), activeType: match.group(2));
    }
    return (activeId: null, activeType: null);
  }

  /// 检查单个课程的进行中活动（使用 HTML 解析）
  Future<XxtCourseActivities?> _checkCourseActivities(
    Map<String, String> course,
  ) async {
    if (_cookie == null || _cookie!.isEmpty) return null;

    try {
      final courseId = course['courseId'] ?? course['courseid'];
      final classId = course['classId'] ?? course['clazzid'];

      final url = '$_activityCheckUrl?courseId=$courseId&jclassId=$classId';

      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Cookie': _cookie,
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final html = response.data?.toString();
      if (html == null || html.isEmpty) {
        return null;
      }

      final document = html_parser.parse(html);
      final activities = <XxtActivity>[];

      // 检查课程是否已结课
      final notOpenTip = document.querySelector('.not-open-tip');
      if (notOpenTip != null) {
        final tipText = notOpenTip.text.trim();
        if (tipText.contains('课程已结束') || tipText.contains('结课')) {
          debugPrint('跳过已结课课程: ${course['name']}');
          return null;
        }
      }

      // 查找进行中活动数量
      int ongoingCount = 0;
      bool foundOngoingTab = false;

      for (final anchor in document.querySelectorAll('a')) {
        final text = anchor.text.trim();
        if (text.contains('进行中')) {
          foundOngoingTab = true;
          final countMatch = RegExp(r'\((\d+)\)').firstMatch(text);
          if (countMatch != null) {
            ongoingCount = int.tryParse(countMatch.group(1) ?? '0') ?? 0;
          }
          break;
        }
      }

      if (!foundOngoingTab || ongoingCount == 0) {
        return null;
      }

      // 解析活动详情
      final startList = document.querySelector('div#startList');
      if (startList != null) {
        for (final mct in startList.querySelectorAll('div.Mct')) {
          final dd = mct.querySelector('dd');
          final center = mct.querySelector('div.Mct_center');
          final anchor = center?.querySelector('a');

          String? onclick = mct.attributes['onclick'];
          if (onclick == null || onclick.isEmpty) {
            onclick = center?.attributes['onclick'];
          }
          if (onclick == null || onclick.isEmpty) {
            onclick = anchor?.attributes['onclick'];
          }
          if (onclick == null || onclick.isEmpty) {
            final mctHtml = mct.outerHtml;
            final activeMatch = RegExp(
              r'activeDetail\((\d+),(\d+)',
            ).firstMatch(mctHtml);
            if (activeMatch != null) {
              onclick =
                  'activeDetail(${activeMatch.group(1)},${activeMatch.group(2)},null)';
            }
          }

          final (:activeId, :activeType) = _parseActiveDetail(onclick);
          final typeName = dd?.text.trim() ?? '未知';
          final activityName = anchor?.text.trim() ?? '未知活动';

          if (activityName.isNotEmpty && activityName != '未知活动') {
            activities.add(
              XxtActivity.fromParsed(
                typeName: typeName,
                name: activityName,
                activeId: activeId,
                activeType: activeType,
              ),
            );
          }
        }
      }

      // 备用策略：检查所有 Mct 元素
      if (activities.isEmpty) {
        for (final mct in document.querySelectorAll('div.Mct')) {
          final dd = mct.querySelector('dd');
          final center = mct.querySelector('div.Mct_center');
          final anchor = center?.querySelector('a');

          String? onclick = mct.attributes['onclick'];
          if (onclick == null || onclick.isEmpty) {
            onclick = center?.attributes['onclick'];
          }
          if (onclick == null || onclick.isEmpty) {
            onclick = anchor?.attributes['onclick'];
          }
          if (onclick == null || onclick.isEmpty) {
            final mctHtml = mct.outerHtml;
            final activeMatch = RegExp(
              r'activeDetail\((\d+),(\d+)',
            ).firstMatch(mctHtml);
            if (activeMatch != null) {
              onclick =
                  'activeDetail(${activeMatch.group(1)},${activeMatch.group(2)},null)';
            }
          }

          final (:activeId, :activeType) = _parseActiveDetail(onclick);
          final typeName = dd?.text.trim() ?? '未知';
          final activityName = anchor?.text.trim() ?? '未知活动';

          if (activityName.isNotEmpty && activityName != '未知活动') {
            activities.add(
              XxtActivity.fromParsed(
                typeName: typeName,
                name: activityName,
                activeId: activeId,
                activeType: activeType,
              ),
            );
          }
        }
      }

      if (activities.isEmpty) {
        return null;
      }

      // 获取结束时间和状态
      final enrichedActivities = <XxtActivity>[];

      for (final activity in activities) {
        if (activity.activeId != null) {
          final futures = await Future.wait([
            _getActivityEndTime(activity.activeId!),
            if (activity.activeType != null)
              _checkActivityStatus(activity.activeId!, activity.activeType!)
            else
              Future.value(XxtActivityStatus.unknown),
          ]);

          final endTime = futures[0] as DateTime?;
          final status = futures.length > 1
              ? futures[1] as XxtActivityStatus
              : XxtActivityStatus.unknown;

          final enrichedActivity = activity.copyWith(
            endTime: endTime,
            status: status,
          );

          // 过滤掉已完成和已过期的活动
          if (!enrichedActivity.status.isCompleted &&
              !enrichedActivity.isExpired) {
            enrichedActivities.add(enrichedActivity);
          } else {
            debugPrint(
              '  跳过活动: ${activity.name} '
              '(状态=${enrichedActivity.status.displayName}, '
              '已过期=${enrichedActivity.isExpired})',
            );
          }
        } else {
          enrichedActivities.add(activity);
        }
      }

      if (enrichedActivities.isEmpty) {
        return null;
      }

      debugPrint('发现活动: ${course['name']} - ${enrichedActivities.length} 个');
      for (final act in enrichedActivities) {
        debugPrint(
          '  - [${act.type.displayName}] ${act.name} '
          '(${act.status.displayName}, ${act.remainingTimeText})',
        );
      }

      return XxtCourseActivities(
        courseName: course['name'] ?? '未知课程',
        courseId: courseId ?? '',
        classId: classId ?? '',
        activities: enrichedActivities,
      );
    } catch (e) {
      debugPrint('检查课程活动失败: ${course['name']}, $e');
      return null;
    }
  }

  /// 获取进行中的活动（使用账号管理器中的学习通账号）
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<XxtActivityResult> getOngoingActivities({
    bool forceRefresh = false,
  }) async {
    // 获取当前活跃账号的学习通配置
    final accountManager = AccountManager();

    // 确保账号管理器已初始化
    if (!accountManager.isInitialized) {
      await accountManager.init();
    }

    final activeAccount = accountManager.activeAccount;

    if (activeAccount == null) {
      return XxtActivityResult.failure('请先登录教务系统账号', needLogin: true);
    }

    if (!activeAccount.hasXuexitong) {
      return XxtActivityResult.failure('请先配置学习通账号', needLogin: true);
    }

    // 尝试从缓存加载（如果不是强制刷新）
    if (!forceRefresh) {
      final (cacheData, isValid) = await AuthStorage.getActivitiesCache();
      if (cacheData != null && isValid) {
        try {
          final activities = _parseActivitiesFromCache(cacheData);
          debugPrint('从缓存加载活动列表: ${activities.length} 门课程');
          return XxtActivityResult.success(activities);
        } catch (e) {
          debugPrint('解析活动缓存失败: $e');
        }
      }
    }

    // 从网络获取
    final result = await getOngoingActivitiesWithCredentials(
      activeAccount.xuexitong!.username,
      activeAccount.xuexitong!.password,
    );

    // 如果成功，保存到缓存
    if (result.success) {
      try {
        final cacheData = _serializeActivitiesToCache(result.courseActivities);
        await AuthStorage.saveActivitiesCache(cacheData);
        debugPrint('活动列表已缓存: ${result.totalActivityCount} 项');
      } catch (e) {
        debugPrint('保存活动缓存失败: $e');
      }
    }

    return result;
  }

  /// 使用指定的账号密码获取进行中活动
  Future<XxtActivityResult> getOngoingActivitiesWithCredentials(
    String username,
    String password,
  ) async {
    try {
      // 确保已登录
      if (_cookie == null || _cookie!.isEmpty) {
        debugPrint('活动获取: Cookie 为空，尝试登录');
        final loginSuccess = await login(username, password);
        if (!loginSuccess) {
          return XxtActivityResult.failure('学习通登录失败，请检查账号密码', needLogin: true);
        }
      }

      // 获取课程列表
      var courses = await _getCourseList();
      debugPrint('活动获取: 首次获取课程 ${courses.length} 门');

      if (courses.isEmpty) {
        // 可能 Cookie 过期，尝试重新登录
        debugPrint('活动获取: 课程列表为空，尝试重新登录');
        final loginSuccess = await login(username, password);
        if (!loginSuccess) {
          return XxtActivityResult.failure('学习通登录失败', needLogin: true);
        }

        courses = await _getCourseList();
        debugPrint('活动获取: 重新登录后获取课程 ${courses.length} 门');
        if (courses.isEmpty) {
          return XxtActivityResult.failure('获取课程列表失败，请稍后重试');
        }
      }

      // 并发检查所有课程的活动
      final results = <XxtCourseActivities>[];

      // 使用 Future.wait 并发请求，但限制并发数
      const batchSize = 10;
      for (var i = 0; i < courses.length; i += batchSize) {
        final batch = courses.skip(i).take(batchSize).toList();
        final batchResults = await Future.wait(
          batch.map((c) => _checkCourseActivities(c)),
        );

        for (final result in batchResults) {
          if (result != null) {
            results.add(result);
          }
        }
      }

      debugPrint('活动获取: 共发现 ${results.length} 门课程有活动');
      return XxtActivityResult.success(results);
    } catch (e, stackTrace) {
      debugPrint('获取进行中活动异常: $e');
      debugPrint('堆栈: $stackTrace');
      return XxtActivityResult.failure('获取失败: $e');
    }
  }

  /// 将活动列表序列化为缓存字符串
  String _serializeActivitiesToCache(List<XxtCourseActivities> activities) {
    final list = activities.map((c) => c.toJson()).toList();
    return jsonEncode(list);
  }

  /// 从缓存字符串解析活动列表
  List<XxtCourseActivities> _parseActivitiesFromCache(String cacheData) {
    final list = jsonDecode(cacheData) as List;
    return list
        .map(
          (item) => XxtCourseActivities.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }
}
