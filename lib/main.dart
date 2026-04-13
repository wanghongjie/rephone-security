import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'l10n/app_localizations.dart';
import 'pages/auth_page.dart';
import 'pages/camera_list_page.dart';
import 'pages/camera_endpoint_page.dart';
import 'pages/membership_page.dart';
import 'pages/profile_page.dart';
import 'pages/welcome_page.dart';
import 'services/push_service.dart';
import 'services/session_manager.dart';
import 'utils/app_market.dart';
import 'utils/log_utils.dart';
import 'utils/navigation_service.dart';

bool get _firebaseEnabled => AppMarket.value == 'global';
bool get _membershipEnabled => AppMarket.value == 'global';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!_firebaseEnabled) return;
  await Firebase.initializeApp();
  LogUtils.i('PushBackground', 'Message: ${message.messageId ?? ''}');
}

/// Camera 端不需要 FCM；仅在确认 [SessionManager] 角色为 monitor 后注册。
bool _monitorPushRegistrationDone = false;

Future<void> registerMonitorPushIfNeeded() async {
  if (!_firebaseEnabled) return;
  if (_monitorPushRegistrationDone) return;
  _monitorPushRegistrationDone = true;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await PushService.init();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志工具
  await LogUtils.init();
  await LocaleManager.init();
  await AppMarket.init();
  if (_firebaseEnabled) {
    await Firebase.initializeApp();

    // 捕获 Flutter 框架抛出的异常
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // 捕获异步异常
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // FCM：见 [registerMonitorPushIfNeeded]，仅在监控端角色就绪后初始化。

  // 设置沉浸式状态栏
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // 状态栏透明
    statusBarIconBrightness: Brightness.dark, // Android 状态栏图标黑色
    statusBarBrightness: Brightness.light, // iOS 状态栏文字黑色
  ));

  runApp(const RePhoneSecurityApp());
  
  if (AppMarket.adMobEnabled) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: <String>['32269ED36C964717F118F673D33C50C3'],
        ),
      );
    });
  }
}

class RePhoneSecurityApp extends StatelessWidget {
  const RePhoneSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleManager.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          title: 'RePhone Security',
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            if (locale != null) {
              return locale;
            }
            return LocaleManager.resolveLocale(deviceLocale, supportedLocales);
          },
          initialRoute: '/',
          routes: {
            '/': (_) => const StartupPage(),
            '/welcome': (_) => const WelcomePage(),
            '/auth': (_) => const AuthPage(),
            '/home': (_) => const MainPage(),
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _decideStartPage();
  }

  Future<void> _decideStartPage() async {
    try {
      final loggedIn = await SessionManager.isLoggedIn();
      if (!mounted) return;
      if (loggedIn) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/welcome');
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  /// `null` until [SessionManager.getDeviceRole] finishes — avoids mounting
  /// [MembershipPage] (and Google Play Billing) before we know the user is monitor.
  String? _cameraRole;
  final GlobalKey _profilePageKey = GlobalKey();
  final GlobalKey _cameraListPageKey = GlobalKey();
  bool _initializedIndex = false;
  List<Widget>? _monitorTabPages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedIndex) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is int) {
        _currentIndex = args;
      }
      if (!_membershipEnabled && _currentIndex > 1) {
        _currentIndex = 1;
      }
      _initializedIndex = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCameraRole();
  }

  List<Widget> _ensureMonitorTabPages() {
    return _monitorTabPages ??=
        _membershipEnabled
            ? [
                CameraListPage(key: _cameraListPageKey),
                const MembershipPage(),
                ProfilePage(key: _profilePageKey),
              ]
            : [
                CameraListPage(key: _cameraListPageKey),
                ProfilePage(key: _profilePageKey),
              ];
  }

  Future<void> _loadCameraRole() async {
    final role = await SessionManager.getDeviceRole() ?? 'monitor';
    if (!mounted) return;
    if (role == 'monitor') {
      unawaited(registerMonitorPushIfNeeded());
    }
    setState(() {
      _cameraRole = role;
      if (role == 'monitor') {
        _ensureMonitorTabPages();
      }
    });
  }

  Future<void> _switchToMonitor() async {
    setState(() {
      _cameraRole = 'monitor';
      _ensureMonitorTabPages();
    });
    await SessionManager.setDeviceRole('monitor');
    await registerMonitorPushIfNeeded();
    if (_firebaseEnabled) {
      PushService.reportTokenForLoggedInMonitor();
    }
  }

  Future<void> _switchToCamera() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.switchToCameraDialogTitle),
        content: Text(l.switchToCameraDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.commonConfirm),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SessionManager.clear();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_cameraRole == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_cameraRole == 'camera') {
      return const CameraEndpointPage();
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentIndex,
        children: _ensureMonitorTabPages(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          Future.microtask(() async {
            final profileTabIndex = _membershipEnabled ? 2 : 1;
            if (index == 0) {
              final state = _cameraListPageKey.currentState;
              if (state != null) await (state as dynamic).refresh();
            } else if (index == profileTabIndex) {
              final state = _profilePageKey.currentState;
              if (state != null) await (state as dynamic).refresh();
            }
          });
        },
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items:
            _membershipEnabled
                ? [
                    BottomNavigationBarItem(
                      icon: const Icon(Icons.videocam),
                      activeIcon: const Icon(Icons.videocam),
                      label: AppLocalizations.of(context).tabCameras,
                    ),
                    BottomNavigationBarItem(
                      icon: const Icon(Icons.workspace_premium_outlined),
                      activeIcon: const Icon(Icons.workspace_premium),
                      label: AppLocalizations.of(context).tabMembership,
                    ),
                    BottomNavigationBarItem(
                      icon: const Icon(Icons.person_outline),
                      activeIcon: const Icon(Icons.person),
                      label: AppLocalizations.of(context).tabProfile,
                    ),
                  ]
                : [
                    BottomNavigationBarItem(
                      icon: const Icon(Icons.videocam),
                      activeIcon: const Icon(Icons.videocam),
                      label: AppLocalizations.of(context).tabCameras,
                    ),
                    BottomNavigationBarItem(
                      icon: const Icon(Icons.person_outline),
                      activeIcon: const Icon(Icons.person),
                      label: AppLocalizations.of(context).tabProfile,
                    ),
                  ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final l = AppLocalizations.of(context);
    final titles =
        _membershipEnabled
            ? [l.tabCameras, l.tabMembership, l.tabProfile]
            : [l.tabCameras, l.tabProfile];
    if (_currentIndex == 0) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        centerTitle: true,
        title: Text(titles[_currentIndex]),
        leadingWidth: 140,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CameraRoleMenu(
              value: _cameraRole ?? 'monitor',
              onSelected: (role) {
                if (role == 'monitor') {
                  _switchToMonitor();
                } else {
                  _switchToCamera();
                }
              },
            ),
          ),
        ),
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(titles[_currentIndex]),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
    );
  }
}

class _CameraRoleMenu extends StatelessWidget {
  const _CameraRoleMenu({
    required this.value,
    required this.onSelected,
  });

  final String value;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isMonitor = value == 'monitor';
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'monitor',
          child: Text(l.cameraRoleMonitor),
        ),
        PopupMenuItem(
          value: 'camera',
          child: Text(l.cameraRoleCamera),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMonitor ? l.cameraRoleMonitor : l.cameraRoleCamera,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}
