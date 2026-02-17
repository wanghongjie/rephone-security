import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
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
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.helpFeedbackEmpty)),
      );
      return;
    }
    if (content.length > 5000) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.helpFeedbackTooLong)),
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
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            id != null ? '${l.helpFeedbackThanks} (ID: $id)' : l.helpFeedbackThanks,
          ),
        ),
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
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.helpEmailCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.helpCenterTitle),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.helpFeedback,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 7,
            maxLength: 5000,
            decoration: InputDecoration(
              labelText: l.helpFeedback,
              hintText: l.helpFeedbackHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l.helpContactOptional,
              hintText: l.helpContactHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submitFeedback,
              child: Text(_submitting ? l.helpSubmitting : l.helpSubmit),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l.helpEmailFeedback,
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
                        child: Text(l.tr('helpCopyEmail')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.helpEmailTip,
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
