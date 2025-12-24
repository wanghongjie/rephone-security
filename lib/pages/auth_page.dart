import 'package:flutter/material.dart';
import 'email_auth_flow.dart';
import 'qr_code_scanner_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('登录 / 注册'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择登录方式',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '登录后可同步设备、查看告警记录，随时掌握安全动态。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              _AuthButton(
                label: '使用 Google 账号继续',
                icon: Icons.g_mobiledata,
                background: Colors.white,
                foreground: Colors.black,
                borderColor: Colors.grey[300],
                onPressed: () => _handleAuth(context, 'Google'),
              ),
              const SizedBox(height: 12),
              _AuthButton(
                label: '使用 Apple 账号继续',
                icon: Icons.apple,
                background: Colors.black,
                foreground: Colors.white,
                onPressed: () => _handleAuth(context, 'Apple'),
              ),
              const SizedBox(height: 12),
              _AuthButton(
                label: '使用电子邮件登录',
                icon: Icons.alternate_email,
                background: theme.colorScheme.primary,
                foreground: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmailInputPage(),
                    ),
                  );
                },
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const QRCodeScannerPage(),
                      ),
                    );
                  },
                  child: const Text('扫码绑定'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAuth(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider 登录示例，成功后进入首页')),
    );
    Navigator.pushReplacementNamed(context, '/home');
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    this.borderColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor ?? Colors.transparent),
          ),
          elevation: background == Colors.white ? 0 : 2,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

