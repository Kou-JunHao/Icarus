/// 应用更新服务
///
/// 从 GitHub 检查并下载应用更新
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新信息
class UpdateInfo {
  /// 最新版本号（如 "1.0.1"）
  final String version;

  /// 版本号数字（如 2）
  final int versionCode;

  /// 更新日志
  final String changelog;

  /// APK 下载链接
  final String downloadUrl;

  /// 文件大小（字节）
  final int fileSize;

  /// 发布时间
  final DateTime publishedAt;

  /// 是否为强制更新
  final bool isForceUpdate;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.changelog,
    required this.downloadUrl,
    required this.fileSize,
    required this.publishedAt,
    this.isForceUpdate = false,
  });

  /// 格式化文件大小
  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024)
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 下载进度回调
typedef DownloadProgressCallback = void Function(int received, int total);

/// 更新服务
class UpdateService {
  // GitHub 仓库信息 - 请替换为实际的 GitHub 用户名和仓库名
  static const String _owner = 'Kou-JunHao'; // 替换为实际的 GitHub 用户名
  static const String _repo = 'Icarus'; // 替换为实际的仓库名

  // 当前应用版本（从 package_info_plus 动态获取）
  static String _currentVersion = '';
  static String _currentBuildNumber = '';

  /// 获取当前版本号
  static String get currentVersion => _currentVersion;

  /// 获取当前构建号
  static String get currentBuildNumber => _currentBuildNumber;

