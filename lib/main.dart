import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/services.dart';
import 'screens/screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化主题服务
  await ThemeService().init();

  // 初始化小组件服务
  await WidgetService.initialize();

  // 延迟初始化通知服务（减少启动时间和内存占用）
  // 通知服务会在首次使用时自动初始化

  // 设置系统UI样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  // 启用边缘到边缘显示
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const IcarusApp());
}

/// 伊卡洛斯应用主入口
class IcarusApp extends StatefulWidget {
  const IcarusApp({super.key});

  @override
  State<IcarusApp> createState() => _IcarusAppState();
}

class _IcarusAppState extends State<IcarusApp> {
  // 默认种子色 - 当系统不支持动态取色时使用
  static const Color _defaultSeedColor = Color(0xFF6366F1);

  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 使用 DynamicColorBuilder 支持莫奈取色
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 优先使用系统动态颜色，否则使用默认种子色
        final lightColorScheme =
            lightDynamic ??
            ColorScheme.fromSeed(
              seedColor: _defaultSeedColor,
              brightness: Brightness.light,
            );
        final darkColorScheme =
            darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: _defaultSeedColor,
              brightness: Brightness.dark,
            );

        return MaterialApp(
          title: '伊卡洛斯',
          debugShowCheckedModeBanner: false,
          // 本地化配置 - 支持中文
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _buildTheme(lightColorScheme),
          darkTheme: _buildTheme(darkColorScheme),
          themeMode: _themeService.themeMode,
          home: const AppNavigator(),
        );
      },
    );
  }

  /// 构建主题（支持动态 ColorScheme）
  ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // 全局页面过渡动画 - Material You 推荐的动画
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      // 现代化卡片
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      // FAB 样式
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      // 现代化按钮
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      // 现代化 AppBar
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      // 现代化输入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      // 现代化底部导航
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      // 现代化底部弹窗
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        dragHandleColor: colorScheme.outline.withValues(alpha: 0.4),
        dragHandleSize: const Size(40, 4),
        showDragHandle: true,
      ),
      // 现代化对话框
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      // 现代化 Snackbar
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      // 列表项
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      // 分割线
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.1),
        thickness: 1,
        space: 1,
      ),
      // 扩展面板
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      // Chip 样式
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
      ),
    );
  }
}

/// 应用导航器 - 处理登录状态
class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator>
    with SingleTickerProviderStateMixin {
  // 教务系统服务实例
  late final JwxtService _jwxtService;
  // 数据管理器
  DataManager? _dataManager;

  bool _isLoggedIn = false;
  bool _isLoading = true;
  String? _loadingMessage;

  // 加载动画控制器
  late AnimationController _loadingAnimationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _jwxtService = JwxtService(baseUrl: 'https://jwyth.hnkjxy.net.cn');

    // 初始化动画
    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _loadingAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _loadingAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // 设置自动重登回调
    _jwxtService.setAutoReloginCallback(_performAutoRelogin);

    _tryAutoLogin();
  }

  /// 执行无感自动重登（Cookie 失效时调用）
  Future<bool> _performAutoRelogin() async {
    try {
      final credentials = await AuthStorage.getCredentials();
      if (credentials == null) {
        debugPrint('无保存的凭据，无法自动重登');
        return false;
      }

      debugPrint('正在执行无感自动重登...');
      final result = await _jwxtService.autoLogin(
        username: credentials.username,
        password: credentials.password,
      );

      if (result is LoginSuccess) {
        debugPrint('无感自动重登成功');
        return true;
      } else {
        debugPrint('无感自动重登失败');
        return false;
      }
    } catch (e) {
      debugPrint('无感自动重登异常: $e');
      return false;
    }
  }

  /// 尝试自动登录
  Future<void> _tryAutoLogin() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = '正在检查登录状态...';
    });

    try {
      final credentials = await AuthStorage.getCredentials();
      if (credentials != null) {
        setState(() {
          _loadingMessage = '正在自动登录...';
        });

        final result = await _jwxtService.autoLogin(
          username: credentials.username,
          password: credentials.password,
          onProgress: (message) {
            if (mounted) {
              setState(() {
                _loadingMessage = message;
              });
            }
          },
        );

        if (result is LoginSuccess) {
          if (mounted) {
            _initDataManager();
            setState(() {
              _isLoggedIn = true;
              _isLoading = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('自动登录失败: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 初始化数据管理器
  void _initDataManager() {
    _dataManager?.dispose();
    _dataManager = DataManager(jwxtService: _jwxtService);
  }

  @override
  void dispose() {
    _loadingAnimationController.dispose();
    _dataManager?.dispose();
    _jwxtService.setAutoReloginCallback(null); // 清除回调
    _jwxtService.dispose();
    super.dispose();
  }

  void _onLoginSuccess() {
    _initDataManager();
    setState(() {
      _isLoggedIn = true;
    });
  }

  void _onLogout() async {
    await _jwxtService.logout();
    await AuthStorage.clearCredentials();
    await AuthStorage.clearAllDataCache(); // 清除所有数据缓存
    _dataManager?.dispose();
    _dataManager = null;
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 显示加载中
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withValues(alpha: 0.1),
                colorScheme.surface,
                colorScheme.secondary.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 动画 Logo
                  AnimatedBuilder(
                    animation: _loadingAnimationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.tertiary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(36),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              size: 56,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '伊卡洛斯',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '校园服务聚合平台',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _loadingMessage ?? '加载中...',
                      key: ValueKey(_loadingMessage),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 根据登录状态显示不同页面
    if (_isLoggedIn && _dataManager != null) {
      return MainShell(dataManager: _dataManager!, onLogout: _onLogout);
    } else {
      return LoginScreen(
        jwxtService: _jwxtService,
        onLoginSuccess: _onLoginSuccess,
      );
    }
  }
}
