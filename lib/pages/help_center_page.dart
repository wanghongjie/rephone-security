import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/feedback_api.dart';
import '../services/session_manager.dart';
import '../utils/device_info.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  static const String _supportEmail = 'dahongwudi123@gmail.com';

  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  bool _submitting = false;
  String? _email;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _loadContextInfo();
  }

  Future<void> _loadContextInfo() async {
    try {
      final user = await SessionManager.getUser();
      // Prefer stored device_role if available, otherwise use monitor.
      final role = await SessionManager.getDeviceRole() ?? 'monitor';
      final did = await DeviceInfo.getOrCreateDeviceId(role);
      if (!mounted) return;
      setState(() {
        _email = user?.email;
        _deviceId = did;
      });
    } catch (_) {
      // ignore: best-effort only
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final content = _contentController.text.trim();
    final contact = _contactController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写反馈内容')),
      );
      return;
    }
    if (content.length > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('反馈内容过长（最多 5000 字符）')),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });
    try {
      final id = await FeedbackApi().submit(
        email: _email,
        deviceId: _deviceId,
        content: content,
        contact: contact.isEmpty ? null : contact,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('感谢反馈，我们会尽快处理${id != null ? '（ID: $id）' : ''}')),
      );
      _contentController.clear();
      _contactController.clear();
    } finally {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邮箱已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助中心'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '意见反馈',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 7,
            maxLength: 5000,
            decoration: const InputDecoration(
              labelText: '反馈内容',
              hintText: '请描述你遇到的问题、期望的功能或改进建议…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '联系方式（可选）',
              hintText: '微信 / 手机号（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submitFeedback,
              child: Text(_submitting ? '提交中...' : '提交反馈'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '邮件反馈',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.email_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _supportEmail,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: _copyEmail,
                        child: const Text('复制邮箱'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '也可以直接发送邮件到该邮箱',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

