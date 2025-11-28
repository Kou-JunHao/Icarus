/// 教务系统 API 服务
///
/// 处理与强智教务系统的所有网络交互
library;

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/jwxt_crypto.dart';
import '../utils/captcha_ocr.dart';

/// 登录结果
sealed class LoginResult {
  const LoginResult();
}

/// 登录成功
class LoginSuccess extends LoginResult {
  final User user;
  const LoginSuccess(this.user);
}

/// 登录失败
class LoginFailure extends LoginResult {
  final String message;
  const LoginFailure(this.message);
}

/// 需要验证码（OCR识别失败时）
class LoginNeedCaptcha extends LoginResult {
  final Uint8List captchaImage;
  const LoginNeedCaptcha(this.captchaImage);
}

/// 教务系统服务
class JwxtService {
  /// 教务系统基础 URL
  final String baseUrl;

  /// HTTP 客户端
  late final Dio _dio;

  /// Cookie 管理器
  final CookieJar _cookieJar = CookieJar();

  /// 缓存的加密参数
  String? _cachedScode;
  String? _cachedSxh;

  /// 是否已登录
  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  /// 当前用户
  User? _currentUser;
  User? get currentUser => _currentUser;

  /// 自动重登回调
  Future<bool> Function()? _autoReloginCallback;

  /// 设置自动重登回调
  void setAutoReloginCallback(Future<bool> Function()? callback) {
    _autoReloginCallback = callback;
  }

  JwxtService({required this.baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ),
    );

    // 添加 Cookie 管理器
    _dio.interceptors.add(CookieManager(_cookieJar));

