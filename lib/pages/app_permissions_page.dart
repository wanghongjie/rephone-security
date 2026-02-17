import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';

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
    
    // For photos/storage, it varies by platform/version, simplified here
    final photosStatus = await Permission.photos.status; 
    // Note: Android 13+ uses separate permissions (photos, videos, audio), 
    // but permission_handler usually abstracts or we might need Permission.storage for older Android.
    // For simplicity in this demo, we check 'photos' which maps reasonably well on iOS and newer Android.
    // If needed, we can add more specific checks.

    if (mounted) {
      setState(() {
        _cameraGranted = cameraStatus.isGranted;
        _microphoneGranted = microphoneStatus.isGranted;
        _photosGranted = photosStatus.isGranted;
        _isLoading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
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
                ),
                _buildPermissionItem(
                  icon: Icons.mic,
                  title: l.appPermissionsMic,
                  subtitle: l.appPermissionsMicSubtitle,
                  isGranted: _microphoneGranted,
                ),
                _buildPermissionItem(
                  icon: Icons.photo_library,
                  title: l.appPermissionsPhotos,
                  subtitle: l.appPermissionsPhotosSubtitle,
                  isGranted: _photosGranted,
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
          onChanged: (value) => _openSettings(),
        ),
        onTap: _openSettings,
      ),
    );
  }
}
