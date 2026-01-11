import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  static const String _supportEmail = 'dahongwudi123@gmail.com';

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写意见标题和反馈内容')),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });
    try {
      // TODO: 后续接入反馈接口 / 或 H5。
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('感谢反馈，我们会尽快处理')),
      );
      _titleController.clear();
      _contentController.clear();
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
            controller: _titleController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '意见标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '反馈内容',
              hintText: '请描述你遇到的问题、期望的功能或改进建议…',
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
            child: ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text(_supportEmail),
              subtitle: const Text('也可以直接发送邮件到该邮箱'),
              trailing: TextButton(
                onPressed: _copyEmail,
                child: const Text('复制邮箱'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


