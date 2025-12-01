/// 应用更新服务
///
/// 从 GitHub 检查并下载应用更新，兼容 Android 8-16
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载结果
class DownloadResult {
  final bool success;
  final String? filePath;
  final DownloadError? error;

  const DownloadResult.success(this.filePath) : success = true, error = null;

  const DownloadResult.failure(this.error) : success = false, filePath = null;
}

/// 下载错误类型
enum DownloadError {
  /// 无法获取下载目录
  directoryError,

  /// 网络连接失败
  networkError,

  /// 连接超时
  timeout,

  /// 服务器错误
  serverError,

  /// 存储空间不足
  storageError,

  /// 用户取消
  cancelled,

  /// 文件写入失败
  writeError,

  /// 未知错误
  unknown,
}

/// 获取错误提示信息
extension DownloadErrorMessage on DownloadError {
  String get message {
    switch (this) {
      case DownloadError.directoryError:
        return '无法访问下载目录，请检查存储权限';
      case DownloadError.networkError:
        return '网络连接失败，请检查网络设置';
      case DownloadError.timeout:
        return '连接超时，请稍后重试';
      case DownloadError.serverError:
        return '服务器错误，请稍后重试';
      case DownloadError.storageError:
        return '存储空间不足，请清理空间后重试';
      case DownloadError.cancelled:
        return '下载已取消';
      case DownloadError.writeError:
        return '文件写入失败，请检查存储权限';
      case DownloadError.unknown:
        return '下载失败，请重试';
    }
  }
}

/// 镜像源状态
enum MirrorStatus {
  /// 未检测
  unknown,

  /// 检测中
  checking,

  /// 可用
  available,

  /// 不可用
  unavailable,
}

/// 镜像源信息
class MirrorSource {
  /// 镜像源ID
  final String id;

  /// 镜像源名称
  final String name;

  /// 镜像源URL模板（{url}将被替换为原始URL）
  final String urlTemplate;

  /// 是否为内置镜像源
  final bool isBuiltin;

  /// 连接状态
  MirrorStatus status;

  /// 延迟（毫秒）
  int? latency;

  MirrorSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    this.isBuiltin = false,
    this.status = MirrorStatus.unknown,
    this.latency,
  });

  /// 转换下载URL
  String transformUrl(String originalUrl) {
    if (urlTemplate.contains('{url}')) {
      return urlTemplate.replaceAll('{url}', originalUrl);
    }
    // 对于直接替换域名的模式
    if (urlTemplate.contains('github.com')) {
      return originalUrl;
    }
    // 提取 GitHub release 路径
    final uri = Uri.parse(originalUrl);
    if (uri.host == 'github.com' || uri.host.contains('githubusercontent')) {
      return urlTemplate.replaceAll('{path}', uri.path);
    }
    return originalUrl;
  }

  /// 从JSON创建
  factory MirrorSource.fromJson(Map<String, dynamic> json) {
    return MirrorSource(
      id: json['id'] as String,
      name: json['name'] as String,
      urlTemplate: json['urlTemplate'] as String,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
    );
  }

  /// 转为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'urlTemplate': urlTemplate,
      'isBuiltin': isBuiltin,
    };
  }

  /// 复制
  MirrorSource copyWith({
    String? id,
    String? name,
    String? urlTemplate,
    bool? isBuiltin,
    MirrorStatus? status,
    int? latency,
  }) {
    return MirrorSource(
      id: id ?? this.id,
      name: name ?? this.name,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      status: status ?? this.status,
      latency: latency ?? this.latency,
    );
  }
}

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
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 下载进度回调
typedef DownloadProgressCallback = void Function(int received, int total);

/// 下载状态
enum DownloadState {
  /// 空闲
  idle,

  /// 下载中
  downloading,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已取消
  cancelled,
}

/// 下载进度信息
class DownloadProgress {
  final DownloadState state;
  final String? version;
  final int received;
  final int total;
  final double progress;
  final String? filePath;
  final DownloadError? error;

  const DownloadProgress({
    required this.state,
    this.version,
    this.received = 0,
    this.total = 0,
    this.progress = 0.0,
    this.filePath,
    this.error,
  });

  factory DownloadProgress.idle() =>
      const DownloadProgress(state: DownloadState.idle);

