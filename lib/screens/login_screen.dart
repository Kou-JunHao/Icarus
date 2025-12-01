/// 登录页面
/// Material You Design 风格的现代化登录界面
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../services/account_manager.dart';

/// 登录页面
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final JwxtService jwxtService;
  final String? errorMessage; // 可选的错误消息（从静默登录失败传入）

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    required this.jwxtService,
    this.errorMessage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberPassword = true;
  String? _errorMessage;
  Uint8List? _captchaImage;
  bool _showManualCaptcha = false;

  // 动画控制器
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
    _loadSavedCredentials();
    // 显示传入的错误消息
    if (widget.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _errorMessage = widget.errorMessage;
          });
        }
      });
    }
  }

  Future<void> _loadSavedCredentials() async {
    // 优先加载完整凭据
    final credentials = await AuthStorage.getCredentials();
    if (credentials != null && mounted) {
      setState(() {
        _usernameController.text = credentials.username;
        _passwordController.text = credentials.password;
        _rememberPassword = true;
      });
      return;
    }

    // 如果没有完整凭据，尝试加载记忆的账号
    final rememberedUsername = await AuthStorage.getRememberedUsername();
    if (rememberedUsername != null && mounted) {
      setState(() {
        _usernameController.text = rememberedUsername;
        _rememberPassword = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.jwxtService.autoLogin(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        onProgress: (message) {
          if (mounted) {
            setState(() {
              _errorMessage = message;
            });
          }
        },
      );

      if (!mounted) return;

      if (result is LoginSuccess) {
        // 保存凭据
        if (_rememberPassword) {
          await AuthStorage.saveCredentials(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );
        } else {
          // 即使不勾选记住密码，也保存账号
          await AuthStorage.saveRememberedUsername(
            _usernameController.text.trim(),
          );
        }

        // 添加或更新账号到账号管理器
        final username = _usernameController.text.trim();
        final password = _passwordController.text;
        final displayName = widget.jwxtService.currentUser?.name;
        await AccountManager().addAccount(
          username: username,
          password: password,
          displayName: displayName,
          setAsActive: true,
        );

        widget.onLoginSuccess();
      } else if (result is LoginNeedCaptcha) {
        setState(() {
          _captchaImage = result.captchaImage;
          _showManualCaptcha = true;
          _errorMessage = '需要手动输入验证码';
        });
      } else if (result is LoginFailure) {
        setState(() {
          _errorMessage = result.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '登录失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginWithCaptcha() async {
    if (_captchaController.text.isEmpty) {
      setState(() {
        _errorMessage = '请输入验证码';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.jwxtService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        captcha: _captchaController.text,
      );

      if (!mounted) return;

      if (result is LoginSuccess) {
        if (_rememberPassword) {
          await AuthStorage.saveCredentials(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );
        } else {
          // 即使不勾选记住密码，也保存账号
          await AuthStorage.saveRememberedUsername(
            _usernameController.text.trim(),
          );
        }

        // 添加或更新账号到账号管理器
        final username = _usernameController.text.trim();
        final password = _passwordController.text;
        final displayName = widget.jwxtService.currentUser?.name;
        await AccountManager().addAccount(
          username: username,
          password: password,
          displayName: displayName,
          setAsActive: true,
        );

        widget.onLoginSuccess();
      } else if (result is LoginFailure) {
        setState(() {
          _errorMessage = result.message;
        });
        // 刷新验证码
        _refreshCaptcha();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '登录失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshCaptcha() async {
    final image = await widget.jwxtService.refreshCaptcha();
    if (mounted && image != null) {
      setState(() {
        _captchaImage = image;
        _captchaController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: 0.08),
              colorScheme.surface,
              colorScheme.secondary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo 和标题
                      _buildHeader(colorScheme),
                      const SizedBox(height: 32),
                      // 登录表单卡片
                      _buildLoginCard(theme, colorScheme, size),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo - 使用应用图标前景
        Hero(
          tag: 'app_logo',
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/app_icon_foreground.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 应用名和副标题
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '伊卡洛斯',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '校园服务聚合平台',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoginCard(ThemeData theme, ColorScheme colorScheme, Size size) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题
                Text(
                  '登录教务系统',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '使用学号和教务系统密码登录',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // 学号输入框
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: '学号',
                    hintText: '请输入学号',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入学号';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // 密码输入框
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '请输入密码',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: _showManualCaptcha
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_showManualCaptcha) _login();
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    return null;
                  },
                ),

                // 验证码输入（仅在需要时显示）
                if (_showManualCaptcha) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _captchaController,
                          decoration: InputDecoration(
                            labelText: '验证码',
                            hintText: '请输入验证码',
                            prefixIcon: const Icon(
                              Icons.security_outlined,
                              size: 20,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _loginWithCaptcha(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 验证码图片
                      GestureDetector(
                        onTap: _refreshCaptcha,
                        child: Container(
                          height: 48,
                          width: 96,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _captchaImage != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    _captchaImage!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // 记住密码
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 32,
                        width: 32,
                        child: Checkbox(
                          value: _rememberPassword,
                          onChanged: (value) {
                            setState(() {
                              _rememberPassword = value ?? true;
                            });
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _rememberPassword = !_rememberPassword;
                            });
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '记住密码',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '勾选后下次打开可无感登录',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.outline,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 错误信息
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _errorMessage!.contains('正在')
                          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                          : colorScheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _errorMessage!.contains('正在')
                              ? Icons.info_outline
                              : Icons.error_outline,
                          size: 18,
                          color: _errorMessage!.contains('正在')
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _errorMessage!.contains('正在')
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // 登录按钮
                FilledButton(
                  onPressed: _isLoading
                      ? null
                      : (_showManualCaptcha ? _loginWithCaptcha : _login),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Text('登录'),
                ),

                // 返回自动登录
                if (_showManualCaptcha) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showManualCaptcha = false;
                        _captchaController.clear();
                        _errorMessage = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(36),
                    ),
                    child: const Text('返回自动登录'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
