import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/push_service.dart';
import '../services/session_manager.dart';
import '../utils/app_features.dart';
import 'camera_endpoint_page.dart';
import 'camera_list_page.dart';
import 'membership_page.dart';
import 'profile_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
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
      if (!membershipEnabled && _currentIndex > 1) {
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
        membershipEnabled
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
    if (firebaseEnabled) {
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
            final profileTabIndex = membershipEnabled ? 2 : 1;
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
            membershipEnabled
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
        membershipEnabled
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