  factory DownloadProgress.downloading({
    required String version,
    required int received,
    required int total,
  }) => DownloadProgress(
    state: DownloadState.downloading,
    version: version,
    received: received,
    total: total,
    progress: total > 0 ? received / total : 0.0,
  );

  factory DownloadProgress.completed({
    required String version,
    required String filePath,
    required int total,
  }) => DownloadProgress(
    state: DownloadState.completed,
    version: version,
    filePath: filePath,
    received: total,
    total: total,
    progress: 1.0,
  );

  factory DownloadProgress.failed({
    required String version,
    required DownloadError error,
  }) => DownloadProgress(
    state: DownloadState.failed,
    version: version,
    error: error,
  );

  factory DownloadProgress.cancelled({String? version}) =>
      DownloadProgress(state: DownloadState.cancelled, version: version);
}

/// 更新服务
class UpdateService {
  // GitHub 仓库信息
  static const String _owner = 'Kou-JunHao';
  static const String _repo = 'Icarus';

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
    } catch (e) {
      _currentVersion = '未知';
      _currentBuildNumber = '0';
    }
  }

  // 存储 key
  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckTime = 'update_last_check_time';
  static const String _keyCustomMirrors = 'update_custom_mirrors';
  static const String _keySelectedMirror = 'update_selected_mirror';
  static const String _keyLastDownloadedVersion =
      'update_last_downloaded_version';

  /// 内置镜像源列表
  static final List<MirrorSource> _builtinMirrors = [
    MirrorSource(
      id: 'github',
      name: 'GitHub (源站)',
      urlTemplate: '{url}',
      isBuiltin: true,
    ),
    MirrorSource(
      id: 'ghproxy',
      name: 'GitHub Proxy',
      urlTemplate: 'https://ghproxy.cc/{url}',
      isBuiltin: true,
    ),
    MirrorSource(
      id: 'ghfast',
      name: 'GitHub Fast',
      urlTemplate: 'https://gh.noki.icu/{url}',
      isBuiltin: true,
    ),
    MirrorSource(
      id: 'jsdelivr',
      name: 'jsDelivr CDN',
      urlTemplate: 'https://cdn.jsdelivr.net/gh/$_owner/$_repo@{tag}/{file}',
      isBuiltin: true,
    ),
  ];

  // 平台通道，用于调用原生方法
  static const MethodChannel _channel = MethodChannel('uno.skkk.icarus/update');

  // 单例
  static UpdateService? _instance;
  factory UpdateService() => _instance ??= UpdateService._();
  UpdateService._();

  // HTTP 客户端 - 用于 API 请求
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

  // 当前选择的镜像源
  String _selectedMirrorId = 'github';

  // 镜像源列表（包含内置和自定义）
  List<MirrorSource> _mirrors = [];

  // 下载进度流控制器
  final StreamController<DownloadProgress> _downloadProgressController =
      StreamController<DownloadProgress>.broadcast();

  // 当前下载进度
  DownloadProgress _currentProgress = DownloadProgress.idle();

  /// 下载进度流
  Stream<DownloadProgress> get downloadProgressStream =>
      _downloadProgressController.stream;

  /// 获取当前下载进度
  DownloadProgress get currentDownloadProgress => _currentProgress;

  /// 是否正在下载
  bool get isDownloading => _currentProgress.state == DownloadState.downloading;

  /// 更新下载进度
  void _updateProgress(DownloadProgress progress) {
    _currentProgress = progress;
    _downloadProgressController.add(progress);
  }

  /// 获取所有镜像源
  List<MirrorSource> get mirrors => List.unmodifiable(_mirrors);

  /// 获取当前选择的镜像源ID
  String get selectedMirrorId => _selectedMirrorId;

  /// 获取当前选择的镜像源
  MirrorSource? get selectedMirror {
    try {
      return _mirrors.firstWhere((m) => m.id == _selectedMirrorId);
    } catch (_) {
      return _mirrors.isNotEmpty ? _mirrors.first : null;
    }
  }

  /// 初始化镜像源
  Future<void> initMirrors() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载内置镜像源
    _mirrors = _builtinMirrors.map((m) => m.copyWith()).toList();

    // 加载自定义镜像源
    final customMirrorsJson = prefs.getString(_keyCustomMirrors);
    if (customMirrorsJson != null) {
      try {
        final List<dynamic> customList = json.decode(customMirrorsJson);
        for (final item in customList) {
          _mirrors.add(MirrorSource.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    // 加载选择的镜像源
    _selectedMirrorId = prefs.getString(_keySelectedMirror) ?? 'github';
  }

  /// 设置选择的镜像源
  Future<void> setSelectedMirror(String mirrorId) async {
    _selectedMirrorId = mirrorId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedMirror, mirrorId);
  }

  /// 添加自定义镜像源
  Future<bool> addCustomMirror(MirrorSource mirror) async {
    // 检查ID是否已存在
    if (_mirrors.any((m) => m.id == mirror.id)) {
      return false;
    }

    _mirrors.add(mirror);
    await _saveCustomMirrors();
    return true;
  }

  /// 更新自定义镜像源
  Future<bool> updateCustomMirror(MirrorSource mirror) async {
    final index = _mirrors.indexWhere((m) => m.id == mirror.id && !m.isBuiltin);
    if (index == -1) return false;

    _mirrors[index] = mirror;
    await _saveCustomMirrors();
    return true;
  }

  /// 删除自定义镜像源
  Future<bool> removeCustomMirror(String mirrorId) async {
    final index = _mirrors.indexWhere((m) => m.id == mirrorId && !m.isBuiltin);
    if (index == -1) return false;

    _mirrors.removeAt(index);
    await _saveCustomMirrors();

    // 如果删除的是当前选择的，切换到默认
    if (_selectedMirrorId == mirrorId) {
      await setSelectedMirror('github');
    }
    return true;
  }

  /// 保存自定义镜像源
  Future<void> _saveCustomMirrors() async {
    final prefs = await SharedPreferences.getInstance();
    final customMirrors = _mirrors.where((m) => !m.isBuiltin).toList();
    final jsonStr = json.encode(customMirrors.map((m) => m.toJson()).toList());
    await prefs.setString(_keyCustomMirrors, jsonStr);
  }

  /// 检测镜像源连通性
  Future<void> checkMirrorConnectivity(String mirrorId, String testUrl) async {
    final index = _mirrors.indexWhere((m) => m.id == mirrorId);
    if (index == -1) return;

    _mirrors[index].status = MirrorStatus.checking;

    final mirror = _mirrors[index];
    final transformedUrl = mirror.transformUrl(testUrl);

    final testDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    final stopwatch = Stopwatch()..start();

    try {
      final response = await testDio.head(
        transformedUrl,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      stopwatch.stop();

      if (response.statusCode != null && response.statusCode! < 400) {
        _mirrors[index].status = MirrorStatus.available;
        _mirrors[index].latency = stopwatch.elapsedMilliseconds;
      } else {
        _mirrors[index].status = MirrorStatus.unavailable;
        _mirrors[index].latency = null;
      }
    } catch (_) {
      stopwatch.stop();
      _mirrors[index].status = MirrorStatus.unavailable;
      _mirrors[index].latency = null;
    } finally {
      testDio.close();
    }
  }

  /// 批量检测所有镜像源连通性
  Future<void> checkAllMirrorsConnectivity(String testUrl) async {
    // 并行检测所有镜像源
    await Future.wait(
      _mirrors.map((m) => checkMirrorConnectivity(m.id, testUrl)),
    );
  }

  /// 检查存储权限（Android 9 及以下需要）
  Future<bool> checkStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'checkStoragePermission',
      );
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  /// 请求存储权限（Android 9 及以下需要）
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestStoragePermission',
      );
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  /// 获取 APK 下载保存目录
  Future<String?> _getDownloadDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getDownloadDir');
    } catch (e) {
      return null;
    }
  }

  /// 检查更新
  /// 返回 null 表示没有更新或已跳过
  Future<UpdateInfo?> checkForUpdate({bool ignoreSkipped = false}) async {
    try {
      // 检查是否需要清理旧的 APK 文件
      // 如果上次下载的版本与当前运行版本一致，说明更新已成功安装
      await _cleanupOldApkIfNeeded();

      final response = await _dio.get(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );

      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final version = tagName.replaceAll(RegExp(r'^v'), '');
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

      if (apkAsset == null) return null;

      final downloadUrl = apkAsset['browser_download_url'] as String? ?? '';
      final fileSize = apkAsset['size'] as int? ?? 0;

      if (downloadUrl.isEmpty) return null;

      // 检查是否需要更新
      if (!_isNewerVersion(version, currentVersion)) return null;

      // 检查是否已跳过此版本
      if (!ignoreSkipped) {
        final skippedVersion = await _getSkippedVersion();
        if (skippedVersion == version) return null;
      }

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
      return null;
    }
  }

  /// 下载更新
  /// 返回下载结果，包含文件路径或错误信息
  /// [showNotification] 是否显示通知栏进度（支持后台下载）
  /// [useNativeService] 是否使用原生下载服务（支持后台下载，不会被系统中断）
  Future<DownloadResult> downloadUpdateWithResult(
    UpdateInfo updateInfo, {
    DownloadProgressCallback? onProgress,
    bool showNotification = true,
    bool useNativeService = true,
  }) async {
    if (!Platform.isAndroid) {
      return const DownloadResult.failure(DownloadError.unknown);
    }

    // 如果已经在下载同一版本，直接返回
    if (isDownloading && _currentProgress.version == updateInfo.version) {
      return const DownloadResult.failure(DownloadError.unknown);
    }

    try {
      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();
      if (downloadDir == null || downloadDir.isEmpty) {
        _updateProgress(
          DownloadProgress.failed(
            version: updateInfo.version,
            error: DownloadError.directoryError,
          ),
        );
        return const DownloadResult.failure(DownloadError.directoryError);
      }

      final fileName = 'icarus_${updateInfo.version}.apk';
      final filePath = '$downloadDir/$fileName';

      // 检查文件是否已存在且完整
      final file = File(filePath);
      if (await file.exists()) {
        final existingSize = await file.length();
        final sizeDiff = (existingSize - updateInfo.fileSize).abs();
        final threshold = updateInfo.fileSize * 0.01;

        if (sizeDiff < threshold && existingSize > 0) {
          _updateProgress(
            DownloadProgress.completed(
              version: updateInfo.version,
              filePath: filePath,
              total: updateInfo.fileSize,
            ),
          );
          return DownloadResult.success(filePath);
        }
        // 删除不完整的文件
        try {
          await file.delete();
        } catch (e) {
          try {
            await file.writeAsBytes([]);
            await file.delete();
          } catch (_) {
            _updateProgress(
              DownloadProgress.failed(
                version: updateInfo.version,
                error: DownloadError.writeError,
              ),
            );
            return const DownloadResult.failure(DownloadError.writeError);
          }
        }
      }

      // 确保目录存在
      final dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 获取镜像源转换后的URL
      String downloadUrl = updateInfo.downloadUrl;
      if (_mirrors.isEmpty) {
        await initMirrors();
      }
      final mirror = selectedMirror;
      if (mirror != null && mirror.id != 'github') {
        downloadUrl = mirror.transformUrl(updateInfo.downloadUrl);
      }

      // 使用原生下载服务（推荐，支持后台下载）
      if (useNativeService) {
        return _downloadWithNativeService(
          downloadUrl,
          filePath,
          updateInfo.version,
          updateInfo.fileSize,
          onProgress,
        );
      }

      // 使用 Dart Dio 下载（应用进入后台可能被中断）
      return _downloadWithDio(
        downloadUrl,
        filePath,
        updateInfo,
        onProgress,
        showNotification,
      );
    } on FileSystemException catch (e) {
      _updateProgress(
        DownloadProgress.failed(
          version: updateInfo.version,
          error: DownloadError.storageError,
        ),
      );
      debugPrint('存储错误: $e');
      return const DownloadResult.failure(DownloadError.storageError);
    } catch (e) {
      _currentDownloadToken = null;
      await _cancelDownloadNotification();
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _updateProgress(
          DownloadProgress.cancelled(version: updateInfo.version),
        );
        return const DownloadResult.failure(DownloadError.cancelled);
      }
      _updateProgress(
        DownloadProgress.failed(
          version: updateInfo.version,
          error: DownloadError.unknown,
        ),
      );
      return const DownloadResult.failure(DownloadError.unknown);
    }
  }

  /// 使用原生服务下载（支持后台下载）
  Future<DownloadResult> _downloadWithNativeService(
    String url,
    String filePath,
    String version,
    int fileSize,
    DownloadProgressCallback? onProgress,
  ) async {
    try {
      // 更新状态为下载中
      _updateProgress(
        DownloadProgress.downloading(
          version: version,
          received: 0,
          total: fileSize,
        ),
      );

      // 启动原生下载服务
      await _channel.invokeMethod('startDownloadService', {
        'url': url,
        'filePath': filePath,
        'version': version,
        'fileSize': fileSize,
      });

      // 轮询检查下载状态
      const checkInterval = Duration(milliseconds: 500);
      const maxWaitTime = Duration(minutes: 30);
      final startTime = DateTime.now();

      while (true) {
        await Future.delayed(checkInterval);

        // 检查是否超时
        if (DateTime.now().difference(startTime) > maxWaitTime) {
          _updateProgress(
            DownloadProgress.failed(
              version: version,
              error: DownloadError.timeout,
            ),
          );
          return const DownloadResult.failure(DownloadError.timeout);
        }

        // 优先检查原生端是否已标记下载完成
        final completedResult = await _checkDownloadCompleted();
        if (completedResult != null) {
          // 使用原生端返回的路径，如果为空则使用传入的 filePath
          final actualPath = completedResult.isNotEmpty
              ? completedResult
              : filePath;
          // 保存已下载的版本信息，用于后续清理
          await _saveLastDownloadedVersion(version);
          _updateProgress(
            DownloadProgress.completed(
              version: version,
              filePath: actualPath,
              total: fileSize,
            ),
          );
          return DownloadResult.success(actualPath);
        }

        // 检查服务是否还在运行
        final isRunning =
            await _channel.invokeMethod<bool>('isDownloadServiceRunning') ??
            false;

        // 检查文件是否已下载完成
        final file = File(filePath);
        if (await file.exists()) {
          final downloadedSize = await file.length();

          // 更新进度
          _updateProgress(
            DownloadProgress.downloading(
              version: version,
              received: downloadedSize,
              total: fileSize,
            ),
          );
          onProgress?.call(downloadedSize, fileSize);

          // 检查是否下载完成
          final sizeDiff = (downloadedSize - fileSize).abs();
          final threshold = fileSize * 0.01; // 1% 误差容忍

          if (!isRunning && downloadedSize > 0) {
            if (sizeDiff < threshold) {
              // 下载完成，保存已下载的版本信息
              await _saveLastDownloadedVersion(version);
              _updateProgress(
                DownloadProgress.completed(
                  version: version,
                  filePath: filePath,
                  total: fileSize,
                ),
              );
              return DownloadResult.success(filePath);
            } else {
              // 服务已停止但文件不完整，查询具体错误类型
              final error = await _getLastDownloadError();
              _updateProgress(
                DownloadProgress.failed(version: version, error: error),
              );
              return DownloadResult.failure(error);
            }
          }
        } else if (!isRunning) {
          // 服务已停止且没有文件，查询具体错误类型
          final error = await _getLastDownloadError();
          _updateProgress(
            DownloadProgress.failed(version: version, error: error),
          );
          return DownloadResult.failure(error);
        }
      }
    } catch (e) {
      debugPrint('原生下载服务错误: $e');
      _updateProgress(
        DownloadProgress.failed(version: version, error: DownloadError.unknown),
      );
      return const DownloadResult.failure(DownloadError.unknown);
    }
  }

  /// 使用 Dart Dio 下载（旧方式，应用进入后台可能被中断）
  Future<DownloadResult> _downloadWithDio(
    String downloadUrl,
    String filePath,
    UpdateInfo updateInfo,
    DownloadProgressCallback? onProgress,
    bool showNotification,
  ) async {
    // 创建取消令牌
    _currentDownloadToken = CancelToken();

    // 更新状态为下载中
    _updateProgress(
      DownloadProgress.downloading(
        version: updateInfo.version,
        received: 0,
        total: updateInfo.fileSize,
      ),
    );

    // 显示初始通知
    if (showNotification) {
      await _showDownloadNotification(
        0,
        100,
        '正在下载更新 v${updateInfo.version}',
        '准备下载...',
      );
    }

    // 下载文件
    final error = await _downloadFileWithError(
      downloadUrl,
      filePath,
      updateInfo.fileSize,
      (received, total) {
        // 更新进度流
        _updateProgress(
          DownloadProgress.downloading(
            version: updateInfo.version,
            received: received,
            total: total,
          ),
        );
        onProgress?.call(received, total);
        // 更新通知栏进度
        if (showNotification) {
          final percent = total > 0 ? (received * 100 ~/ total) : 0;
          final receivedMB = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMB = (total / 1024 / 1024).toStringAsFixed(1);
          _updateDownloadNotification(
            percent,
            100,
            '正在下载更新 v${updateInfo.version}',
            '$receivedMB MB / $totalMB MB ($percent%)',
          );
        }
      },
    );

    _currentDownloadToken = null;

    if (error != null) {
      if (showNotification) {
        await _cancelDownloadNotification();
      }
      _updateProgress(
        DownloadProgress.failed(version: updateInfo.version, error: error),
      );
      return DownloadResult.failure(error);
    }

    // 验证文件
    if (await File(filePath).exists()) {
      final downloadedSize = await File(filePath).length();
      if (downloadedSize > 0) {
        // 显示完成通知
        if (showNotification) {
          await _completeDownloadNotification(
            filePath,
            '下载完成',
            '点击安装 Icarus v${updateInfo.version}',
          );
        }
        _updateProgress(
          DownloadProgress.completed(
            version: updateInfo.version,
            filePath: filePath,
            total: updateInfo.fileSize,
          ),
        );
        return DownloadResult.success(filePath);
      }
    }

    if (showNotification) {
      await _cancelDownloadNotification();
    }
    _updateProgress(
      DownloadProgress.failed(
        version: updateInfo.version,
        error: DownloadError.writeError,
      ),
    );
    return const DownloadResult.failure(DownloadError.writeError);
  }

  /// 下载文件，返回错误类型（null 表示成功）
  Future<DownloadError?> _downloadFileWithError(
    String url,
    String filePath,
    int expectedSize,
    DownloadProgressCallback? onProgress,
  ) async {
    try {
      // 确保文件不存在
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      final downloadDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(minutes: 30),
          followRedirects: true,
          maxRedirects: 10,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': '*/*',
          },
        ),
      );

      await downloadDio.download(
        url,
        filePath,
        cancelToken: _currentDownloadToken,
        deleteOnError: true,
        options: Options(
          followRedirects: true,
          maxRedirects: 10,
          validateStatus: (status) => status != null && status < 400,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received, total);
          } else {
            onProgress?.call(received, expectedSize);
          }
        },
      );

      downloadDio.close();
      return null; // 成功
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return DownloadError.cancelled;
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return DownloadError.timeout;
      } else if (e.type == DioExceptionType.connectionError) {
        return DownloadError.networkError;
      } else if (e.response?.statusCode != null &&
          e.response!.statusCode! >= 500) {
        return DownloadError.serverError;
      }
      return DownloadError.networkError;
    } on FileSystemException {
      return DownloadError.storageError;
    } catch (e) {
      if (e.toString().contains('No space left') ||
          e.toString().contains('ENOSPC')) {
        return DownloadError.storageError;
      }
      return DownloadError.unknown;
    }
  }

  /// 下载更新（兼容旧API）
  @Deprecated('请使用 downloadUpdateWithResult 以获取详细错误信息')
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo, {
    DownloadProgressCallback? onProgress,
  }) async {
    final result = await downloadUpdateWithResult(
      updateInfo,
      onProgress: onProgress,
    );
    return result.filePath;
  }

  /// 取消下载
  void cancelDownload() {
    final version = _currentProgress.version;

    // 取消 Dio 下载
    _currentDownloadToken?.cancel('用户取消下载');
    _currentDownloadToken = null;

    // 取消原生下载服务
    _cancelNativeDownloadService();

    // 更新状态
    if (version != null && version.isNotEmpty) {
      _updateProgress(DownloadProgress.cancelled(version: version));
    }
    // 取消通知
    _cancelDownloadNotification();
  }

  /// 取消原生下载服务
  Future<void> _cancelNativeDownloadService() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelDownloadService');
    } catch (_) {}
  }

  /// 检查原生端是否已标记下载完成
  /// 返回文件路径表示完成，返回 null 表示未完成
  Future<String?> _checkDownloadCompleted() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'isDownloadCompleted',
      );
      if (result != null && result['completed'] == true) {
        return result['filePath'] as String?;
      }
    } catch (e) {
      debugPrint('检查下载完成状态失败: $e');
    }
    return null;
  }

  /// 从原生端获取最后的下载错误类型
  Future<DownloadError> _getLastDownloadError() async {
    if (!Platform.isAndroid) return DownloadError.unknown;
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getLastDownloadError',
      );
      if (result != null) {
        final errorType = result['errorType'] as String?;
        debugPrint('原生下载错误类型: $errorType');
        return _parseNativeErrorType(errorType);
      }
    } catch (e) {
      debugPrint('获取原生下载错误失败: $e');
    }
    return DownloadError.unknown;
  }

  /// 将原生错误类型字符串转换为 DownloadError 枚举
  DownloadError _parseNativeErrorType(String? errorType) {
    switch (errorType) {
      case 'network_error':
        return DownloadError.networkError;
      case 'timeout':
        return DownloadError.timeout;
      case 'server_error':
        return DownloadError.serverError;
      case 'storage_error':
        return DownloadError.storageError;
      case 'write_error':
        return DownloadError.writeError;
      case 'cancelled':
        return DownloadError.cancelled;
      case 'unknown':
      default:
        return DownloadError.unknown;
    }
  }

  /// 重置下载状态
  void resetDownloadState() {
    _updateProgress(DownloadProgress.idle());
  }

  /// 显示下载进度通知
  Future<void> _showDownloadNotification(
    int progress,
    int total,
    String title,
    String content,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showDownloadNotification', {
        'progress': progress,
        'total': total,
        'title': title,
        'content': content,
      });
    } catch (_) {}
  }

  /// 更新下载进度通知
  Future<void> _updateDownloadNotification(
    int progress,
    int total,
    String title,
    String content,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updateDownloadNotification', {
        'progress': progress,
        'total': total,
        'title': title,
        'content': content,
      });
    } catch (_) {}
  }

  /// 完成下载通知
  Future<void> _completeDownloadNotification(
    String? filePath,
    String title,
    String content,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('completeDownloadNotification', {
        'filePath': filePath,
        'title': title,
        'content': content,
      });
    } catch (_) {}
  }

  /// 取消下载通知
  Future<void> _cancelDownloadNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelDownloadNotification');
    } catch (_) {}
  }

  /// 检查通知权限
  Future<bool> checkNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'checkNotificationPermission',
      );
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 请求通知权限
  Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  /// 安装更新
  /// 返回是否成功触发安装
  Future<bool> installUpdate(String filePath) async {
    if (!Platform.isAndroid) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final result = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
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

  /// 保存已下载的版本号
  Future<void> _saveLastDownloadedVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastDownloadedVersion, version);
  }

  /// 获取已下载的版本号
  Future<String?> _getLastDownloadedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastDownloadedVersion);
  }

  /// 清除已下载版本记录
  Future<void> _clearLastDownloadedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastDownloadedVersion);
  }

  /// 检查并清理旧的 APK 文件
  /// 只有当上次下载的版本与当前运行版本一致时才清理
  /// （说明用户已经成功安装了更新）
  Future<void> _cleanupOldApkIfNeeded() async {
    if (!Platform.isAndroid) return;

    try {
      final lastDownloadedVersion = await _getLastDownloadedVersion();
      if (lastDownloadedVersion == null) return;

      // 如果当前版本 >= 上次下载的版本，说明更新已安装成功
      if (!_isNewerVersion(lastDownloadedVersion, currentVersion)) {
        debugPrint('检测到更新已安装成功，清理旧的 APK 文件');
        await clearDownloadCache();
        await _clearLastDownloadedVersion();
      }
    } catch (e) {
      debugPrint('清理旧 APK 失败: $e');
    }
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
    while (newParts.length < 3) {
      newParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// 解析版本号为数字
  int _parseVersionCode(String version) {
    final parts = version.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
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

  /// 清理下载的 APK 文件
  Future<void> clearDownloadCache() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('clearApkCache');
    } catch (_) {}
  }

  void dispose() {
    cancelDownload();
    _dio.close();
  }
}
