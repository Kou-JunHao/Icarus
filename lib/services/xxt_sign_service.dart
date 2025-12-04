/// 学习通签到服务
/// 独立实现，基于公开 API 文档，与 GPL 代码无关
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/xxt_sign.dart';
import '../models/xxt_activity.dart';
import 'account_manager.dart';

/// 学习通签到服务
class XxtSignService {
  static final XxtSignService _instance = XxtSignService._internal();
  factory XxtSignService() => _instance;
  XxtSignService._internal();

  final Dio _dio = Dio();

  /// 当前 Cookie
  String? _cookie;

  /// 用户信息
  String? _uid;
  String? _name;
  String? _fid;
  String? _uname; // 学号

  /// User-Agent (移动端)
  static const String _userAgent =
      'Dalvik/2.1.0 (Linux; U; Android 12; SM-N9006 Build/8aba9e4.0) '
      '(schild:ce31140dfcdc2fcd113ccdd86f89a9aa) (device:SM-N9006) '
      'Language/zh_CN com.chaoxing.mobile/ChaoXingStudy_3_6.5.1_android_phone_10837_265 '
      '(@Kalimdor)_68f184fd763546c1a04ab3a09b3deebb';

  /// 设置 Cookie（从 XxtService 获取登录状态）
  void setCookie(String cookie) {
    _cookie = cookie;
  }

  /// 获取当前用户名
  String? get currentUserName => _name;

  /// 获取当前用户 ID
  String? get currentUserId => _uid;

  /// 设置用户信息
  void setUserInfo({
    required String uid,
    required String name,
    required String fid,
  }) {
    _uid = uid;
    _name = name;
    _fid = fid;
  }

