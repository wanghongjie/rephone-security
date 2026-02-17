import 'package:flutter/material.dart';

import '../services/bind_api.dart';
import '../models/camera_device.dart';
import '../l10n/app_localizations.dart';

enum _CameraField { name, location }

class CameraSettingsPage extends StatefulWidget {
  const CameraSettingsPage({
    super.key,
    required this.camera,
  });

  final CameraDevice camera;

  @override
  State<CameraSettingsPage> createState() => _CameraSettingsPageState();
}

class _CameraSettingsPageState extends State<CameraSettingsPage> {
  late String _name;
  late String _location;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _name = widget.camera.name;
    _location = widget.camera.location;
  }

  CameraDevice _buildUpdatedCamera() {
    return widget.camera.copyWith(
      name: _name,
      location: _location,
    );
  }

  Future<void> _editField(_CameraField field) async {
    final l = AppLocalizations.of(context);
    final title = field == _CameraField.name ? l.cameraSettingsName : l.cameraSettingsLocation;
    final initialValue = field == _CameraField.name ? _name : _location;

    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _CameraEditPage(
          title: title,
          initialValue: initialValue,
        ),
      ),
    );
    if (value == null) return;

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.cameraSettingsFieldEmpty)),
        );
      }
      return;
    }

    // Update local state first for snappy UI, then persist.
    setState(() {
      if (field == _CameraField.name) {
        _name = trimmed;
      } else {
        _location = trimmed;
      }
    });

    await _saveToServer();
  }

  Future<void> _deleteDevice() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cameraSettingsDeleteTitle),
        content: Text(l.cameraSettingsDeleteContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l.cameraSettingsDeleteButton),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await BindApi().deleteCamera(cameraDeviceId: widget.camera.id);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cameraSettingsDeleted)),
      );
      // Return null to indicate the device is gone/deleted, or a special signal
      // Actually, since we return a CameraDevice usually, we can return null to signal deletion
      // But the current implementation returns updated CameraDevice on pop.
      // We should change the return type logic or use a specific signal.
      // Let's modify the pop logic.
      Navigator.pop(context, null); // returning null means deleted (or cancelled, but we can differentiate if needed)
      // Wait, standard back returns the updated camera.
      // If I return null, the caller might think "no changes".
      // But the caller (CameraListPage) reloads the list anyway usually.
      // Let's stick to: standard back returns updated camera.
      // "Delete" returns 'deleted'.
      // But I can't return string 'deleted' because the type is CameraDevice.
      // I'll assume the caller handles null as "no update" or I need to change return type.
      // Let's check CameraListPage usage of push.
      // It doesn't use the return value currently! It relies on polling/refresh.
      // "onSelected: (value) => _handleMenuAction(value, camera),"
      // _handleMenuAction just calls navigation.
      // So I can just pop. The list will refresh via polling or manual refresh.
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.cameraSettingsDeleteFailed}: $e')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _saveToServer() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    try {
      final l = AppLocalizations.of(context);
      await BindApi().updateCameraInfo(
        cameraDeviceId: widget.camera.id,
        cameraName: _name,
        cameraLocation: _location,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cameraSettingsSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.cameraSettingsSaveFailed}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // Ensure we always return the latest edited values to the previous page,
    // including when user uses system back / gesture back.
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, _buildUpdatedCamera());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.cameraSettingsTitle),
          backgroundColor: theme.colorScheme.inversePrimary,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _buildUpdatedCamera()),
          ),
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(l.cameraSettingsName),
              subtitle: Text(_name),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isSaving ? null : () => _editField(_CameraField.name),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(l.cameraSettingsLocation),
              subtitle: Text(_location),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isSaving ? null : () => _editField(_CameraField.location),
            ),
            const Divider(height: 1),
            if (!_isSaving)
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(
                    l.cameraSettingsDeleteTitle,
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: _deleteDevice,
                ),
              ),
            if (_isSaving)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(l.cameraSettingsSaving),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraEditPage extends StatefulWidget {
  const _CameraEditPage({
    required this.title,
    required this.initialValue,
  });

  final String title;
  final String initialValue;

  @override
  State<_CameraEditPage> createState() => _CameraEditPageState();
}

class _CameraEditPageState extends State<_CameraEditPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('修改${widget.title}'),
        backgroundColor: theme.colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(context, v),
          decoration: InputDecoration(
            labelText: widget.title,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
