import 'package:flutter/material.dart';

import '../services/bind_api.dart';
import '../models/camera_device.dart';

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
    final title = field == _CameraField.name ? '相机名称' : '相机位置';
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
          SnackBar(content: Text('$title 不能为空')),
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

  Future<void> _saveToServer() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    try {
      await BindApi().updateCameraInfo(
        cameraDeviceId: widget.camera.id,
        cameraName: _name,
        cameraLocation: _location,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新失败: $e'),
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
          title: const Text('设备设置'),
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
              title: const Text('相机名称'),
              subtitle: Text(_name),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isSaving ? null : () => _editField(_CameraField.name),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('相机位置'),
              subtitle: Text(_location),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isSaving ? null : () => _editField(_CameraField.location),
            ),
            const Divider(height: 1),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('保存中...'),
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