  /// 初始化版本信息（应在应用启动时调用）
  static Future<void> initVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      _currentBuildNumber = packageInfo.buildNumber;
      debugPrint('应用版本: $_currentVersion+$_currentBuildNumber');
    } catch (e) {
      debugPrint('获取版本信息失败: $e');
      _currentVersion = '未知';
      _currentBuildNumber = '0';
    }
  }

  // 存储 key
  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckTime = 'update_last_check_time';

  // 平台通道，用于调用原生安装方法
  static const MethodChannel _channel = MethodChannel('uno.skkk.icarus/update');

  // 单例
  static UpdateService? _instance;
  factory UpdateService() => _instance ??= UpdateService._();
  UpdateService._();

  // HTTP 客户端
  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Icarus-App',
      },
    ),
  );

  // 当前下载任务
  CancelToken? _currentDownloadToken;

  /// 检查更新
  /// 返回 null 表示没有更新或已跳过
  Future<UpdateInfo?> checkForUpdate({bool ignoreSkipped = false}) async {
    try {
      // 获取 GitHub Releases 最新版本
      final response = await _dio.get(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );

      if (response.statusCode != 200) {
        debugPrint('检查更新失败: HTTP ${response.statusCode}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;

      // 解析版本信息
      final tagName = data['tag_name'] as String? ?? '';
      final version = tagName.replaceAll(RegExp(r'^v'), ''); // 移除 v 前缀
      final body = data['body'] as String? ?? '暂无更新说明';
      final publishedAtStr = data['published_at'] as String?;
      final assets = data['assets'] as List<dynamic>? ?? [];

      // 查找 APK 文件
      Map<String, dynamic>? apkAsset;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkAsset = asset as Map<String, dynamic>;
          break;
        }
      }

      if (apkAsset == null) {
        debugPrint('未找到 APK 文件');
        return null;
      }

      final downloadUrl = apkAsset['browser_download_url'] as String? ?? '';
      final fileSize = apkAsset['size'] as int? ?? 0;

      // 检查是否需要更新
      if (!_isNewerVersion(version, currentVersion)) {
        debugPrint('当前已是最新版本: $currentVersion');
        return null;
      }

      // 检查是否已跳过此版本
      if (!ignoreSkipped) {
        final skippedVersion = await _getSkippedVersion();
        if (skippedVersion == version) {
          debugPrint('用户已跳过版本: $version');
          return null;
        }
      }

      // 保存检查时间
      await _saveLastCheckTime();

      return UpdateInfo(
        version: version,
        versionCode: _parseVersionCode(version),
        changelog: body,
        downloadUrl: downloadUrl,
        fileSize: fileSize,
        publishedAt: publishedAtStr != null
            ? DateTime.parse(publishedAtStr)
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint('检查更新异常: $e');
      return null;
    }
  }

  /// 下载更新
  /// 返回下载的文件路径
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo, {
    DownloadProgressCallback? onProgress,
  }) async {
    try {
      // 获取下载目录 - 使用外部缓存目录以便安装器访问
      Directory dir;
      if (Platform.isAndroid) {
        dir =
            (await getExternalCacheDirectories())?.first ??
            await getApplicationCacheDirectory();
      } else {
        dir = await getApplicationCacheDirectory();
      }
      final fileName = 'icarus_${updateInfo.version}.apk';
      final filePath = '${dir.path}/$fileName';

      // 检查文件是否已存在
      final file = File(filePath);
      if (await file.exists()) {
        final existingSize = await file.length();
        if (existingSize == updateInfo.fileSize) {
          debugPrint('APK 文件已存在且完整');
          return filePath;
        }
        // 文件不完整，删除重新下载
        await file.delete();
      }

      // 创建取消令牌
      _currentDownloadToken = CancelToken();

      // 下载文件
      await _dio.download(
        updateInfo.downloadUrl,
        filePath,
        cancelToken: _currentDownloadToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received, total);
          }
        },
      );

      _currentDownloadToken = null;
      return filePath;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        debugPrint('下载已取消');
      } else {
        debugPrint('下载更新异常: $e');
      }
      return null;
    }
  }

  /// 取消下载
  void cancelDownload() {
    _currentDownloadToken?.cancel('用户取消下载');
    _currentDownloadToken = null;
  }

  /// 安装更新
  /// 返回是否成功触发安装
  Future<bool> installUpdate(String filePath) async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('当前平台不支持自动安装');
        return false;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('安装文件不存在: $filePath');
        return false;
      }

      // 尝试通过平台通道调用原生安装方法
      try {
        final result = await _channel.invokeMethod<bool>('installApk', {
          'filePath': filePath,
        });
        return result ?? false;
      } on MissingPluginException {
        // 平台通道未实现，使用备用方案
        debugPrint('平台通道未实现，返回文件路径供用户手动安装');
        return false;
      }
    } catch (e) {
      debugPrint('安装更新异常: $e');
      return false;
    }
  }

  /// 获取下载文件路径（用于手动安装提示）
  String getDownloadedFilePath(String filePath) {
    return filePath;
  }

  /// 跳过此版本
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySkippedVersion, version);
  }

  /// 获取已跳过的版本
  Future<String?> _getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySkippedVersion);
  }

  /// 比较版本号，返回 true 表示 newVersion 更新
  bool _isNewerVersion(String newVersion, String currentVersion) {
    final newParts = newVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final currentParts = currentVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    // 补齐位数
    while (newParts.length < 3) newParts.add(0);
    while (currentParts.length < 3) currentParts.add(0);

    for (int i = 0; i < 3; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// 解析版本号为数字
  int _parseVersionCode(String version) {
    final parts = version.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (parts.length < 3) parts.add(0);
    return parts[0] * 10000 + parts[1] * 100 + parts[2];
  }

  /// 保存最后检查时间
  Future<void> _saveLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastCheckTime, DateTime.now().toIso8601String());
  }

  /// 获取最后检查时间
  Future<DateTime?> getLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyLastCheckTime);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// 清理下载缓存
  Future<void> clearDownloadCache() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final files = dir.listSync();
      for (final file in files) {
        if (file is File && file.path.endsWith('.apk')) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('清理下载缓存异常: $e');
    }
  }

  void dispose() {
    cancelDownload();
    _dio.close();
  }
}
