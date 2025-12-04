/// 学习通签到页面
/// 支持普通签到、位置签到、密码签到等多种签到类型
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/xxt_sign.dart';
import '../models/xxt_activity.dart';
import '../services/xxt_sign_service.dart';
import '../services/xxt_sign_account_manager.dart';

/// 签到页面
class XxtSignScreen extends StatefulWidget {
  /// 签到活动
  final XxtActivity activity;

  /// 课程活动信息
  final XxtCourseActivities courseActivity;

  const XxtSignScreen({
    super.key,
    required this.activity,
    required this.courseActivity,
  });

  @override
  State<XxtSignScreen> createState() => _XxtSignScreenState();
}

class _XxtSignScreenState extends State<XxtSignScreen> {
  final XxtSignService _signService = XxtSignService();
  final XxtSignAccountManager _accountManager = XxtSignAccountManager();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _encController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingDetails = true;
  XxtSignActivity? _signActivity;
  String? _error;
  XxtSignResult? _result;
  XxtShareSignResult? _shareResult;

  // 位置信息
  XxtLocation? _currentLocation;
  bool _isGettingLocation = false;

  // 分享签到
  bool _enableShareSign = false;
  List<XxtSignAccount> _selectedAccounts = [];

  // 拍照签到
  Uint8List? _photoData;
  bool _isUploadingPhoto = false;

