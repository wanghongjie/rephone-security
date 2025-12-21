import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/auth_page.dart';
import 'pages/camera_list_page.dart';
import 'pages/camera_endpoint_page.dart';
import 'pages/explore_page.dart';
import 'pages/membership_page.dart';
import 'pages/profile_page.dart';
import 'pages/welcome_page.dart';
import 'services/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RePhoneSecurityApp());
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
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('camera_role') ?? 'monitor';
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('camera_role', 'monitor');
  }

  Future<void> _switchToCamera() async {
    setState(() {
      _cameraRole = 'camera';
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('camera_role', 'camera');
  }

  final List<Widget> _pages = [
    const CameraListPage(),
    const ExplorePage(),
    const MembershipPage(),
    const ProfilePage(),
  ];

  final List<String> _titles = [
    '相机列表',
    '探索',
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
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: '探索',
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
