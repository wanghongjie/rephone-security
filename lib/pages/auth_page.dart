import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../widgets/agreement_checkbox.dart';
import 'email_auth_flow.dart';
import 'qr_code_scanner_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _agreed = false;

  bool _ensureAgreed() {
    if (_agreed) return true;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.authCheckAgreeHint)),
    );
    return false;
  }

  void _openEmail() {
    if (!_ensureAgreed()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EmailInputPage(),
      ),
    );
  }

  void _openScan() {
    if (!_ensureAgreed()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QRCodeScannerPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.authTitle),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.authChooseMethod,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.authDesc,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              _AuthButton(
                label: l.authEmailLogin,
                icon: Icons.alternate_email,
                background: theme.colorScheme.primary,
                foreground: Colors.white,
                onPressed: _openEmail,
              ),
              const SizedBox(height: 12),
              _AuthButton(
                label: l.authScanToBind,
                icon: Icons.qr_code_scanner,
                background: Colors.white,
                foreground: theme.colorScheme.primary,
                borderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
                onPressed: _openScan,
              ),
              const SizedBox(height: 20),
              AgreementCheckbox(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
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