  /// 登录并获取用户信息
  Future<bool> login(String username, String password) async {
    try {
      // 使用与 XxtService 相同的登录方式（明文密码）
      final formData =
          'fid=-1'
          '&uname=${Uri.encodeComponent(username)}'
          '&password=${Uri.encodeComponent(password)}'
          '&refer=${Uri.encodeComponent('http://i.mooc.chaoxing.com')}';

      final response = await _dio.post(
        'https://passport2.chaoxing.com/fanyalogin',
        data: formData,
        options: Options(
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent': _userAgent,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      debugPrint('签到服务登录响应: ${response.data}');

      dynamic result = response.data;
      if (result is String) {
        result = jsonDecode(result);
      }

      if (result is Map && result['status'] == true) {
        // 提取 Cookie
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _cookie = _parseCookies(cookies);
          debugPrint('签到服务登录成功，Cookie: $_cookie');
        }

        // 获取用户信息
        await _fetchUserInfo();
        return true;
      }

      final errorMsg = result is Map
          ? (result['mes'] ?? result['msg'] ?? '未知错误')
          : '响应格式错误';
      debugPrint('签到服务登录失败: $errorMsg');
      return false;
    } catch (e) {
      debugPrint('签到服务登录失败: $e');
      return false;
    }
  }

  /// 解析 Cookie
  String _parseCookies(List<String> setCookieHeaders) {
    final cookies = <String>[];
    for (final header in setCookieHeaders) {
      final cookiePart = header.split(';').first.trim();
      if (cookiePart.contains('=')) {
        cookies.add(cookiePart);
      }
    }
    return cookies.join('; ');
  }

  /// 快速登录（只获取签到必需的信息，用于分享签到）
  Future<bool> loginFast(String username, String password) async {
    try {
      final formData =
          'fid=-1'
          '&uname=${Uri.encodeComponent(username)}'
          '&password=${Uri.encodeComponent(password)}'
          '&refer=${Uri.encodeComponent('http://i.mooc.chaoxing.com')}';

      final response = await _dio.post(
        'https://passport2.chaoxing.com/fanyalogin',
        data: formData,
        options: Options(
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent': _userAgent,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      dynamic result = response.data;
      if (result is String) {
        result = jsonDecode(result);
      }

      if (result is Map && result['status'] == true) {
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _cookie = _parseCookies(cookies);
        }

        // 只从 Cookie 提取 uid 和 fid，然后从一个快速接口获取 name 和 uname
        _extractUserInfoFromCookie();

        // 使用 SSO 接口获取用户信息（这是最快的方式）
        await _fetchUserInfoFast();
        return _uid != null && _name != null;
      }
      return false;
    } catch (e) {
      debugPrint('快速登录失败: $e');
      return false;
    }
  }

  /// 快速获取用户信息（只调用一个接口）
  Future<void> _fetchUserInfoFast() async {
    if (_cookie == null) return;

    try {
      final response = await _dio.get(
        'https://sso.chaoxing.com/apis/login/userLogin4Uname.do',
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is Map) {
        final msg = data['msg'];
        if (msg is Map) {
          _uid ??= msg['puid']?.toString() ?? msg['uid']?.toString();
          if (msg['name'] != null && msg['name'].toString().isNotEmpty) {
            _name = msg['name'].toString();
          }
          if (msg['uname'] != null && msg['uname'].toString().isNotEmpty) {
            _uname = msg['uname'].toString();
          }
          _fid ??= msg['fid']?.toString();
        }
      }
    } catch (e) {
      debugPrint('快速获取用户信息失败: $e');
    }
  }

  /// 获取用户信息
  Future<void> _fetchUserInfo() async {
    if (_cookie == null) return;

    // 首先尝试从 Cookie 中提取基本信息（uid 和 fid）
    _extractUserInfoFromCookie();

    // 即使有 uid，也需要继续获取真实姓名
    // Cookie 中不包含用户姓名信息

    try {
      // 方法1: 从 SSO 接口获取（这是最可靠的方式）
      final response = await _dio.get(
        'https://sso.chaoxing.com/apis/login/userLogin4Uname.do',
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      debugPrint('获取用户信息响应类型: ${response.data.runtimeType}');
      debugPrint('获取用户信息响应: ${response.data}');

      // 处理可能是 String 类型的 JSON 响应
      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is Map) {
        final msg = data['msg'];
        debugPrint('msg 类型: ${msg.runtimeType}, 内容: $msg');

        if (msg is Map) {
          // 优先使用 puid 作为 uid
          _uid ??= msg['puid']?.toString() ?? msg['uid']?.toString();
          // 获取真实姓名
          if (msg['name'] != null && msg['name'].toString().isNotEmpty) {
            _name = msg['name'].toString();
          }
          // 获取学号
          if (msg['uname'] != null && msg['uname'].toString().isNotEmpty) {
            _uname = msg['uname'].toString();
          }
          _fid ??= msg['fid']?.toString();
          debugPrint(
            '用户信息(SSO): uid=$_uid, name=$_name, uname=$_uname, fid=$_fid',
          );
          if (_uid != null && _name != null && _name!.isNotEmpty) return;
        }
      }

      // 方法2: 从账户信息接口获取
      final accountResponse = await _dio.get(
        'https://mobilelearn.chaoxing.com/v2/apis/active/student/getAccountInfo',
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      debugPrint('获取账户信息响应类型: ${accountResponse.data.runtimeType}');
      debugPrint('获取账户信息响应: ${accountResponse.data}');

      dynamic accountData = accountResponse.data;
      if (accountData is String) {
        accountData = jsonDecode(accountData);
      }

      if (accountData is Map && accountData['result'] == 1) {
        final infoData = accountData['data'] as Map<String, dynamic>?;
        if (infoData != null) {
          _uid ??= infoData['uid']?.toString();
          if (infoData['name'] != null &&
              infoData['name'].toString().isNotEmpty &&
              (_name == null || _name!.isEmpty)) {
            _name = infoData['name'].toString();
          }
          _fid ??= infoData['fid']?.toString() ?? '-1';
          debugPrint('用户信息(Account): uid=$_uid, name=$_name, fid=$_fid');
          if (_uid != null && _name != null && _name!.isNotEmpty) return;
        }
      }

      // 方法3: 从个人信息接口获取
      final profileResponse = await _dio.get(
        'https://passport2.chaoxing.com/mooc/accountManage',
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      // 尝试从 HTML 中提取姓名
      final html = profileResponse.data?.toString() ?? '';
      final nameMatch = RegExp(
        r'class="user-name[^"]*"[^>]*>([^<]+)<',
      ).firstMatch(html);
      if (nameMatch != null && _name == null) {
        final extractedName = nameMatch.group(1)?.trim();
        if (extractedName != null && extractedName.isNotEmpty) {
          _name = extractedName;
          debugPrint('用户信息(Profile): name=$_name');
        }
      }
    } catch (e) {
      debugPrint('获取用户信息失败: $e');
    }

    // 如果还是没有 name，尝试从其他接口获取
    if (_uid != null && (_name == null || _name!.isEmpty)) {
      await _fetchUserName();
    }

    // 最后如果还是没有 name，使用 uid 作为默认名称
    if (_uid != null && (_name == null || _name!.isEmpty)) {
      _name = '用户$_uid';
      debugPrint('使用默认名称: $_name');
    }
  }

  /// 额外尝试获取用户姓名
  Future<void> _fetchUserName() async {
    if (_cookie == null || _uid == null) return;

    try {
      // 尝试从用户信息接口获取
      final response = await _dio.get(
        'https://i.mooc.chaoxing.com/settings/info',
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      final html = response.data?.toString() ?? '';

      // 尝试多种模式匹配姓名
      final patterns = [
        RegExp(r'name="name"[^>]*value="([^"]+)"'),
        RegExp(r'"realName"\s*:\s*"([^"]+)"'),
        RegExp(r'真实姓名[：:]\s*([^\s<]+)'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final extractedName = match.group(1)?.trim();
          if (extractedName != null && extractedName.isNotEmpty) {
            _name = extractedName;
            debugPrint('用户信息(Settings): name=$_name');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('获取用户姓名失败: $e');
    }
  }

  /// 从 Cookie 中提取用户信息
  void _extractUserInfoFromCookie() {
    if (_cookie == null) return;

    // 提取 _uid 或 UID
    final uidMatch = RegExp(r'(?:_uid|UID)=(\d+)').firstMatch(_cookie!);
    if (uidMatch != null) {
      _uid = uidMatch.group(1);
    }

    // 提取 fid
    final fidMatch = RegExp(r'fid=(\d+)').firstMatch(_cookie!);
    if (fidMatch != null) {
      _fid = fidMatch.group(1);
    }
  }

  /// 生成设备码
  String _generateDeviceCode() {
    final random = Random();
    final uuid1 = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final uuid2 = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();

    final rawData = sha256.convert(utf8.encode(uuid1 + uuid2)).bytes;
    final doubledData = Uint8List.fromList([...rawData, ...rawData]);
    return base64.encode(doubledData);
  }

  /// 获取签到活动详情
  Future<XxtSignActivity?> getSignActivityInfo(
    String activeId,
    String courseName,
    String courseId,
    String classId,
  ) async {
    // 确保已登录
    if (_cookie == null) {
      final loginSuccess = await _ensureLoggedIn();
      if (!loginSuccess) {
        debugPrint('获取签到详情失败: 未登录');
        return null;
      }
    }

    try {
      final response = await _dio.get(
        'https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo',
        queryParameters: {'activeId': activeId},
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      debugPrint('获取签到详情响应: ${response.data}');

      if (response.data is Map && response.data['result'] == 1) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data == null) return null;

        // 安全解析 otherId（可能是 int 或 String）
        final otherIdRaw = data['otherId'];
        final otherId = otherIdRaw is int
            ? otherIdRaw
            : int.tryParse(otherIdRaw?.toString() ?? '') ?? 0;

        // 安全解析 ifphoto
        final ifphotoRaw = data['ifphoto'];
        final ifphoto = ifphotoRaw is int
            ? ifphotoRaw
            : int.tryParse(ifphotoRaw?.toString() ?? '') ?? 0;

        final signType = XxtSignType.fromOtherId(
          otherId,
          requirePhoto: ifphoto == 1,
        );

        // 安全解析时间戳
        final startTimeRaw = data['starttime'];
        final startTimeMs = startTimeRaw is int
            ? startTimeRaw
            : int.tryParse(startTimeRaw?.toString() ?? '');

        final endTimeRaw = data['endTime'];
        final endTimeMs = endTimeRaw is int
            ? endTimeRaw
            : int.tryParse(endTimeRaw?.toString() ?? '');

        // 安全解析其他字段
        int? parseIntField(dynamic value) {
          if (value == null) return null;
          if (value is int) return value;
          return int.tryParse(value.toString());
        }

        // 安全解析 double 字段
        double? parseDoubleField(dynamic value) {
          if (value == null) return null;
          if (value is num) return value.toDouble();
          return double.tryParse(value.toString());
        }

        // 解析签退信息
        XxtSignOutInfo? signOutInfo;
        final signInIdRaw = data['signInId'];
        final signOutIdRaw = data['signOutId'];
        final signOutPublishTimeRaw = data['signOutPublishTimeStamp'];

        // 解析各个字段的数值
        final signInIdNum = signInIdRaw is int
            ? signInIdRaw
            : int.tryParse(signInIdRaw?.toString() ?? '') ?? 0;
        final signOutIdNum = signOutIdRaw is int
            ? signOutIdRaw
            : int.tryParse(signOutIdRaw?.toString() ?? '') ?? 0;
        final signOutPublishTimeMs = signOutPublishTimeRaw is int
            ? signOutPublishTimeRaw
            : int.tryParse(signOutPublishTimeRaw?.toString() ?? '') ?? 0;

        // 只有当有实际签退信息时才创建 signOutInfo
        // signInId != 0 表示当前是签退活动
        // signOutPublishTimeMs > 0 表示有签退发布时间（设置了签退）
        final hasSignOutInfo = signInIdNum != 0 || signOutPublishTimeMs > 0;

        if (hasSignOutInfo) {
          signOutInfo = XxtSignOutInfo(
            signInId: signInIdNum != 0 ? signInIdNum.toString() : null,
            signOutId: signOutIdNum != 0 ? signOutIdNum.toString() : null,
            signOutPublishTime: signOutPublishTimeMs > 0
                ? DateTime.fromMillisecondsSinceEpoch(signOutPublishTimeMs)
                : null,
            courseId: courseId,
            classId: classId,
          );
          debugPrint('解析到签退信息: $signOutInfo');
        }

        return XxtSignActivity(
          activeId: activeId,
          signType: signType,
          name: data['name']?.toString() ?? '签到',
          courseName: courseName,
          courseId: courseId,
          classId: classId,
          startTime: startTimeMs != null
              ? DateTime.fromMillisecondsSinceEpoch(startTimeMs)
              : null,
          endTime: endTimeMs != null && endTimeMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(endTimeMs)
              : null,
          requirePhoto: ifphoto == 1,
          qrcodeRefresh: parseIntField(data['ifrefreshewm']) == 1,
          qrcodeRequireLocation: parseIntField(data['ifopenAddress']) == 1,
          locationLatitude: parseDoubleField(data['locationLatitude']),
          locationLongitude: parseDoubleField(data['locationLongitude']),
          locationRange: parseIntField(data['locationRange']),
          passwordLength: parseIntField(data['numberCount']),
          signOutInfo: signOutInfo,
        );
      }

      debugPrint('获取签到详情失败: result != 1, response=${response.data}');
      return null;
    } catch (e) {
      debugPrint('获取签到详情失败: $e');
      return null;
    }
  }

  /// 确保已登录
  Future<bool> _ensureLoggedIn() async {
    if (_cookie != null) return true;

    final accountManager = AccountManager();
    if (!accountManager.isInitialized) {
      await accountManager.init();
    }

    final activeAccount = accountManager.activeAccount;
    if (activeAccount?.xuexitong == null) {
      debugPrint('未配置学习通账号');
      return false;
    }

    return await login(
      activeAccount!.xuexitong!.username,
      activeAccount.xuexitong!.password,
    );
  }

  /// 执行预签到
  Future<bool> _preSign(XxtSignActivity activity) async {
    if (_cookie == null || _uid == null) return false;

    try {
      final response = await _dio.post(
        'https://mobilelearn.chaoxing.com/newsign/preSign',
        queryParameters: {
          'courseId': activity.courseId,
          'classId': activity.classId,
          'activePrimaryId': activity.activeId,
          'uid': _uid,
          'general': '1',
          'sys': '1',
          'ls': '1',
          'appType': '15',
          'isTeacherViewOpen': '0',
        },
        data: 'ext=',
        options: Options(
          headers: {
            'Cookie': _cookie,
            'User-Agent': _userAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      debugPrint('预签到响应: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('预签到失败: $e');
      return false;
    }
  }

  /// 执行分析请求
  Future<String?> _analysis(String activeId) async {
    if (_cookie == null) return null;

    try {
      final response = await _dio.get(
        'https://mobilelearn.chaoxing.com/pptSign/analysis',
        queryParameters: {'vs': '1', 'DB_STRATEGY': 'RANDOM', 'aid': activeId},
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      final html = response.data?.toString() ?? '';
      final match = RegExp(r"code='\+'([a-f0-9]+)'").firstMatch(html);
      return match?.group(1);
    } catch (e) {
      debugPrint('分析请求失败: $e');
      return null;
    }
  }

  /// 执行分析后请求
  Future<void> _analysis2(String code) async {
    if (_cookie == null) return;

    try {
      await _dio.get(
        'https://mobilelearn.chaoxing.com/pptSign/analysis2',
        queryParameters: {'DB_STRATEGY': 'RANDOM', 'code': code},
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );
    } catch (e) {
      debugPrint('分析后请求失败: $e');
    }
  }

  /// 获取签到位置（优先使用教师设定位置）
  XxtLocation? _getSignLocation(
    XxtSignActivity activity,
    XxtLocation? userLocation,
  ) {
    // 如果签到活动有教师设定的位置，优先使用
    if (activity.locationLatitude != null &&
        activity.locationLongitude != null) {
      debugPrint(
        '使用教师设定位置: ${activity.locationLatitude}, ${activity.locationLongitude}',
      );
      return XxtLocation(
        latitude: activity.locationLatitude!,
        longitude: activity.locationLongitude!,
        address: '签到位置', // 使用通用地址
      );
    }
    // 否则使用用户提供的位置
    if (userLocation != null) {
      debugPrint('使用用户位置: ${userLocation.latitude}, ${userLocation.longitude}');
    }
    return userLocation;
  }

  /// 提交签到
  Future<XxtSignResult> _submitSign(
    XxtSignActivity activity, {
    XxtLocation? location,
    String? objectId,
    String? enc,
    String? signCode,
    String? validate,
  }) async {
    if (_cookie == null || _uid == null || _name == null) {
      debugPrint('签到失败: cookie=$_cookie, uid=$_uid, name=$_name, fid=$_fid');
      return XxtSignResult.failed('未登录或用户信息不完整');
    }

    // fid 可以使用默认值
    final fid = _fid ?? '-1';

    try {
      final params = <String, dynamic>{
        'activeId': activity.activeId,
        'uid': _uid,
        'name': _name,
        'fid': fid,
        'deviceCode': _generateDeviceCode(),
        'clientip': '',
        'appType': '15',
        'ifTiJiao': '1',
        'vpProbability': '-1',
        'vpStrategy': '',
      };

      // 添加学号（如果有）
      if (_uname != null && _uname!.isNotEmpty) {
        params['uname'] = _uname;
      }

      // 根据签到类型添加额外参数
      switch (activity.signType) {
        case XxtSignType.normal:
          params['latitude'] = '-1';
          params['longitude'] = '-1';
          break;

        case XxtSignType.photo:
          params['objectId'] = objectId ?? '';
          break;

        case XxtSignType.qrcode:
          params['enc'] = enc ?? '';
          params['latitude'] = '-1';
          params['longitude'] = '-1';
          if (activity.qrcodeRequireLocation) {
            // 优先使用教师设定的位置，如果没有则使用用户位置
            final signLocation = _getSignLocation(activity, location);
            if (signLocation != null) {
              params['location'] = signLocation.toJsonString();
              params['latitude'] = signLocation.latitude.toString();
              params['longitude'] = signLocation.longitude.toString();
            }
          }
          break;

        case XxtSignType.gesture:
        case XxtSignType.password:
          params['signCode'] = signCode ?? '';
          params['latitude'] = '';
          params['longitude'] = '';
          break;

        case XxtSignType.location:
          // 优先使用教师设定的位置，如果没有则使用用户位置
          final signLocation = _getSignLocation(activity, location);
          if (signLocation != null) {
            params['latitude'] = signLocation.latitude.toString();
            params['longitude'] = signLocation.longitude.toString();
            params['address'] = signLocation.address;
          } else {
            return XxtSignResult.failed('位置签到需要提供位置信息');
          }
          break;
      }

      // 添加验证码参数
      if (validate != null) {
        params['validate'] = validate;
      }

      debugPrint('签到请求参数: $params');

      final response = await _dio.get(
        'https://mobilelearn.chaoxing.com/pptSign/stuSignajax',
        queryParameters: params,
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      final result = response.data?.toString() ?? '';
      debugPrint('签到结果: $result');

      if (result == 'success') {
        return XxtSignResult.success();
      } else if (result == 'success2') {
        return XxtSignResult.late();
      } else if (result.contains('已签到')) {
        return XxtSignResult.alreadySigned();
      } else if (result == 'validate' || result.startsWith('validate_')) {
        // validate 或 validate_XXXXX 都表示需要验证码
        return XxtSignResult.needValidate();
      } else {
        return XxtSignResult.failed(result);
      }
    } catch (e) {
      debugPrint('提交签到失败: $e');
      return XxtSignResult.failed('网络错误: $e');
    }
  }

  /// 校验签到密码/手势
  Future<bool> checkSignCode(String activeId, String signCode) async {
    if (_cookie == null) return false;

    try {
      final response = await _dio.get(
        'https://mobilelearn.chaoxing.com/widget/sign/pcStuSignController/checkSignCode',
        queryParameters: {'activeId': activeId, 'signCode': signCode},
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      if (response.data is Map) {
        return response.data['result'] == 1;
      }
      return false;
    } catch (e) {
      debugPrint('校验签到码失败: $e');
      return false;
    }
  }

  /// 上传图片（拍照签到用）
  Future<String?> uploadPhoto(Uint8List imageData) async {
    if (_cookie == null || _uid == null) return null;

    try {
      // 获取上传 token
      final tokenResponse = await _dio.get(
        'https://pan-yz.chaoxing.com/api/token/uservalid',
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      debugPrint('Token响应类型: ${tokenResponse.data.runtimeType}');
      debugPrint('Token响应: ${tokenResponse.data}');

      String? token;
      final data = tokenResponse.data;
      if (data is Map<String, dynamic>) {
        token = data['_token']?.toString();
      } else if (data is Map) {
        token = (data as dynamic)['_token']?.toString();
      } else if (data is String) {
        // 响应是 JSON 字符串，需要手动解析
        try {
          final jsonData = jsonDecode(data) as Map<String, dynamic>;
          token = jsonData['_token']?.toString();
        } catch (e) {
          debugPrint('JSON解析失败: $e');
        }
      }

      if (token == null || token.isEmpty) {
        debugPrint('获取上传token失败');
        return null;
      }

      debugPrint('使用token: $token');

      // 上传图片
      final formData = FormData.fromMap({
        'puid': _uid,
        'file': MultipartFile.fromBytes(
          imageData,
          filename: 'sign_photo.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      final uploadResponse = await _dio.post(
        'https://pan-yz.chaoxing.com/upload?_from=mobilelearn&_token=$token',
        data: formData,
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      debugPrint('上传响应类型: ${uploadResponse.data.runtimeType}');
      debugPrint('上传响应: ${uploadResponse.data}');

      String? objectId;
      final uploadData = uploadResponse.data;
      if (uploadData is Map<String, dynamic>) {
        objectId = uploadData['objectId']?.toString();
      } else if (uploadData is Map) {
        objectId = (uploadData as dynamic)['objectId']?.toString();
      } else if (uploadData is String) {
        // 响应是 JSON 字符串
        try {
          final jsonData = jsonDecode(uploadData) as Map<String, dynamic>;
          objectId = jsonData['objectId']?.toString();
        } catch (e) {
          debugPrint('上传响应JSON解析失败: $e');
        }
      }

      debugPrint('获取到objectId: $objectId');
      return objectId;
    } catch (e, stackTrace) {
      debugPrint('上传图片失败: $e');
      debugPrint('堆栈: $stackTrace');
      return null;
    }
  }

  /// 执行签到（完整流程）
  Future<XxtSignResult> sign(
    XxtSignActivity activity, {
    XxtLocation? location,
    Uint8List? photo,
    String? enc,
    String? signCode,
    String? validate,
  }) async {
    // 确保已登录
    if (_cookie == null) {
      final loginSuccess = await _ensureLoggedIn();
      if (!loginSuccess) {
        return XxtSignResult.failed('学习通登录失败，请检查账号配置');
      }
    }

    // 1. 预签到
    await _preSign(activity);

    // 2. 分析请求
    final code = await _analysis(activity.activeId);
    if (code != null) {
      await _analysis2(code);
    }

    // 3. 处理拍照签到的图片上传
    String? objectId;
    if (activity.signType == XxtSignType.photo && photo != null) {
      objectId = await uploadPhoto(photo);
      if (objectId == null) {
        return XxtSignResult.failed('图片上传失败');
      }
    }

    // 4. 提交签到
    return _submitSign(
      activity,
      location: location,
      objectId: objectId,
      enc: enc,
      signCode: signCode,
      validate: validate,
    );
  }

  /// 快速签到（用于分享签到）
  Future<XxtSignResult> signFast(
    XxtSignActivity activity, {
    XxtLocation? location,
    Uint8List? photo,
    String? enc,
    String? signCode,
    String? validate,
  }) async {
    // 确保已登录
    if (_cookie == null || _uid == null || _name == null) {
      return XxtSignResult.failed('未登录或用户信息不完整');
    }

    // 1. 执行预签到
    await _preSign(activity);

    // 2. 执行 analysis（反作弊）
    final code = await _analysis(activity.activeId);
    if (code != null) {
      await _analysis2(code);
    }

    // 3. 处理拍照签到的图片上传
    String? objectId;
    if (activity.signType == XxtSignType.photo && photo != null) {
      objectId = await uploadPhoto(photo);
      if (objectId == null) {
        return XxtSignResult.failed('图片上传失败');
      }
    }

    // 4. 提交签到
    return _submitSign(
      activity,
      location: location,
      objectId: objectId,
      enc: enc,
      signCode: signCode,
      validate: validate,
    );
  }

  /// 快速签到带验证码重试
  Future<XxtSignResult> signFastWithCaptchaRetry(
    XxtSignActivity activity, {
    XxtLocation? location,
    Uint8List? photo,
    String? enc,
    String? signCode,
    Future<String?> Function(XxtCaptchaData)? onCaptchaRequired,
  }) async {
    // 第一次尝试签到
    var result = await signFast(
      activity,
      location: location,
      photo: photo,
      enc: enc,
      signCode: signCode,
    );

    // 如果需要验证码且提供了验证码回调
    if (result.needCaptcha && onCaptchaRequired != null) {
      final captchaData = await getCaptchaImage(activity);
      if (captchaData == null) {
        return XxtSignResult.failed('获取验证码失败');
      }

      final validate = await onCaptchaRequired(captchaData);
      if (validate == null) {
        return XxtSignResult.failed('验证码验证取消');
      }

      result = await signFast(
        activity,
        location: location,
        photo: photo,
        enc: enc,
        signCode: signCode,
        validate: validate,
      );
    }

    return result;
  }

  /// 从 XxtActivity 创建签到任务并执行普通签到
  Future<XxtSignResult> signFromActivity(
    XxtActivity activity,
    XxtCourseActivities courseActivity, {
    XxtLocation? location,
    String? signCode,
    String? enc,
  }) async {
    if (activity.activeId == null) {
      return XxtSignResult.failed('活动 ID 无效');
    }

    // 获取签到详情
    final signActivity = await getSignActivityInfo(
      activity.activeId!,
      courseActivity.courseName,
      courseActivity.courseId,
      courseActivity.classId,
    );

    if (signActivity == null) {
      return XxtSignResult.failed('获取签到详情失败');
    }

    // 执行签到
    return sign(signActivity, location: location, signCode: signCode, enc: enc);
  }

  // ===================== 滑动验证码相关 =====================
  // 基于公开 API 端点实现，与 GPL 代码完全独立

  /// 验证码 ID（固定值）
  static const String _captchaId = 'Qt9FIw9o4pwRjOyqM6yizZBh682qN2TU';

  /// 获取验证码配置
  Future<int?> _getCaptchaConf() async {
    try {
      final response = await _dio.get(
        'https://captcha.chaoxing.com/captcha/get/conf',
        queryParameters: {
          'callback': 'cx_captcha_function',
          'captchaId': _captchaId,
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: Options(headers: {'User-Agent': _userAgent}),
      );

      final jsonStr = _parseJsonp(response.data?.toString() ?? '');
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr);
        return json['t'] as int?;
      }
    } catch (e) {
      debugPrint('获取验证码配置失败: $e');
    }
    return null;
  }

  /// 解析 JSONP 响应
  String? _parseJsonp(String response) {
    // 格式: cx_captcha_function({...})
    final match = RegExp(r'cx_captcha_function\((.+)\)').firstMatch(response);
    return match?.group(1);
  }

  /// 生成 MD5 哈希
  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// 获取验证码图片数据
  Future<XxtCaptchaData?> getCaptchaImage(XxtSignActivity activity) async {
    if (_cookie == null) return null;

    try {
      // 1. 获取配置中的时间戳 t
      final t = await _getCaptchaConf();
      if (t == null) {
        debugPrint('获取验证码配置失败');
        return null;
      }

      // 2. 生成必要参数
      final type = 'slide';
      final version = '1.1.20';
      final captchaKey = _md5('$t${_generateUuid()}');
      final iv = _md5(
        '$_captchaId$type${DateTime.now().millisecondsSinceEpoch}${_generateUuid()}',
      );
      final token = '${_md5('$t$_captchaId$type$captchaKey')}:${t + 300000}';

      // 3. 构建 referer URL
      final referer =
          'https://mobilelearn.chaoxing.com/newsign/preSign'
          '?courseId=${activity.courseId}'
          '&classId=${activity.classId}'
          '&activePrimaryId=${activity.activeId}'
          '&uid=$_uid'
          '&general=1&sys=1&ls=1&appType=15&isTeacherViewOpen=0';

      // 4. 请求验证码图片
      final response = await _dio.get(
        'https://captcha.chaoxing.com/captcha/get/verification/image',
        queryParameters: {
          'callback': 'cx_captcha_function',
          'captchaId': _captchaId,
          'type': type,
          'version': version,
          'captchaKey': captchaKey,
          'token': token,
          'referer': referer,
          'iv': iv,
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: Options(
          headers: {'Cookie': _cookie, 'User-Agent': _userAgent},
        ),
      );

      final jsonStr = _parseJsonp(response.data?.toString() ?? '');
      if (jsonStr == null) {
        debugPrint('解析验证码响应失败');
        return null;
      }

      final json = jsonDecode(jsonStr);
      final imageVo = json['imageVerificationVo'];
      if (imageVo == null) {
        debugPrint('验证码图片数据为空');
        return null;
      }

      return XxtCaptchaData(
        captchaId: _captchaId,
        type: type,
        version: version,
        token: json['token'] ?? token,
        captchaKey: captchaKey,
        iv: iv,
        shadeImageUrl: imageVo['shadeImage'] ?? '',
        cutoutImageUrl: imageVo['cutoutImage'] ?? '',
      );
    } catch (e) {
      debugPrint('获取验证码图片失败: $e');
      return null;
    }
  }

  /// 生成 UUID
  String _generateUuid() {
    final random = Random();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  /// 验证滑动验证码
  /// [xPosition] 滑块 x 坐标位置 (0-280)
  /// 返回 validate 字符串，失败返回 null
  Future<String?> checkCaptchaResult(
    double xPosition,
    XxtCaptchaData captchaData,
    XxtSignActivity activity,
  ) async {
    if (_cookie == null) return null;

    try {
      // 构建 referer URL
      final referer =
          'https://mobilelearn.chaoxing.com/newsign/preSign'
          '?courseId=${activity.courseId}'
          '&classId=${activity.classId}'
          '&activePrimaryId=${activity.activeId}'
          '&uid=$_uid'
          '&general=1&sys=1&ls=1&appType=15&isTeacherViewOpen=0';

      final response = await _dio.get(
        'https://captcha.chaoxing.com/captcha/check/verification/result',
        queryParameters: {
          'callback': 'cx_captcha_function',
          'captchaId': captchaData.captchaId,
          'type': captchaData.type,
          'token': captchaData.token,
          'textClickArr': '[{"x":${xPosition.toInt()}}]',
          'coordinate': '[]',
          'runEnv': '10',
          'version': captchaData.version,
          't': 'a',
          'iv': captchaData.iv,
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: Options(
          headers: {
            'Cookie': _cookie,
            'User-Agent': _userAgent,
            'Referer': referer,
          },
        ),
      );

      final jsonStr = _parseJsonp(response.data?.toString() ?? '');
      if (jsonStr == null) {
        debugPrint('解析验证码结果失败');
        return null;
      }

      final json = jsonDecode(jsonStr);
      debugPrint('验证码结果: $json');

      // 检查错误
      if (json['error'] == 1) {
        debugPrint('验证码校验错误: ${json['msg']}');
        return null;
      }

      // 检查结果
      if (json['result'] == true) {
        // 解析 extraData 获取 validate
        final extraDataStr = json['extraData']?.toString();
        if (extraDataStr != null) {
          final extraData = jsonDecode(extraDataStr.replaceAll(r'\"', '"'));
          return extraData['validate']?.toString();
        }
      }

      return null;
    } catch (e) {
      debugPrint('验证码校验失败: $e');
      return null;
    }
  }

  /// 带验证码重试的签到
  Future<XxtSignResult> signWithCaptchaRetry(
    XxtSignActivity activity, {
    XxtLocation? location,
    Uint8List? photo,
    String? enc,
    String? signCode,
    Future<String?> Function(XxtCaptchaData)? onCaptchaRequired,
  }) async {
    // 第一次尝试签到
    var result = await sign(
      activity,
      location: location,
      photo: photo,
      enc: enc,
      signCode: signCode,
    );

    // 如果需要验证码且提供了验证码回调
    if (result.needCaptcha && onCaptchaRequired != null) {
      debugPrint('需要验证码，开始获取验证码...');

      // 获取验证码
      final captchaData = await getCaptchaImage(activity);
      if (captchaData == null) {
        return XxtSignResult.failed('获取验证码失败');
      }

      // 回调让用户完成验证
      final validate = await onCaptchaRequired(captchaData);
      if (validate == null) {
        return XxtSignResult.failed('验证码验证取消');
      }

      // 使用验证码重新签到
      result = await sign(
        activity,
        location: location,
        photo: photo,
        enc: enc,
        signCode: signCode,
        validate: validate,
      );
    }

    return result;
  }

  /// 为指定账号执行签到（分享签到用）
  Future<XxtSignResult> signForAccount(
    XxtSignAccount account,
    XxtSignActivity activity, {
    XxtLocation? location,
    Uint8List? photo,
    String? enc,
    String? signCode,
    Future<String?> Function(XxtCaptchaData)? onCaptchaRequired,
  }) async {
    // 保存当前登录状态
    final savedCookie = _cookie;
    final savedUid = _uid;
    final savedName = _name;
    final savedFid = _fid;
    final savedUname = _uname;

    try {
      // 清除当前状态
      clearSession();

      // 使用快速登录（减少网络请求）
      final loginSuccess = await loginFast(account.username, account.password);
      if (!loginSuccess) {
        return XxtSignResult.failed('账号 ${account.displayName} 登录失败');
      }

      // 使用快速签到（跳过 analysis 步骤）
      return await signFastWithCaptchaRetry(
        activity,
        location: location,
        photo: photo,
        enc: enc,
        signCode: signCode,
        onCaptchaRequired: onCaptchaRequired,
      );
    } finally {
      // 恢复原来的登录状态
      _cookie = savedCookie;
      _uid = savedUid;
      _name = savedName;
      _fid = savedFid;
      _uname = savedUname;
    }
  }

  /// 分享签到（为多个账号签到）
  Future<XxtShareSignResult> shareSign(
    List<XxtSignAccount> accounts,
    XxtSignActivity activity, {
    XxtLocation? location,
    Uint8List? photo,
    String? enc,
    String? signCode,
    Future<String?> Function(XxtCaptchaData)? onCaptchaRequired,
    void Function(int current, int total, XxtSignAccount account)? onProgress,
  }) async {
    final results = <XxtSignAccountResult>[];

    for (var i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      onProgress?.call(i + 1, accounts.length, account);

      final result = await signForAccount(
        account,
        activity,
        location: location,
        photo: photo,
        enc: enc,
        signCode: signCode,
        onCaptchaRequired: onCaptchaRequired,
      );

      results.add(XxtSignAccountResult(account: account, result: result));
    }

    return XxtShareSignResult(results: results);
  }

  /// 清除登录状态
  void clearSession() {
    _cookie = null;
    _uid = null;
    _name = null;
    _fid = null;
    _uname = null;
  }
}