  // 已签到状态
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _accountManager.init();
    _loadSignDetails();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _encController.dispose();
    super.dispose();
  }

  /// 加载签到详情
  Future<void> _loadSignDetails() async {
    if (widget.activity.activeId == null) {
      setState(() {
        _isLoadingDetails = false;
        _error = '活动 ID 无效';
      });
      return;
    }

    setState(() {
      _isLoadingDetails = true;
      _error = null;
    });

    try {
      final signActivity = await _signService.getSignActivityInfo(
        widget.activity.activeId!,
        widget.courseActivity.courseName,
        widget.courseActivity.courseId,
        widget.courseActivity.classId,
      );

      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _signActivity = signActivity;
          if (signActivity == null) {
            _error = '获取签到详情失败';
          }
        });
      }

      // 如果是位置签到，自动获取位置
      if (signActivity?.signType == XxtSignType.location) {
        _getCurrentLocation();
      }

      // 根据签到类型设置分享签到默认状态
      // 拍照签到默认关闭分享，其他类型默认开启
      if (signActivity != null) {
        _enableShareSign = signActivity.signType != XxtSignType.photo;
        if (_enableShareSign && _selectedAccounts.isEmpty) {
          _selectedAccounts = List.from(_accountManager.enabledAccounts);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
          _error = '加载失败: $e';
        });
      }
    }
  }

  /// 获取当前位置
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      // 检查位置服务
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请开启位置服务')));
        }
        setState(() {
          _isGettingLocation = false;
        });
        return;
      }

      // 检查权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('位置权限被拒绝')));
          }
          setState(() {
            _isGettingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('位置权限被永久拒绝，请在设置中开启')));
        }
        setState(() {
          _isGettingLocation = false;
        });
        return;
      }

      // 获取位置
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (mounted) {
        setState(() {
          _currentLocation = XxtLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            address: '当前位置',
          );
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取位置失败: $e')));
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  /// 执行签到
  Future<void> _doSign() async {
    if (_signActivity == null) return;

    // 验证必要参数
    if (_signActivity!.signType == XxtSignType.location &&
        _currentLocation == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先获取位置')));
      return;
    }

    if ((_signActivity!.signType == XxtSignType.password ||
            _signActivity!.signType == XxtSignType.gesture) &&
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入签到码')));
      return;
    }

    if (_signActivity!.signType == XxtSignType.qrcode &&
        _encController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入二维码内容')));
      return;
    }

    if (_signActivity!.signType == XxtSignType.photo && _photoData == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先拍摄或选择照片')));
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 如果是密码/手势签到，先验证
      if (_signActivity!.signType == XxtSignType.password ||
          _signActivity!.signType == XxtSignType.gesture) {
        final isValid = await _signService.checkSignCode(
          _signActivity!.activeId,
          _passwordController.text,
        );
        if (!isValid) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _error = '签到码错误';
            });
          }
          return;
        }
      }

      // 检查是否启用分享签到
      if (_enableShareSign) {
        // 分享签到模式
        final allResults = <XxtSignAccountResult>[];

        // 对于二维码签到，先为分享账号签到（因为 enc 可能过期）
        // 当前用户已登录，签到最快，放到最后
        final isQrcodeSign = _signActivity!.signType == XxtSignType.qrcode;

        if (isQrcodeSign && _selectedAccounts.isNotEmpty) {
          // 二维码签到：先为分享账号签到
          final shareResult = await _signService.shareSign(
            _selectedAccounts,
            _signActivity!,
            location: _currentLocation,
            photo: _photoData,
            signCode: _passwordController.text.isNotEmpty
                ? _passwordController.text
                : null,
            enc: _encController.text.isNotEmpty ? _encController.text : null,
            onCaptchaRequired: _handleCaptchaRequired,
            onProgress: (current, total, account) {
              debugPrint('分享签到进度: $current/$total - ${account.displayName}');
            },
          );
          allResults.addAll(shareResult.results);

          // 然后为当前用户签到
          final currentUserResult = await _signService.signWithCaptchaRetry(
            _signActivity!,
            location: _currentLocation,
            photo: _photoData,
            signCode: _passwordController.text.isNotEmpty
                ? _passwordController.text
                : null,
            enc: _encController.text.isNotEmpty ? _encController.text : null,
            onCaptchaRequired: _handleCaptchaRequired,
          );

          final currentUserAccount = XxtSignAccount(
            id: 'current_user',
            username: _signService.currentUserName ?? '当前用户',
            password: '',
            nickname: '我（当前用户）',
            createdAt: DateTime.now(),
          );
          // 将当前用户结果插入到开头
          allResults.insert(
            0,
            XxtSignAccountResult(
              account: currentUserAccount,
              result: currentUserResult,
            ),
          );
        } else {
          // 非二维码签到：先为当前用户签到
          final currentUserResult = await _signService.signWithCaptchaRetry(
            _signActivity!,
            location: _currentLocation,
            photo: _photoData,
            signCode: _passwordController.text.isNotEmpty
                ? _passwordController.text
                : null,
            enc: _encController.text.isNotEmpty ? _encController.text : null,
            onCaptchaRequired: _handleCaptchaRequired,
          );

          final currentUserAccount = XxtSignAccount(
            id: 'current_user',
            username: _signService.currentUserName ?? '当前用户',
            password: '',
            nickname: '我（当前用户）',
            createdAt: DateTime.now(),
          );
          allResults.add(
            XxtSignAccountResult(
              account: currentUserAccount,
              result: currentUserResult,
            ),
          );

          // 如果有选中的其他账号，继续为它们签到
          if (_selectedAccounts.isNotEmpty) {
            final shareResult = await _signService.shareSign(
              _selectedAccounts,
              _signActivity!,
              location: _currentLocation,
              photo: _photoData,
              signCode: _passwordController.text.isNotEmpty
                  ? _passwordController.text
                  : null,
              enc: _encController.text.isNotEmpty ? _encController.text : null,
              onCaptchaRequired: _handleCaptchaRequired,
              onProgress: (current, total, account) {
                debugPrint('分享签到进度: $current/$total - ${account.displayName}');
              },
            );
            allResults.addAll(shareResult.results);
          }
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
            _shareResult = XxtShareSignResult(results: allResults);
          });
        }
      } else {
        // 单账号签到
        final result = await _signService.signWithCaptchaRetry(
          _signActivity!,
          location: _currentLocation,
          photo: _photoData,
          signCode: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          enc: _encController.text.isNotEmpty ? _encController.text : null,
          onCaptchaRequired: _handleCaptchaRequired,
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
            _result = result;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '签到失败: $e';
        });
      }
    }
  }

  /// 处理验证码请求
  Future<String?> _handleCaptchaRequired(XxtCaptchaData captchaData) async {
    if (!mounted) return null;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CaptchaDialog(
        captchaData: captchaData,
        signActivity: _signActivity!,
        signService: _signService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('签到'), centerTitle: true),
      body: _isLoadingDetails
          ? _buildLoadingView(colorScheme)
          : _error != null && _signActivity == null
          ? _buildErrorView(theme, colorScheme)
          : _shareResult != null
          ? _buildShareResultView(theme, colorScheme)
          : _result != null
          ? _buildResultView(theme, colorScheme)
          : _buildSignForm(theme, colorScheme),
    );
  }

  Widget _buildLoadingView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            '加载签到详情...',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? '未知错误',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadSignDetails,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(ThemeData theme, ColorScheme colorScheme) {
    final isSuccess = _result?.success ?? false;
    final iconColor = isSuccess ? Colors.green : colorScheme.error;
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.error_rounded;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 60, color: iconColor),
            ),
            const SizedBox(height: 24),
            Text(
              _result?.message ?? (isSuccess ? '签到成功' : '签到失败'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.courseActivity.courseName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            if (isSuccess)
              FilledButton(
                onPressed: () => Navigator.pop(context, _result),
                child: const Text('返回'),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _result = null;
                        _error = null;
                      });
                    },
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _result),
                    child: const Text('返回'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareResultView(ThemeData theme, ColorScheme colorScheme) {
    final allSuccess = _shareResult!.allSuccess;
    final successCount = _shareResult!.successCount;
    final failedCount = _shareResult!.failedCount;
    final total = _shareResult!.results.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 总体结果
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: allSuccess
                  ? Colors.green.withValues(alpha: 0.1)
                  : colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  allSuccess
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 64,
                  color: allSuccess ? Colors.green : colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  allSuccess ? '分享签到完成' : '部分签到失败',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '成功 $successCount / 失败 $failedCount / 共 $total 人',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 详细结果
          ...(_shareResult!.results.map(
            (r) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: r.result.success
                      ? Colors.green.withValues(alpha: 0.1)
                      : colorScheme.errorContainer,
                  child: Icon(
                    r.result.success
                        ? Icons.check_rounded
                        : Icons.close_rounded,
                    color: r.result.success
                        ? Colors.green
                        : colorScheme.onErrorContainer,
                  ),
                ),
                title: Text(r.account.displayName),
                subtitle: Text(
                  r.result.message ?? (r.result.success ? '签到成功' : '签到失败'),
                  style: TextStyle(
                    color: r.result.success
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                  ),
                ),
              ),
            ),
          )),
          const SizedBox(height: 16),
          // 按钮区域
          if (allSuccess)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _shareResult = null;
                        _result = null;
                        _error = null;
                      });
                    },
                    child: const Text('重试'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSignForm(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 签到信息卡片
          _buildInfoCard(theme, colorScheme),

          // 签退提示
          if (_signActivity?.signOutInfo?.shouldShowTips == true) ...[
            const SizedBox(height: 12),
            _buildSignOutTips(theme, colorScheme),
          ],

          const SizedBox(height: 24),

          // 根据签到类型显示不同输入
          if (_signActivity != null) ...[
            _buildSignTypeSection(theme, colorScheme),
            const SizedBox(height: 24),
          ],

          // 分享签到选项
          if (_accountManager.accounts.isNotEmpty) ...[
            _buildShareSignSection(theme, colorScheme),
            const SizedBox(height: 24),
          ],

          // 错误提示
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 签到按钮（二维码签到不显示，因为已有扫描二维码按钮）
          if (_signActivity?.signType != XxtSignType.qrcode)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _isLoading ? null : _doSign,
                child: _isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        _enableShareSign
                            ? '分享签到 (${_selectedAccounts.length + 1}人)'
                            : '立即签到',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShareSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '分享签到',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _enableShareSign,
                  onChanged: (value) {
                    setState(() {
                      _enableShareSign = value;
                      if (value && _selectedAccounts.isEmpty) {
                        // 默认选中所有启用的账号
                        _selectedAccounts = List.from(
                          _accountManager.enabledAccounts,
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            if (_enableShareSign) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前登录账号将自动签到',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 二维码签到警告
              if (_signActivity?.signType == XxtSignType.qrcode &&
                  _selectedAccounts.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '二维码签到的分享签到可能因二维码过期而失败',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                '额外为以下账号签到：',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // 账号列表
              ...(_accountManager.accounts.map((account) {
                final isSelected = _selectedAccounts.contains(account);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedAccounts.add(account);
                      } else {
                        _selectedAccounts.remove(account);
                      }
                    });
                  },
                  title: Text(account.displayName),
                  subtitle: Text(
                    account.username,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              })),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.activity.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.courseActivity.courseName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_signActivity != null) ...[
              const SizedBox(height: 16),
              Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              _buildInfoRow(
                theme,
                colorScheme,
                Icons.category_rounded,
                '签到类型',
                _signActivity!.signType.displayName,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                theme,
                colorScheme,
                Icons.schedule_rounded,
                '剩余时间',
                _signActivity!.remainingTimeText,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建签退提示卡片
  Widget _buildSignOutTips(ThemeData theme, ColorScheme colorScheme) {
    final signOutInfo = _signActivity!.signOutInfo!;
    final status = signOutInfo.redirectStatus;

    // 检查签退时间是否有效（年份不能小于当前年份）
    final publishTime = signOutInfo.signOutPublishTime;
    if (publishTime != null && publishTime.year < DateTime.now().year) {
      // 无效的签退时间，不显示提示
      return const SizedBox.shrink();
    }

    // 获取提示文字
    String tipText;
    bool canTap = true;
    bool isSignOut = false;

    switch (status) {
      case XxtSignRedirectStatus.signOut:
        tipText = '这是一个签退活动，请确保已经签到了本签退活动的主签到活动。\n点击跳转到主签到活动进行签到。';
        isSignOut = true;
        break;
      case XxtSignRedirectStatus.signInPublished:
        tipText = '此签到已发布签退活动。\n点击跳转到签退活动进行签退。';
        break;
      case XxtSignRedirectStatus.signInUnpublished:
        if (publishTime != null) {
          final formattedTime =
              '${publishTime.year}-${publishTime.month.toString().padLeft(2, '0')}-${publishTime.day.toString().padLeft(2, '0')} ${publishTime.hour.toString().padLeft(2, '0')}:${publishTime.minute.toString().padLeft(2, '0')}:${publishTime.second.toString().padLeft(2, '0')}';
          tipText = '此签到活动设置了签退活动，将在$formattedTime发布，请发布后及时签退。';
        } else {
          tipText = '此签到活动设置了签退活动，请发布后及时签退。';
        }
        canTap = false;
        break;
      default:
        return const SizedBox.shrink();
    }

    // 签退使用紫色调，签到使用蓝绿色调
    final cardColor = isSignOut
        ? colorScheme.tertiaryContainer
        : colorScheme.secondaryContainer;
    final iconColor = isSignOut
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSecondaryContainer;
    final textColor = isSignOut
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSecondaryContainer;

    // 获取图标
    final icon = isSignOut
        ? Icons
              .login_rounded // 签退活动：需要先签到
        : Icons.logout_rounded; // 签到活动：有签退

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: canTap
            ? () => _navigateToSignOutActivity(signOutInfo, status)
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tipText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              if (canTap)
                Icon(
                  Icons.chevron_right_rounded,
                  color: iconColor.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 跳转到签退活动
  Future<void> _navigateToSignOutActivity(
    XxtSignOutInfo signOutInfo,
    XxtSignRedirectStatus status,
  ) async {
    // 获取要跳转的活动 ID
    final targetActiveId = status == XxtSignRedirectStatus.signOut
        ? signOutInfo.signInId
        : signOutInfo.signOutId;

    if (targetActiveId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法获取目标活动信息')));
      return;
    }

    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在获取活动信息...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      // 获取目标活动的详细信息
      final targetActivity = await _signService.getSignActivityInfo(
        targetActiveId,
        widget.courseActivity.courseName,
        widget.courseActivity.courseId,
        widget.courseActivity.classId,
      );

      if (targetActivity == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('获取活动信息失败')));
        }
        return;
      }

      if (mounted) {
        // 创建一个新的 XxtActivity 用于跳转
        final targetXxtActivity = XxtActivity(
          activeId: targetActiveId,
          name: targetActivity.name,
          type: XxtActivityType.signIn,
          rawType: '签到',
          status: XxtActivityStatus.pending,
        );

        // 跳转到新的签到页面
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => XxtSignScreen(
              activity: targetXxtActivity,
              courseActivity: widget.courseActivity,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('跳转签退活动失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('跳转失败: $e')));
      }
    }
  }

  Widget _buildInfoRow(
    ThemeData theme,
    ColorScheme colorScheme,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSignTypeSection(ThemeData theme, ColorScheme colorScheme) {
    switch (_signActivity!.signType) {
      case XxtSignType.normal:
        return _buildNormalSignSection(theme, colorScheme);
      case XxtSignType.photo:
        return _buildPhotoSignSection(theme, colorScheme);
      case XxtSignType.qrcode:
        return _buildQRCodeSignSection(theme, colorScheme);
      case XxtSignType.gesture:
        return _buildGestureSignSection(theme, colorScheme);
      case XxtSignType.password:
        return _buildPasswordSignSection(theme, colorScheme);
      case XxtSignType.location:
        return _buildLocationSignSection(theme, colorScheme);
    }
  }

  Widget _buildNormalSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '点击下方按钮即可完成签到',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 提示信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.camera_alt_rounded, color: colorScheme.tertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '请拍摄或选择照片完成签到',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 照片预览区域
        if (_photoData != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.memory(
                  _photoData!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    onPressed: () {
                      setState(() {
                        _photoData = null;
                      });
                    },
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 拍照和选择照片按钮
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _isUploadingPhoto ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('拍摄照片'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _isUploadingPhoto ? null : _pickPhoto,
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('选择照片'),
              ),
            ),
          ],
        ),
        if (_enableShareSign) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, size: 16, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '拍照签到不建议使用分享签到，所有账号将使用同一张照片',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 拍摄照片
  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _photoData = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
      }
    }
  }

  /// 从相册选择照片
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _photoData = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择照片失败: $e')));
      }
    }
  }

  Widget _buildQRCodeSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 扫描二维码按钮
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _scanQRCode,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('扫描二维码签到'),
          ),
        ),
        if (_signActivity!.qrcodeRequireLocation) ...[
          const SizedBox(height: 16),
          _buildLocationInput(theme, colorScheme),
        ],
      ],
    );
  }

  /// 扫描二维码
  Future<void> _scanQRCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const _QRCodeScannerScreen()),
    );

    if (result != null && mounted) {
      // 解析二维码内容，提取 enc 参数
      final enc = _parseEncFromQRCode(result);
      if (enc != null) {
        setState(() {
          _encController.text = enc;
        });

        // 扫码成功后直接签到（防止二维码过期）
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('二维码识别成功，正在签到...'),
            duration: Duration(seconds: 1),
          ),
        );

        // 直接执行签到
        await _doSign();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法识别二维码: $result')));
      }
    }
  }

  /// 从二维码内容解析 enc 参数
  String? _parseEncFromQRCode(String qrContent) {
    // 尝试解析 URL 中的 enc 参数
    // 格式: https://mobilelearn.chaoxing.com/...?enc=XXXX&...
    try {
      final uri = Uri.parse(qrContent);
      final enc = uri.queryParameters['enc'];
      if (enc != null && enc.isNotEmpty) {
        return enc;
      }
    } catch (_) {}

    // 尝试使用正则表达式匹配
    final encMatch = RegExp(r'[?&]enc=([^&]+)').firstMatch(qrContent);
    if (encMatch != null) {
      return encMatch.group(1);
    }

    // 如果整个内容看起来像 enc（32位十六进制）
    if (RegExp(r'^[a-fA-F0-9]{32,}$').hasMatch(qrContent)) {
      return qrContent;
    }

    return null;
  }

  Widget _buildGestureSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '手势签到',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '请绘制手势图案完成签到',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        // 手势绘制区域
        Center(
          child: _GesturePatternWidget(
            onPatternCompleted: (pattern) {
              setState(() {
                _passwordController.text = pattern;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        // 显示已绘制的手势编码
        if (_passwordController.text.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '手势编码: ${_passwordController.text}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPasswordSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '密码签到',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '请输入签到密码',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '签到密码',
            hintText: '${_signActivity!.passwordLength ?? 4} 位数字',
            prefixIcon: const Icon(Icons.password_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSignSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '位置签到',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '请获取当前位置后签到',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _buildLocationInput(theme, colorScheme),
        if (_signActivity!.locationLatitude != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '签到范围: ${_signActivity!.locationRange ?? 0} 米',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '教师位置: ${_signActivity!.locationLatitude}, ${_signActivity!.locationLongitude}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationInput(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.my_location_rounded,
                color: _currentLocation != null
                    ? Colors.green
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentLocation != null ? '已获取位置' : '未获取位置',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_currentLocation != null)
                      Text(
                        '${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _isGettingLocation ? null : _getCurrentLocation,
                child: _isGettingLocation
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Text(_currentLocation != null ? '重新获取' : '获取位置'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 二维码扫描页面
class _QRCodeScannerScreen extends StatefulWidget {
  const _QRCodeScannerScreen();

  @override
  State<_QRCodeScannerScreen> createState() => _QRCodeScannerScreenState();
}

class _QRCodeScannerScreenState extends State<_QRCodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      _hasScanned = true;
      Navigator.pop(context, barcode!.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 扫描框覆盖层
          CustomPaint(
            painter: _ScannerOverlayPainter(
              borderColor: colorScheme.primary,
              overlayColor: Colors.black54,
            ),
            child: const SizedBox.expand(),
          ),
          // 提示文字
          Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: Text(
              '将二维码放入框内扫描',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                shadows: [const Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 扫描框覆盖层绘制
class _ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final Color overlayColor;

  _ScannerOverlayPainter({
    required this.borderColor,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.7;
    final scanAreaLeft = (size.width - scanAreaSize) / 2;
    final scanAreaTop = (size.height - scanAreaSize) / 2;
    final scanRect = Rect.fromLTWH(
      scanAreaLeft,
      scanAreaTop,
      scanAreaSize,
      scanAreaSize,
    );

    // 绘制半透明覆盖层
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlayPath, Paint()..color = overlayColor);

    // 绘制扫描框边角
    final cornerLength = 24.0;
    final cornerWidth = 4.0;
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 左上角
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop + cornerLength),
      Offset(scanAreaLeft, scanAreaTop),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop),
      Offset(scanAreaLeft + cornerLength, scanAreaTop),
      borderPaint,
    );

    // 右上角
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize - cornerLength, scanAreaTop),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + cornerLength),
      borderPaint,
    );

    // 右下角
    canvas.drawLine(
      Offset(
        scanAreaLeft + scanAreaSize,
        scanAreaTop + scanAreaSize - cornerLength,
      ),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      Offset(
        scanAreaLeft + scanAreaSize - cornerLength,
        scanAreaTop + scanAreaSize,
      ),
      borderPaint,
    );

    // 左下角
    canvas.drawLine(
      Offset(scanAreaLeft + cornerLength, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize),
      borderPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize - cornerLength),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 滑动验证码对话框
class _CaptchaDialog extends StatefulWidget {
  final XxtCaptchaData captchaData;
  final XxtSignActivity signActivity;
  final XxtSignService signService;

  const _CaptchaDialog({
    required this.captchaData,
    required this.signActivity,
    required this.signService,
  });

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  late XxtCaptchaData _captchaData;
  double _sliderValue = 0;
  bool _isVerifying = false;
  bool _isRefreshing = false;
  String? _error;

  // 原始图片尺寸（学习通验证码标准尺寸）
  static const double _originalWidth = 320.0;
  static const double _originalCutoutWidth = 56.0;

  // 实际渲染宽度（会根据容器动态调整）
  double _containerWidth = 320.0;

  // 计算密度因子
  double get _density => _containerWidth / _originalWidth;

  // 计算滑块显示宽度
  double get _cutoutDisplayWidth => _originalCutoutWidth * _density;

  // 计算滑块最大滑动范围
  double get _maxSliderRange => _containerWidth - _cutoutDisplayWidth;

  @override
  void initState() {
    super.initState();
    _captchaData = widget.captchaData;
  }

  /// 刷新验证码
  Future<void> _refreshCaptcha() async {
    setState(() {
      _isRefreshing = true;
      _error = null;
      _sliderValue = 0;
    });

    try {
      final newData = await widget.signService.getCaptchaImage(
        widget.signActivity,
      );
      if (newData != null && mounted) {
        setState(() {
          _captchaData = newData;
          _isRefreshing = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isRefreshing = false;
            _error = '刷新验证码失败';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _error = '刷新验证码失败: $e';
        });
      }
    }
  }

  /// 验证滑块位置
  Future<void> _verifyCaptcha() async {
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      // 坐标转换算法（与学习通官方一致）
      // 原始坐标范围: -8 到 272（总范围 280）
      // sliderValue 范围: 0 到 _maxSliderRange
      // 转换公式: (sliderValue / maxSliderRange) * 280 - 8
      final xPosition = (_sliderValue / _maxSliderRange) * 280.0 - 8.0;

      debugPrint(
        '验证码坐标: sliderValue=$_sliderValue, maxRange=$_maxSliderRange, xPosition=$xPosition',
      );

      final validate = await widget.signService.checkCaptchaResult(
        xPosition,
        _captchaData,
        widget.signActivity,
      );

      if (validate != null && mounted) {
        Navigator.of(context).pop(validate);
      } else {
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _sliderValue = 0;
            _error = '验证失败，请重试';
          });
          // 刷新验证码
          _refreshCaptcha();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _error = '验证失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('请完成滑动验证'),
      content: LayoutBuilder(
        builder: (context, constraints) {
          // 计算合适的宽度（最大 320，但不超过可用空间）
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 320.0;
          final targetWidth = availableWidth.clamp(200.0, 320.0);

          // 更新容器宽度（用于坐标计算）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_containerWidth != targetWidth) {
              setState(() {
                _containerWidth = targetWidth;
              });
            }
          });

          return SizedBox(
            width: targetWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 验证码图片区域
                if (_isRefreshing)
                  SizedBox(
                    height: targetWidth / 2,
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else
                  LayoutBuilder(
                    builder: (context, imageConstraints) {
                      final imageWidth = targetWidth;
                      final imageHeight = imageWidth / 2; // 2:1 比例
                      final cutoutWidth =
                          _originalCutoutWidth * (imageWidth / _originalWidth);

                      return SizedBox(
                        width: imageWidth,
                        height: imageHeight,
                        child: Stack(
                          children: [
                            // 背景图
                            Positioned.fill(
                              child: Image.network(
                                _captchaData.shadeImageUrl,
                                fit: BoxFit.fill,
                                errorBuilder: (context, error, stack) =>
                                    Container(
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          size: 48,
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                            // 滑块图
                            Positioned(
                              left: _sliderValue,
                              top: 0,
                              bottom: 0,
                              width: cutoutWidth,
                              child: Image.network(
                                _captchaData.cutoutImageUrl,
                                fit: BoxFit.fill,
                                errorBuilder: (context, error, stack) =>
                                    Container(color: Colors.grey[400]),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),

                // 滑块
                Slider(
                  value: _sliderValue,
                  min: 0,
                  max: _maxSliderRange,
                  onChanged: _isVerifying
                      ? null
                      : (value) {
                          setState(() {
                            _sliderValue = value;
                          });
                        },
                  onChangeEnd: _isVerifying ? null : (_) => _verifyCaptcha(),
                ),

                // 提示文字
                Text(
                  '拖动滑块完成验证',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                // 错误提示
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],

                // 加载指示器
                if (_isVerifying) ...[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _isVerifying ? null : _refreshCaptcha,
          child: const Text('刷新验证码'),
        ),
        TextButton(
          onPressed: _isVerifying
              ? null
              : () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 手势图案绘制组件
/// 九宫格手势解锁样式
class _GesturePatternWidget extends StatefulWidget {
  final void Function(String pattern) onPatternCompleted;

  const _GesturePatternWidget({required this.onPatternCompleted});

  @override
  State<_GesturePatternWidget> createState() => _GesturePatternWidgetState();
}

class _GesturePatternWidgetState extends State<_GesturePatternWidget> {
  /// 选中的点列表
  final List<int> _selectedPoints = [];

  /// 当前触摸位置
  Offset? _currentPosition;

  /// 是否正在绘制
  bool _isDrawing = false;

  /// 点的位置（9个点，3x3布局）
  final List<Offset> _pointPositions = [];

  /// 点的大小
  static const double _pointRadius = 24.0;

  /// 网格大小
  static const double _gridSize = 280.0;

  /// 点的间距
  double get _spacing => _gridSize / 3;

  @override
  void initState() {
    super.initState();
    _initPointPositions();
  }

  void _initPointPositions() {
    _pointPositions.clear();
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        _pointPositions.add(
          Offset(_spacing * col + _spacing / 2, _spacing * row + _spacing / 2),
        );
      }
    }
  }

  /// 检查触摸点是否在某个点的范围内
  int? _getPointAtPosition(Offset position) {
    for (int i = 0; i < _pointPositions.length; i++) {
      final distance = (position - _pointPositions[i]).distance;
      if (distance <= _pointRadius * 1.5) {
        return i;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final localPosition = details.localPosition;
    final point = _getPointAtPosition(localPosition);

    setState(() {
      _selectedPoints.clear();
      _isDrawing = true;
      _currentPosition = localPosition;

      if (point != null) {
        _selectedPoints.add(point);
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDrawing) return;

    final localPosition = details.localPosition;
    final point = _getPointAtPosition(localPosition);

    setState(() {
      _currentPosition = localPosition;

      if (point != null && !_selectedPoints.contains(point)) {
        _selectedPoints.add(point);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isDrawing = false;
      _currentPosition = null;
    });

    if (_selectedPoints.length >= 2) {
      // 将选中的点转换为编码（点编号从1开始）
      final pattern = _selectedPoints.map((p) => (p + 1).toString()).join('');
      widget.onPatternCompleted(pattern);
    }
  }

  void _reset() {
    setState(() {
      _selectedPoints.clear();
      _currentPosition = null;
      _isDrawing = false;
    });
    widget.onPatternCompleted('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Container(
          width: _gridSize,
          height: _gridSize,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _GesturePatternPainter(
                pointPositions: _pointPositions,
                selectedPoints: _selectedPoints,
                currentPosition: _isDrawing ? _currentPosition : null,
                pointRadius: _pointRadius,
                primaryColor: colorScheme.primary,
                inactiveColor: colorScheme.outlineVariant,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 重置按钮
        TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('重新绘制'),
        ),
        // 提示
        Text(
          '点位编号：\n1 2 3\n4 5 6\n7 8 9',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 手势图案绘制器
class _GesturePatternPainter extends CustomPainter {
  final List<Offset> pointPositions;
  final List<int> selectedPoints;
  final Offset? currentPosition;
  final double pointRadius;
  final Color primaryColor;
  final Color inactiveColor;

  _GesturePatternPainter({
    required this.pointPositions,
    required this.selectedPoints,
    required this.currentPosition,
    required this.pointRadius,
    required this.primaryColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final selectedPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final selectedStrokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final inactiveStrokePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final linePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // 绘制连线
    if (selectedPoints.length >= 2) {
      final path = Path();
      path.moveTo(
        pointPositions[selectedPoints[0]].dx,
        pointPositions[selectedPoints[0]].dy,
      );

      for (int i = 1; i < selectedPoints.length; i++) {
        path.lineTo(
          pointPositions[selectedPoints[i]].dx,
          pointPositions[selectedPoints[i]].dy,
        );
      }

      canvas.drawPath(path, linePaint);
    }

    // 绘制到当前位置的线
    if (selectedPoints.isNotEmpty && currentPosition != null) {
      canvas.drawLine(
        pointPositions[selectedPoints.last],
        currentPosition!,
        linePaint..color = primaryColor.withValues(alpha: 0.4),
      );
    }

    // 绘制点
    for (int i = 0; i < pointPositions.length; i++) {
      final position = pointPositions[i];
      final isSelected = selectedPoints.contains(i);

      // 外圈
      canvas.drawCircle(
        position,
        pointRadius,
        isSelected ? selectedStrokePaint : inactiveStrokePaint,
      );

      // 内圈（选中时）
      if (isSelected) {
        canvas.drawCircle(position, pointRadius * 0.4, selectedPaint);
      } else {
        canvas.drawCircle(position, pointRadius * 0.3, inactivePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GesturePatternPainter oldDelegate) {
    return selectedPoints != oldDelegate.selectedPoints ||
        currentPosition != oldDelegate.currentPosition;
  }
}
