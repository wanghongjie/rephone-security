import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'pages/auth_page.dart';
import 'pages/camera_list_page.dart';
import 'pages/camera_endpoint_page.dart';
import 'pages/membership_page.dart';
import 'pages/profile_page.dart';
import 'pages/welcome_page.dart';
import 'services/session_manager.dart';
import 'utils/log_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志工具
  await LogUtils.init();

  // 设置沉浸式状态栏
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // 状态栏透明
    statusBarIconBrightness: Brightness.dark, // Android 状态栏图标黑色
    statusBarBrightness: Brightness.light, // iOS 状态栏文字黑色
  ));

  runApp(const RePhoneSecurityApp());
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: <String>['32269ED36C964717F118F673D33C50C3'],
      ),
    );
  });
}

class RePhoneSecurityApp extends StatelessWidget {
  const RePhoneSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RePhone Security',
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
      home: const StartupPage(),
      routes: {
        '/auth': (_) => const AuthPage(),
        '/home': (_) => const MainPage(),
      },
      debugShowCheckedModeBanner: false,
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WelcomePage()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomePage()),
      );
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
  String _cameraRole = 'monitor'; // monitor 或 camera

  @override
  void initState() {
    super.initState();
    _loadCameraRole();
  }

  Future<void> _loadCameraRole() async {
    final role = await SessionManager.getDeviceRole() ?? 'monitor';
    if (role == 'camera') {
      setState(() {
        _cameraRole = 'camera';
      });
    }
  }

  Future<void> _switchToMonitor() async {
    setState(() {
      _cameraRole = 'monitor';
    });
    await SessionManager.setDeviceRole('monitor');
  }

  Future<void> _switchToCamera() async {
    setState(() {
      _cameraRole = 'camera';
    });
    await SessionManager.setDeviceRole('camera');
  }

  final List<Widget> _pages = [
    const CameraListPage(),
    const MembershipPage(),
    const ProfilePage(),
  ];

  final List<String> _titles = [
    '相机列表',
    '会员',
    '个人中心',
  ];

  @override
  Widget build(BuildContext context) {
    if (_cameraRole == 'camera') {
      return CameraEndpointPage(
        onSwitchToMonitor: _switchToMonitor,
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam),
            activeIcon: Icon(Icons.videocam),
            label: '相机列表',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.workspace_premium_outlined),
            activeIcon: Icon(Icons.workspace_premium),
            label: '会员',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '个人中心',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_currentIndex == 0) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        centerTitle: true,
        title: Text(_titles[_currentIndex]),
        leadingWidth: 140,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CameraRoleMenu(
              value: _cameraRole,
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
      title: Text(_titles[_currentIndex]),
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
    final isMonitor = value == 'monitor';
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'monitor',
          child: Text('监控端'),
        ),
        PopupMenuItem(
          value: 'camera',
          child: Text('相机端'),
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
              isMonitor ? '监控端' : '相机端',
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
