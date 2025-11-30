/// 学习通服务
/// 处理学习通登录和未交作业查询
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/xxt_work.dart';
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
    final list = works.map((w) => {
      'name': w.name,
      'status': w.status,
      'remainingTime': w.remainingTime,
      'courseName': w.courseName,
    }).toList();
    return jsonEncode(list);
  }

  /// 从缓存字符串解析作业列表
  List<XxtWork> _parseWorksFromCache(String cacheData) {
    final list = jsonDecode(cacheData) as List;
    return list.map((item) => XxtWork.fromParsed(
      name: item['name'] ?? '',
      status: item['status'] ?? '未提交',
      remainingTime: item['remainingTime'] ?? '未知',
      courseName: item['courseName'],
    )).toList();
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
}
