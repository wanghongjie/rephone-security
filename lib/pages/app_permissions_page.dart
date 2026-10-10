import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../utils/permission_kind.dart';
import '../utils/permission_manager.dart';

class AppPermissionsPage extends StatefulWidget {
  const AppPermissionsPage({super.key});

  @override
  State<AppPermissionsPage> createState() => _AppPermissionsPageState();
}

class _AppPermissionsPageState extends State<AppPermissionsPage> with WidgetsBindingObserver {
  bool _cameraGranted = false;
  bool _microphoneGranted = false;
  bool _photosGranted = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;

    // Photos：与 playback/monitor 实际“能否保存到相册”的逻辑一致，避免显示与行为矛盾。
    bool photosGranted;
    if (Platform.isAndroid) {
      final sdk = await _getAndroidSdkInt();
      // Android 10+ (API 29+) 通过 MediaStore 保存无需运行时权限，与 playback 行为一致。
      if (sdk != null && sdk >= 29) {
        photosGranted = true;
      } else {
        final storage = await Permission.storage.status;
        photosGranted = storage.isGranted || storage.isLimited;
      }
    } else {
      final photosStatus = await Permission.photos.status;
      final photosAddOnlyStatus = await Permission.photosAddOnly.status;
      photosGranted = photosStatus.isGranted ||
          photosStatus.isLimited ||
          photosAddOnlyStatus.isGranted ||
          photosAddOnlyStatus.isLimited;
    }

    if (mounted) {
      setState(() {
        _cameraGranted = cameraStatus.isGranted;
        _microphoneGranted = microphoneStatus.isGranted;
        _photosGranted = photosGranted;
        _isLoading = false;
      });
    }
  }

  Future<int?> _getAndroidSdkInt() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return null;
    }
  }

  /// 用户主动点击权限开关：
  /// 已开启 → 跳转系统设置（关闭也需在系统设置中操作）；
  /// 未开启 → 先弹自定义弹窗说明用途，用户同意后才调起系统权限弹窗。
  Future<void> _onPermissionTap(AppPermissionKind kind, bool isGranted) async {
    if (isGranted) {
      await openAppSettings();
      return;
    }
    await PermissionManager.ensure(
      context,
      kind,
      guideToSettingsOnDeny: true,
    );
    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appPermissionsTitle),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildPermissionItem(
                  icon: Icons.camera_alt,
                  title: l.appPermissionsCamera,
                  subtitle: l.appPermissionsCameraSubtitle,
                  isGranted: _cameraGranted,
                  onTap: () => _onPermissionTap(
                      AppPermissionKind.camera, _cameraGranted),
                ),
                _buildPermissionItem(
                  icon: Icons.mic,
                  title: l.appPermissionsMic,
                  subtitle: l.appPermissionsMicSubtitle,
                  isGranted: _microphoneGranted,
                  onTap: () => _onPermissionTap(
                      AppPermissionKind.microphone, _microphoneGranted),
                ),
                _buildPermissionItem(
                  icon: Icons.photo_library,
                  title: l.appPermissionsPhotos,
                  subtitle: l.appPermissionsPhotosSubtitle,
                  isGranted: _photosGranted,
                  onTap: () => _onPermissionTap(
                      AppPermissionKind.photos, _photosGranted),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    l.appPermissionsNote,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        trailing: Switch(
          value: isGranted,
          onChanged: (_) => onTap(),
        ),
        onTap: onTap,
      ),
    );
  }
}