    // 添加日志拦截器（调试用）
    // _dio.interceptors.add(LogInterceptor(
    //   requestBody: true,
    //   responseBody: true,
    // ));
  }

  /// 检查会话是否有效（检测登录页面重定向）
  bool _isSessionExpired(Response response) {
    // 检查是否被重定向到登录页面
    final location = response.headers.value('location') ?? '';
    if (location.contains('Logon') || location.contains('login')) {
      return true;
    }

    // 检查响应内容是否包含登录页面特征
    final body = response.data?.toString() ?? '';
    if (body.contains('请登录') ||
        body.contains('登录页面') ||
        body.contains('userAccount') && body.contains('userPassword') ||
        body.contains('Logon.do?method=logon')) {
      return true;
    }

    return false;
  }

  /// 尝试自动重新登录
  Future<bool> _tryAutoRelogin() async {
    if (_autoReloginCallback == null) {
      print('未设置自动重登回调');
      return false;
    }

    print('会话已过期，尝试自动重新登录...');
    _isLoggedIn = false;

    try {
      final success = await _autoReloginCallback!();
      if (success) {
        print('自动重新登录成功');
        return true;
      }
    } catch (e) {
      print('自动重新登录失败: $e');
    }

    return false;
  }

  /// 初始化会话，获取 JSESSIONID
  Future<void> _initSession() async {
    await _dio.get('/');
  }

  /// 获取加密参数
  Future<bool> _fetchEncryptParams() async {
    try {
      final response = await _dio.post('/Logon.do?method=logon&flag=sess');
      final data = response.data.toString();

      if (data == 'no' || !data.contains('#')) {
        return false;
      }

      final params = JwxtCrypto.parseEncryptParams(data);
      if (params == null) {
        return false;
      }

      _cachedScode = params.scode;
      _cachedSxh = params.sxh;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取验证码图片
  Future<Uint8List?> getCaptchaImage() async {
    try {
      // 确保会话已初始化
      await _initSession();

      // 获取加密参数
      if (!await _fetchEncryptParams()) {
        return null;
      }

      // 获取验证码图片
      final response = await _dio.get(
        '/verifycode.servlet',
        options: Options(responseType: ResponseType.bytes),
      );

      return Uint8List.fromList(response.data);
    } catch (e) {
      return null;
    }
  }

  /// 刷新验证码
  Future<Uint8List?> refreshCaptcha() async {
    try {
      // 重新获取加密参数
      if (!await _fetchEncryptParams()) {
        return null;
      }

      // 获取新验证码
      final response = await _dio.get(
        '/verifycode.servlet',
        options: Options(responseType: ResponseType.bytes),
      );

      return Uint8List.fromList(response.data);
    } catch (e) {
      return null;
    }
  }

  /// 自动登录（使用OCR识别验证码）
  ///
  /// [username] 学号
  /// [password] 密码
  /// [maxRetry] 最大重试次数（验证码识别可能失败）
  /// [onProgress] 进度回调
  Future<LoginResult> autoLogin({
    required String username,
    required String password,
    int maxRetry = 10,
    void Function(String message)? onProgress,
  }) async {
    for (int attempt = 1; attempt <= maxRetry; attempt++) {
      onProgress?.call('正在尝试登录 ($attempt/$maxRetry)...');

      try {
        // 1. 初始化会话
        await _initSession();

        // 2. 获取加密参数
        if (!await _fetchEncryptParams()) {
          continue;
        }

        // 3. 获取验证码图片
        final captchaImage = await _getCaptchaImageBytes();
        if (captchaImage == null) {
          continue;
        }

        // 4. OCR识别验证码
        onProgress?.call('正在识别验证码...');
        final captcha = await CaptchaOcr.recognize(captchaImage);
        if (captcha == null || captcha.length < 4) {
          print('验证码识别失败，重试中...');
          continue;
        }

        // 5. 尝试登录
        final result = await login(
          username: username,
          password: password,
          captcha: captcha,
        );

        // 6. 检查结果
        if (result is LoginSuccess) {
          return result;
        }

        if (result is LoginFailure) {
          final msg = result.message;
          // 验证码错误，继续重试
          if (msg.contains('验证码')) {
            print('验证码错误，重试中...');
            continue;
          }
          // 其他错误，直接返回
          return result;
        }
      } catch (e) {
        print('登录尝试 $attempt 失败: $e');
        continue;
      }
    }

    return const LoginFailure('验证码识别失败，请手动输入');
  }

  /// 获取验证码图片字节数据（内部使用）
  Future<Uint8List?> _getCaptchaImageBytes() async {
    try {
      final response = await _dio.get(
        '/verifycode.servlet',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data);
    } catch (e) {
      return null;
    }
  }

  /// 执行登录
  ///
  /// [username] 学号
  /// [password] 密码
  /// [captcha] 验证码
  Future<LoginResult> login({
    required String username,
    required String password,
    required String captcha,
  }) async {
    try {
      // 确保有加密参数
      if (_cachedScode == null || _cachedSxh == null) {
        if (!await _fetchEncryptParams()) {
          return const LoginFailure('无法获取加密参数，请重试');
        }
      }

      // 加密密码
      final encoded = JwxtCrypto.encode(
        username: username,
        password: password,
        scode: _cachedScode!,
        sxh: _cachedSxh!,
      );

      // 打印调试信息
      print('=== 登录调试信息 ===');
      print('username: $username');
      print('scode: $_cachedScode');
      print('sxh: $_cachedSxh');
      print('encoded: $encoded');
      print('captcha: $captcha');

      // 构造表单数据
      final formData =
          'userAccount=${Uri.encodeComponent(username)}'
          '&userPassword='
          '&encoded=${Uri.encodeComponent(encoded)}'
          '&RANDOMCODE=${Uri.encodeComponent(captcha)}';

      // 提交登录请求，不跟随重定向以便检查 Location
      final response = await _dio.post(
        '/Logon.do?method=logon',
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      print('response status: ${response.statusCode}');
      print('response url: ${response.realUri}');
      print('response headers: ${response.headers.map}');

      // 检查 302 重定向（登录成功）
      if (response.statusCode == 302) {
        final location = response.headers.value('location') ?? '';
        print('location header: $location');

        // 登录成功会重定向到 jsxsd 相关页面
        if (location.contains('jsxsd') ||
            location.contains('LoginToXk') ||
            location.contains('main') ||
            location.contains('xsMain') ||
            location.contains('index') ||
            location.contains('framework')) {
          // 需要跟随重定向完成登录
          // 注意：重定向 URL 可能是 http，需要转换为相对路径或使用相同协议
          String redirectUrl = location;
          if (location.startsWith('http://') ||
              location.startsWith('https://')) {
            // 提取路径部分，使用 baseUrl 的协议
            final uri = Uri.parse(location);
            redirectUrl =
                uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');
          }
          print('跟随重定向: $redirectUrl');

          // 跟随重定向，可能需要多次
          try {
            var redirectResponse = await _dio.get(
              redirectUrl,
              options: Options(
                followRedirects: false,
                validateStatus: (status) => status != null && status < 500,
              ),
            );

            // 继续跟随重定向直到不再是 302
            int maxRedirects = 5;
            while (redirectResponse.statusCode == 302 && maxRedirects > 0) {
              final nextLocation =
                  redirectResponse.headers.value('location') ?? '';
              if (nextLocation.isEmpty) break;

              String nextUrl = nextLocation;
              if (nextLocation.startsWith('http://') ||
                  nextLocation.startsWith('https://')) {
                final uri = Uri.parse(nextLocation);
                nextUrl =
                    uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');
              }
              print('继续重定向: $nextUrl');

              redirectResponse = await _dio.get(
                nextUrl,
                options: Options(
                  followRedirects: false,
                  validateStatus: (status) => status != null && status < 500,
                ),
              );
              maxRedirects--;
            }

            print('最终页面状态: ${redirectResponse.statusCode}');
          } catch (e) {
            print('重定向过程出错: $e');
          }

          _isLoggedIn = true;
          _currentUser = User(studentId: username);
          _cachedScode = null;
          _cachedSxh = null;
          print('登录成功！');
          return LoginSuccess(_currentUser!);
        }
      }

      // 检查最终 URL 是否包含 main（登录成功会重定向到主页）
      final finalUrl = response.realUri.toString().toLowerCase();
      if (finalUrl.contains('main') || finalUrl.contains('xsmain')) {
        _isLoggedIn = true;
        _currentUser = User(studentId: username);
        _cachedScode = null;
        _cachedSxh = null;
        return LoginSuccess(_currentUser!);
      }

      // 登录失败，解析错误信息
      final html = response.data.toString();
      print('response html length: ${html.length}');
      final errorMessage = _extractErrorMessage(html);
      print('error message: $errorMessage');

      // 清除加密参数，下次需要重新获取
      _cachedScode = null;
      _cachedSxh = null;

      return LoginFailure(errorMessage);
    } on DioException catch (e) {
      print('DioException: ${e.type} - ${e.message}');
      print('Response: ${e.response?.statusCode} - ${e.response?.realUri}');

      // 处理 302 重定向
      if (e.response?.statusCode == 302) {
        final location = e.response?.headers.value('location') ?? '';
        if (location.contains('main') || location.contains('xsMain')) {
          _isLoggedIn = true;
          _currentUser = User(studentId: username);
          _cachedScode = null;
          _cachedSxh = null;
          return LoginSuccess(_currentUser!);
        }
      }

      return LoginFailure('网络错误: ${e.message}');
    } catch (e) {
      print('Exception: $e');
      return LoginFailure('登录失败: $e');
    }
  }

  /// 从 HTML 中提取错误信息
  String _extractErrorMessage(String html) {
    // 尝试匹配 id="showMsg" 的元素
    final showMsgPattern = RegExp(
      r'''id=["']showMsg["'][^>]*>([^<]+)<''',
      caseSensitive: false,
    );
    var match = showMsgPattern.firstMatch(html);
    if (match != null) {
      return match.group(1)?.trim() ?? '登录失败';
    }

    // 尝试匹配红色字体的错误信息
    final redFontPattern = RegExp(
      r'''<font[^>]*color=["']?red["']?[^>]*>([^<]+)</font>''',
      caseSensitive: false,
    );
    match = redFontPattern.firstMatch(html);
    if (match != null) {
      return match.group(1)?.trim() ?? '登录失败';
    }

    return '登录失败，请检查账号密码';
  }

  /// 登出
  Future<void> logout() async {
    try {
      await _dio.get('/Logon.do?method=logout');
    } catch (_) {
      // 忽略登出错误
    } finally {
      _isLoggedIn = false;
      _currentUser = null;
      _cachedScode = null;
      _cachedSxh = null;
      _cookieJar.deleteAll();
    }
  }

  /// 获取课程表
  ///
  /// [xnxq] 学年学期，格式如 "2024-2025-1"，为空则获取当前学期
  Future<Schedule?> getSchedule({String? xnxq}) async {
    if (!_isLoggedIn) return null;

    try {
      // 构建请求参数
      String url = '/jsxsd/xskb/xskb_list.do';
      if (xnxq != null) {
        url += '?xnxq01id=$xnxq';
      }

      var response = await _dio.get(url);
      var html = response.data.toString();

      // 检查会话是否过期
      if (_isSessionExpired(response)) {
        print('检测到会话过期，尝试自动重新登录...');
        if (await _tryAutoRelogin()) {
          // 重新请求
          response = await _dio.get(url);
          html = response.data.toString();
          // 再次检查
          if (_isSessionExpired(response)) {
            print('重新登录后会话仍然无效');
            return null;
          }
        } else {
          return null;
        }
      }

      print('=== 课程表 HTML 长度: ${html.length} ===');
      // 打印前3000字符用于调试
      print('=== HTML 内容预览 ===');
      print(html.substring(0, html.length > 3000 ? 3000 : html.length));
      print('=== HTML 预览结束 ===');

      return _parseScheduleHtml(html);
    } catch (e) {
      print('获取课程表失败: $e');
      return null;
    }
  }

  /// 解析课程表 HTML
  ///
  /// 强智教务系统课程表结构：
  /// - 表格 id="timetable"
  /// - 每行代表一个时间段（大节）
  /// - 每列代表一天（周一到周日）
  /// - 每个单元格有两个版本：kbcontent1(简略) 和 kbcontent(详细，含教师)
  /// - 课程信息格式：课程名<br/><font title='周次(节次)'>周次</font><br/><font title='教室'>教室</font>
  /// - 多门课程用 ---------------------- 分隔
  Schedule? _parseScheduleHtml(String html) {
    final courses = <Course>[];

    // 查找课程表表格 - id="timetable"
    final tablePattern = RegExp(
      r'''<table[^>]*id=["']timetable["'][^>]*>(.*?)</table>''',
      dotAll: true,
      caseSensitive: false,
    );
    final tableMatch = tablePattern.firstMatch(html);

    if (tableMatch == null) {
      print('未找到课程表表格 (id="timetable")');
      return Schedule(
        semester: _extractSemester(html),
        currentWeek: _extractCurrentWeek(html),
        courses: [],
      );
    }

    final tableHtml = tableMatch.group(1) ?? '';
    print('找到课程表表格，长度: ${tableHtml.length}');

    // 解析每一行
    final rowPattern = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
    final rows = rowPattern.allMatches(tableHtml).toList();
    print('找到 ${rows.length} 行');

    // 节次映射：每行（大节）对应的起始和结束小节
    // 第一大节(01,02), 第二大节(03,04), 第三大节(05,06), 第四大节(07,08), 第五大节(09,10), 第六大节(11,12)
    final sectionMapping = [
      [1, 2],
      [3, 4],
      [5, 6],
      [7, 8],
      [9, 10],
      [11, 12],
    ];

    int dataRowIndex = 0; // 数据行索引（跳过表头）

    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final rowHtml = rows[rowIndex].group(1) ?? '';

      // 跳过表头行（只包含 th 标签的星期标题行）
      if (!rowHtml.contains('<td')) {
        continue;
      }

      // 跳过备注行
      if (rowHtml.contains('备注')) {
        continue;
      }

      // 计算当前行对应的节次
      if (dataRowIndex >= sectionMapping.length) {
        dataRowIndex++;
        continue;
      }

      final startSection = sectionMapping[dataRowIndex][0];
      final endSection = sectionMapping[dataRowIndex][1];
      print('处理第 ${dataRowIndex + 1} 大节 (第$startSection-$endSection小节)');

      // 解析每个 td 单元格
      final cellPattern = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
      final cells = cellPattern.allMatches(rowHtml).toList();
      print('  找到 ${cells.length} 个单元格');

      // 遍历每个单元格（对应星期一到星期日）
      for (int cellIndex = 0; cellIndex < cells.length; cellIndex++) {
        final cellHtml = cells[cellIndex].group(1) ?? '';
        final weekday = cellIndex + 1; // 星期1-7

        if (weekday > 7) break;

        // 优先使用 kbcontent（详细版，包含教师信息）
        // 如果没有找到，则回退到 kbcontent1（简略版）
        var courseDivPattern = RegExp(
          r'''<div[^>]*class=["']kbcontent["'\s][^>]*>(.*?)</div>''',
          dotAll: true,
          caseSensitive: false,
        );

        var courseMatches = courseDivPattern.allMatches(cellHtml).toList();

        // 如果没有找到 kbcontent，尝试 kbcontent1
        if (courseMatches.isEmpty) {
          courseDivPattern = RegExp(
            r'''<div[^>]*class=["']kbcontent1["'\s][^>]*>(.*?)</div>''',
            dotAll: true,
            caseSensitive: false,
          );
          courseMatches = courseDivPattern.allMatches(cellHtml).toList();
        }

        for (final courseMatch in courseMatches) {
          final courseHtml = courseMatch.group(1) ?? '';

          // 跳过空内容
          if (courseHtml.trim().isEmpty ||
              courseHtml.trim() == '&nbsp;' ||
              !courseHtml.contains('<font')) {
            continue;
          }

          // 按分隔线分割多门课程 (---------------------- 或 --------- 等)
          // 分隔线前后可能有 <br> 标签
          final courseBlocks = courseHtml.split(
            RegExp(r'<br\s*/?>?\s*-{5,}\s*<br\s*/?>?|-{10,}'),
          );

          for (final block in courseBlocks) {
            final trimmedBlock = block.trim();
            if (trimmedBlock.isEmpty ||
                trimmedBlock == '<br>' ||
                trimmedBlock == '<br/>' ||
                !trimmedBlock.contains('<font')) {
              continue;
            }

            final course = _parseCourseFromDiv(
              block,
              weekday,
              startSection,
              endSection,
            );

            if (course != null) {
              courses.add(course);
              print(
                '  添加课程: ${course.name} | 教师=${course.teacher ?? "无"} | 周$weekday | 第$startSection-$endSection节 | 周次=${course.weeks}',
              );
            }
          }
        }
      }

      dataRowIndex++;
    }

    print('=== 共解析到 ${courses.length} 门课程 ===');

    // 合并相同课程（同一课程在同一时间段但不同周次的记录）
    final mergedCourses = _mergeCourses(courses);
    print('=== 合并后共 ${mergedCourses.length} 门课程 ===');

    return Schedule(
      semester: _extractSemester(html),
      currentWeek: _extractCurrentWeek(html),
      courses: mergedCourses,
    );
  }

  /// 从课程 div 中解析课程信息
  ///
  /// 典型格式：
  /// 课程名<br/><font title='教师'>教师名</font><br/><font title='周次(节次)'>2-16(周)[01-02节]</font><br/><font title='教室'>教室地点</font><br/>
  /// 或简略版：
  /// 课程名<br/><font title='周次(节次)'>2-16(周)</font><br/><font title='教室'>教室地点</font><br/>
  Course? _parseCourseFromDiv(
    String html,
    int weekday,
    int startSection,
    int endSection,
  ) {
    // 清理 HTML，去掉换行和多余空格
    final cleanHtml = html.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 提取课程名（在第一个 <br 或 <font 之前的文本）
    String? name;
    final nameMatch = RegExp(r'^([^<]+)').firstMatch(cleanHtml);
    if (nameMatch != null) {
      name = nameMatch.group(1)?.replaceAll('&nbsp;', '').trim();
    }

    // 如果开头是 <br，尝试在其后查找课程名
    if (name == null || name.isEmpty) {
      final altNameMatch = RegExp(r'<br\s*/?>\s*([^<]+)').firstMatch(cleanHtml);
      if (altNameMatch != null) {
        name = altNameMatch.group(1)?.replaceAll('&nbsp;', '').trim();
      }
    }

    if (name == null || name.isEmpty || name == '&nbsp;') return null;

    // 提取教师信息 - 从 <font title='教师'> 中查找
    String? teacher;
    final teacherPattern = RegExp(
      r'''<font[^>]*title=["']教师["'][^>]*>([^<]+)</font>''',
      caseSensitive: false,
    );
    final teacherMatch = teacherPattern.firstMatch(html);
    if (teacherMatch != null) {
      teacher = teacherMatch.group(1)?.trim();
    }

    // 提取周次信息 - 从 <font title='周次(节次)'> 中查找
    String? weekRange;
    List<int> weeks = [];

    final weekPattern = RegExp(
      r'''<font[^>]*title=["']周次[^"']*["'][^>]*>([^<]+)</font>''',
      caseSensitive: false,
    );
    final weekMatch = weekPattern.firstMatch(html);
    if (weekMatch != null) {
      weekRange = weekMatch.group(1)?.trim();
      if (weekRange != null) {
        weeks = _parseWeekRange(weekRange);
      }
    }

    // 提取教室信息 - 从 <font title='教室'> 中查找
    String? location;
    final locationPattern = RegExp(
      r'''<font[^>]*title=["']教室["'][^>]*>([^<]+)</font>''',
      caseSensitive: false,
    );
    final locationMatch = locationPattern.firstMatch(html);
    if (locationMatch != null) {
      location = locationMatch.group(1)?.trim();
    }

    // 如果没有解析到周次，默认1-20周
    if (weeks.isEmpty) {
      weeks = List.generate(20, (i) => i + 1);
    }

    return Course(
      name: name,
      teacher: teacher,
      location: location,
      weekday: weekday,
      startSection: startSection,
      endSection: endSection,
      weekRange: weekRange,
      weeks: weeks,
    );
  }

  /// 合并相同课程
  ///
  /// 同一课程在同一时间段但不同周次的记录会被合并
  /// 例如：同一门课在周二3-4节，但分成多个周次记录，会被合并为一条
  List<Course> _mergeCourses(List<Course> courses) {
    if (courses.isEmpty) return courses;

    // 按课程名、星期、节次分组
    final Map<String, List<Course>> grouped = {};

    for (final course in courses) {
      final key =
          '${course.name}_${course.weekday}_${course.startSection}_${course.endSection}';
      grouped.putIfAbsent(key, () => []).add(course);
    }

    final mergedCourses = <Course>[];

    for (final entry in grouped.entries) {
      final group = entry.value;

      if (group.length == 1) {
        mergedCourses.add(group.first);
      } else {
        // 合并周次
        final allWeeks = <int>{};
        for (final course in group) {
          allWeeks.addAll(course.weeks);
        }
        final sortedWeeks = allWeeks.toList()..sort();

        // 使用第一个课程的其他信息，合并周次
        final first = group.first;
        mergedCourses.add(
          Course(
            name: first.name,
            teacher: first.teacher,
            location: first.location,
            weekday: first.weekday,
            startSection: first.startSection,
            endSection: first.endSection,
            weeks: sortedWeeks,
          ),
        );

        print(
          '  合并课程: ${first.name} | 周${first.weekday} | 第${first.startSection}-${first.endSection}节 | '
          '${group.length}条记录 -> 周次=${sortedWeeks}',
        );
      }
    }

    return mergedCourses;
  }

  /// 解析周次范围字符串
  ///
  /// 支持格式：
  /// - "17-19(周)" -> [17, 18, 19]
  /// - "2-16(周)" -> [2, 3, ..., 16]
  /// - "4-7,9-11(周)" -> [4, 5, 6, 7, 9, 10, 11]
  /// - "2,4-7,9-16(周)" -> [2, 4, 5, 6, 7, 9, 10, ..., 16]
  /// - "12(周)" -> [12]
  /// - "单周" 或 "双周" 修饰符
  List<int> _parseWeekRange(String weekStr) {
    final weeks = <int>[];

    // 检查单双周
    final isSingleWeek = weekStr.contains('单');
    final isDoubleWeek = weekStr.contains('双');

    // 移除"(周)"后缀和节次信息[01-02节]，只保留周次部分
    // 例如 "2,4-7,9-16(周)[01-02节]" -> "2,4-7,9-16"
    String cleanStr = weekStr
        .replaceAll(RegExp(r'\[.*?\]'), '') // 移除 [01-02节] 部分
        .replaceAll(RegExp(r'\(周\)'), '') // 移除 (周)
        .replaceAll('周', '') // 移除 "周"
        .trim();

    print('    周次解析: "$weekStr" -> "$cleanStr"');

    // 按逗号分割
    final parts = cleanStr.split(',');

    for (final part in parts) {
      final trimmedPart = part.trim();
      if (trimmedPart.isEmpty) continue;

      // 检查是否是范围格式 如 "4-7"
      final rangeMatch = RegExp(r'^(\d+)-(\d+)$').firstMatch(trimmedPart);
      if (rangeMatch != null) {
        final start = int.tryParse(rangeMatch.group(1) ?? '') ?? 0;
        final end = int.tryParse(rangeMatch.group(2) ?? '') ?? 0;

        for (int i = start; i <= end; i++) {
          if (isSingleWeek && i % 2 == 0) continue; // 单周跳过偶数
          if (isDoubleWeek && i % 2 == 1) continue; // 双周跳过奇数
          if (!weeks.contains(i)) weeks.add(i);
        }
      } else {
        // 单个数字
        final week = int.tryParse(trimmedPart);
        if (week != null) {
          if (isSingleWeek && week % 2 == 0) continue;
          if (isDoubleWeek && week % 2 == 1) continue;
          if (!weeks.contains(week)) weeks.add(week);
        }
      }
    }

    weeks.sort();
    print('    解析结果: $weeks');
    return weeks;
  }

  /// 提取学期信息
  String? _extractSemester(String html) {
    // 尝试从下拉框中获取当前选中的学期
    // <option value="2025-2026-1" selected="selected">2025-2026-1</option>
    final selectPattern = RegExp(
      r'''<option[^>]*value=["']([^"']+)["'][^>]*selected[^>]*>''',
      caseSensitive: false,
    );
    final selectMatch = selectPattern.firstMatch(html);
    if (selectMatch != null) {
      return selectMatch.group(1);
    }

    // 尝试匹配其他格式
    final pattern = RegExp(r'(\d{4}-\d{4}-[12])');
    final match = pattern.firstMatch(html);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  /// 提取当前周次
  int _extractCurrentWeek(String html) {
    // 强智教务系统的课程表页面通常不直接显示当前周
    // 需要从其他 API 获取，或者根据学期开始日期计算
    return 1;
  }

  /// 获取当前周次（从教务系统获取）
  Future<int> fetchCurrentWeek() async {
    // 优先使用用户设置的开学日期计算
    final userWeek = await _getUserDefinedCurrentWeek();
    if (userWeek > 0) {
      print('使用用户设置的开学日期计算当前周: $userWeek');
      return userWeek;
    }

    if (!_isLoggedIn) return _estimateCurrentWeek();

    try {
      // 尝试从主页获取当前周
      final response = await _dio.get('/jsxsd/framework/xsMain.jsp');
      final html = response.data.toString();
      print('=== 尝试获取当前周 ===');
      print('主页 HTML 长度: ${html.length}');

      // 查找类似 "第X周" 的文本
      final weekPattern = RegExp(r'第\s*(\d+)\s*周');
      final match = weekPattern.firstMatch(html);
      if (match != null) {
        final week = int.tryParse(match.group(1) ?? '1') ?? 1;
        print('从主页获取到当前周: $week');
        return week;
      }

      // 尝试查找其他格式
      final weekPattern2 = RegExp(r'周次[：:](\d+)');
      final match2 = weekPattern2.firstMatch(html);
      if (match2 != null) {
        final week = int.tryParse(match2.group(1) ?? '1') ?? 1;
        print('从主页获取到当前周(格式2): $week');
        return week;
      }
    } catch (e) {
      print('获取当前周次失败: $e');
    }

    // 如果获取失败，根据日期估算
    return _estimateCurrentWeek();
  }

  /// 根据用户设置的开学日期计算当前周次
  Future<int> _getUserDefinedCurrentWeek() async {
    try {
      // 动态导入以避免循环依赖
      final prefs = await SharedPreferences.getInstance();
      final dateStr = prefs.getString('semester_start_date');
      if (dateStr == null) return 0;

      final startDate = DateTime.tryParse(dateStr);
      if (startDate == null) return 0;

      final now = DateTime.now();
      final difference = now.difference(startDate).inDays;

      if (difference < 0) return 0; // 还没开学

      final week = (difference ~/ 7) + 1;
      return week.clamp(1, 25);
    } catch (e) {
      return 0;
    }
  }

  /// 根据日期估算当前周次
  /// 假设每学期大约从9月初或2月底开始
  int _estimateCurrentWeek() {
    final now = DateTime.now();
    final month = now.month;

    // 秋季学期：9月到次年1月（第一学期）
    // 春季学期：2月底到7月（第二学期）
    int startMonth;
    int startDay;

    if (month >= 9 || month == 1) {
      // 秋季学期，假设9月1日开学
      startMonth = 9;
      startDay = 1;
    } else if (month >= 2 && month <= 7) {
      // 春季学期，假设2月26日开学
      startMonth = 2;
      startDay = 26;
    } else {
      // 8月，假期，返回1
      return 1;
    }

    // 计算开学日期
    int startYear = now.year;
    if (month == 1) {
      startYear -= 1; // 1月份属于上一年开始的秋季学期
    }

    final startDate = DateTime(startYear, startMonth, startDay);
    final difference = now.difference(startDate).inDays;

    if (difference < 0) {
      return 1; // 还没开学
    }

    final week = (difference ~/ 7) + 1;
    print('估算当前周: $week (基于日期 ${now.toString().substring(0, 10)})');

    // 限制在合理范围内
    return week.clamp(1, 25);
  }

  /// 获取成绩
  ///
  /// [kksj] 开课时间（学期），如 "2024-2025-1"，为空则获取所有成绩
  Future<List<SemesterGrades>?> getGrades({String? kksj}) async {
    if (!_isLoggedIn) return null;

    try {
      String url = '/jsxsd/kscj/cjcx_list';
      if (kksj != null) {
        url += '?kksj=$kksj';
      }

      var response = await _dio.get(url);
      var html = response.data.toString();

      // 检查会话是否过期
      if (_isSessionExpired(response)) {
        print('检测到会话过期，尝试自动重新登录...');
        if (await _tryAutoRelogin()) {
          response = await _dio.get(url);
          html = response.data.toString();
          if (_isSessionExpired(response)) {
            print('重新登录后会话仍然无效');
            return null;
          }
        } else {
          return null;
        }
      }

      print('=== 成绩 HTML 长度: ${html.length} ===');

      return _parseGradesHtml(html);
    } catch (e) {
      print('获取成绩失败: $e');
      return null;
    }
  }

  /// 解析成绩 HTML
  ///
  /// 强智教务系统成绩表结构：
  /// - 表格 id="dataList"
  /// - 列顺序通常为：序号、学年学期、课程代码、课程名称、课程性质、课程归属、学分、绩点、成绩、...
  List<SemesterGrades>? _parseGradesHtml(String html) {
    final grades = <Grade>[];

    // 查找成绩表格
    final tablePattern = RegExp(
      r'''<table[^>]*id=["']dataList["'][^>]*>(.*?)</table>''',
      dotAll: true,
      caseSensitive: false,
    );
    final tableMatch = tablePattern.firstMatch(html);

    if (tableMatch == null) {
      print('未找到成绩表格 (id="dataList")');
      return [];
    }

    final tableHtml = tableMatch.group(1) ?? '';
    print('找到成绩表格，长度: ${tableHtml.length}');

    // 解析表头以确定列索引
    final headerPattern = RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true);
    final headers = headerPattern
        .allMatches(tableHtml)
        .map((m) => _cleanHtmlText(m.group(1) ?? ''))
        .toList();

    print('表头: $headers');

    // 确定各列索引
    int semesterIndex = _findColumnIndex(headers, ['学年学期', '学期', '开课学期']);
    int courseCodeIndex = _findColumnIndex(headers, ['课程代码', '课程编号']);
    int courseNameIndex = _findColumnIndex(headers, ['课程名称', '课程']);
    int courseTypeIndex = _findColumnIndex(headers, ['课程性质', '性质']);
    int creditIndex = _findColumnIndex(headers, ['学分']);
    int gpaIndex = _findColumnIndex(headers, ['绩点']);
    int scoreIndex = _findColumnIndex(headers, ['成绩', '总成绩']);
    int examTypeIndex = _findColumnIndex(headers, ['考试性质', '考核方式']);

    print(
      '列索引 - 学期:$semesterIndex 课程名:$courseNameIndex 学分:$creditIndex 绩点:$gpaIndex 成绩:$scoreIndex',
    );

    // 解析数据行
    final rowPattern = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
    final rows = rowPattern.allMatches(tableHtml).skip(1).toList(); // 跳过表头行

    for (final row in rows) {
      final rowHtml = row.group(1) ?? '';

      // 跳过只有 th 的行
      if (!rowHtml.contains('<td')) continue;

      // 解析单元格
      final cellPattern = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
      final cells = cellPattern
          .allMatches(rowHtml)
          .map((m) => _cleanHtmlText(m.group(1) ?? ''))
          .toList();

      if (cells.isEmpty) continue;

      // 调试：打印第一行的所有单元格内容
      if (grades.isEmpty) {
        print('第一行数据 cells 数量: ${cells.length}');
        for (int i = 0; i < cells.length; i++) {
          print('  cells[$i]: ${cells[i]}');
        }
      }

      // 提取各字段
      String? semester = _safeGetCell(cells, semesterIndex);
      String? courseCode = _safeGetCell(cells, courseCodeIndex);
      String? courseName = _safeGetCell(cells, courseNameIndex);
      String? courseType = _safeGetCell(cells, courseTypeIndex);
      String? creditStr = _safeGetCell(cells, creditIndex);
      String? gpaStr = _safeGetCell(cells, gpaIndex);
      String? score = _safeGetCell(cells, scoreIndex);
      String? examType = _safeGetCell(cells, examTypeIndex);

      // 验证必要字段
      if (courseName == null || courseName.isEmpty) continue;
      if (score == null || score.isEmpty) continue;

      final credit = double.tryParse(creditStr ?? '') ?? 0.0;
      final gpa = double.tryParse(gpaStr ?? '');

      grades.add(
        Grade(
          courseName: courseName,
          courseCode: courseCode,
          score: score,
          gpa: gpa,
          credit: credit,
          courseType: courseType,
          examType: examType,
          semester: semester,
        ),
      );

      print('添加成绩: $courseName | $score | 学分$credit | 绩点$gpa');
    }

    print('=== 共解析到 ${grades.length} 条成绩 ===');

    // 按学期分组
    final groupedGrades = <String, List<Grade>>{};
    for (final grade in grades) {
      final semester = grade.semester ?? '未知学期';
      groupedGrades.putIfAbsent(semester, () => []).add(grade);
    }

    // 转换为 SemesterGrades 列表，按学期倒序排列
    final result =
        groupedGrades.entries
            .map((e) => SemesterGrades(semester: e.key, grades: e.value))
            .toList()
          ..sort((a, b) => b.semester.compareTo(a.semester));

    return result;
  }

  /// 查找列索引
  int _findColumnIndex(List<String> headers, List<String> possibleNames) {
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].trim();
      for (final name in possibleNames) {
        // 使用精确匹配而非包含匹配，避免"课程编号"匹配到"课程名称"
        if (header == name) {
          return i;
        }
      }
    }
    // 如果精确匹配失败，再尝试包含匹配
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].trim();
      for (final name in possibleNames) {
        if (header.contains(name)) {
          return i;
        }
      }
    }
    return -1;
  }

  /// 安全获取单元格内容
  String? _safeGetCell(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) return null;
    final value = cells[index].trim();
    return value.isEmpty ? null : value;
  }

  /// 清理 HTML 文本
  String _cleanHtmlText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '') // 移除 HTML 标签
        .replaceAll('&nbsp;', ' ') // 替换 &nbsp;
        .replaceAll(RegExp(r'\s+'), ' ') // 合并空白字符
        .trim();
  }

  /// 获取用户信息
  Future<User?> getUserInfo() async {
    if (!_isLoggedIn) return null;

    try {
      // 从学生信息页面获取用户详细信息
      var response = await _dio.get('/jsxsd/grxx/xsxx');
      var html = response.data.toString();

      // 检查会话是否过期
      if (_isSessionExpired(response)) {
        print('检测到会话过期，尝试自动重新登录...');
        if (await _tryAutoRelogin()) {
          response = await _dio.get('/jsxsd/grxx/xsxx');
          html = response.data.toString();
          if (_isSessionExpired(response)) {
            print('重新登录后会话仍然无效');
            return _currentUser;
          }
        } else {
          return _currentUser;
        }
      }

      return _parseUserInfoHtml(html);
    } catch (e) {
      print('获取用户信息失败: $e');
      return _currentUser;
    }
  }

  /// 解析用户信息 HTML
  User? _parseUserInfoHtml(String html) {
    String? name;
    String? college;
    String? major;
    String? className;
    String? enrollmentYear;
    String? studyLevel;

    // 该 HTML 有两种格式:
    // 1. 表头行格式: <td>院系：软件学院</td> (院系、专业、班级、学号在同一行)
    // 2. 表格格式: <td>姓名</td><td>&nbsp;值</td> (姓名、学习层次等)

    // 提取院系 - 格式: 院系：xxx
    final collegePattern = RegExp(r'>院系[：:]\s*([^<]+)<', caseSensitive: false);
    final collegeMatch = collegePattern.firstMatch(html);
    if (collegeMatch != null) {
      college = collegeMatch.group(1)?.trim();
    }

    // 提取专业 - 格式: 专业：xxx
    final majorPattern = RegExp(r'>专业[：:]\s*([^<]+)<', caseSensitive: false);
    final majorMatch = majorPattern.firstMatch(html);
    if (majorMatch != null) {
      major = majorMatch.group(1)?.trim();
    }

    // 提取班级 - 格式: 班级：xxx
    final classPattern = RegExp(r'>班级[：:]\s*([^<]+)<', caseSensitive: false);
    final classMatch = classPattern.firstMatch(html);
    if (classMatch != null) {
      className = classMatch.group(1)?.trim();
    }

    // 提取姓名 - 格式: <td>姓名</td><td>&nbsp;xxx</td>
    final namePattern = RegExp(
      r'>姓名</td>\s*<td[^>]*>\s*(?:&nbsp;)?\s*([^<]+)<',
      caseSensitive: false,
    );
    final nameMatch = namePattern.firstMatch(html);
    if (nameMatch != null) {
      name = nameMatch.group(1)?.trim().replaceAll('&nbsp;', '').trim();
    }

    // 提取学习层次 - 格式: <td>学习层次</td><td colspan="2">&nbsp;普通大专</td>
    final studyLevelPattern = RegExp(
      r'>学习层次</td>\s*<td[^>]*>\s*(?:&nbsp;)?\s*([^<]+)<',
      caseSensitive: false,
    );
    final studyLevelMatch = studyLevelPattern.firstMatch(html);
    if (studyLevelMatch != null) {
      studyLevel = studyLevelMatch
          .group(1)
          ?.trim()
          .replaceAll('&nbsp;', '')
          .trim();
    }

    // 提取入学日期 - 格式: <td>入学日期</td><td colspan="3">&nbsp;2024-09-13</td>
    final enrollmentPattern = RegExp(
      r'>入学日期</td>\s*<td[^>]*>\s*(?:&nbsp;)?\s*([^<]+)<',
      caseSensitive: false,
    );
    final enrollmentMatch = enrollmentPattern.firstMatch(html);
    if (enrollmentMatch != null) {
      final dateStr = enrollmentMatch
          .group(1)
          ?.trim()
          .replaceAll('&nbsp;', '')
          .trim();
      // 从日期中提取年份，如 "2024-09-13" -> "2024"
      if (dateStr != null && dateStr.isNotEmpty) {
        final yearMatch = RegExp(r'(\d{4})').firstMatch(dateStr);
        if (yearMatch != null) {
          enrollmentYear = yearMatch.group(1);
        }
      }
    }

    // 如果没有找到入学年份，从学号提取（前4位通常是年份）
    if (enrollmentYear == null && _currentUser != null) {
      final studentId = _currentUser!.studentId;
      if (studentId.length >= 4) {
        final yearStr = studentId.substring(0, 4);
        if (int.tryParse(yearStr) != null) {
          enrollmentYear = yearStr;
        }
      }
    }

    // 调试输出
    print(
      '解析结果 - 姓名: $name, 学院: $college, 专业: $major, 班级: $className, 入学年份: $enrollmentYear, 学习层次: $studyLevel',
    );

    if (_currentUser == null) return null;

    return _currentUser!.copyWith(
      name: name,
      college: college,
      major: major,
      className: className,
      enrollmentYear: enrollmentYear,
      studyLevel: studyLevel,
    );
  }

  /// 获取可用学期列表
  Future<List<String>> getAvailableSemesters() async {
    if (!_isLoggedIn) return [];

    try {
      final response = await _dio.get('/jsxsd/kscj/cjcx_list');
      final html = response.data.toString();

      // 从下拉框中提取学期列表
      final optionPattern = RegExp(
        r'''<option[^>]*value=["']([^"']+)["'][^>]*>([^<]+)</option>''',
        caseSensitive: false,
      );

      final semesters = <String>[];
      for (final match in optionPattern.allMatches(html)) {
        final value = match.group(1) ?? '';
        if (value.contains('-')) {
          // 学期格式通常是 "2024-2025-1"
          semesters.add(value);
        }
      }

      return semesters;
    } catch (e) {
      print('获取学期列表失败: $e');
      return [];
    }
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }
}
