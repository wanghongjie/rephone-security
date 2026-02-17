import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import '../l10n/app_localizations.dart';
import 'app_permissions_page.dart';
import 'delete_account_page.dart';
import 'reset_password_page.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  bool _isLoggingOut = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsGeneral),
      ),
      body: ListView(
        children: [
          _buildSettingItem(
            icon: Icons.language,
            title: l.settingsLanguage,
            subtitle: _buildLanguageSubtitle(l),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LanguageSettingsPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.security,
            title: l.settingsAppPermissions,
            subtitle: l.settingsAppPermissionsSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppPermissionsPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.lock_reset,
            title: l.settingsResetPassword,
            subtitle: l.settingsResetPasswordSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.delete_forever,
            title: l.settingsDeleteAccount,
            subtitle: l.settingsDeleteAccountSubtitle,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeleteAccountPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.logout,
            title: l.settingsLogout,
            subtitle: l.settingsLogoutSubtitle,
            onTap: _showLogoutDialog,
            isDestructive: false, // Logout is technically destructive but usually styled differently than delete
          ),
        ],
      ),
    );
  }

  String _buildLanguageSubtitle(AppLocalizations l) {
    final locale = LocaleManager.localeNotifier.value;
    if (locale == null) {
      return l.settingsLanguageFollowSystem;
    }
    if (locale.languageCode == 'zh') {
      return l.settingsLanguageChinese;
    }
    return l.settingsLanguageEnglish;
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
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
            color: isDestructive ? Colors.red : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDestructive ? Colors.red : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _showLogoutDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.settingsLogoutDialogTitle),
        content: Text(l.settingsLogoutDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.settingsLogoutDialogCancel),
          ),
          ElevatedButton(
            onPressed: _isLoggingOut
                ? null
                : () async {
                    // Close the dialog first.
                    Navigator.pop(context);
                    await _logout();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l.settingsLogoutDialogConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() {
      _isLoggingOut = true;
    });
    try {
      await SessionManager.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).settingsLogoutSuccess)),
      );
      // Go to login page and clear navigation stack.
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  LanguageOption _currentLanguageOption() {
    final locale = LocaleManager.localeNotifier.value;
    if (locale == null) {
      return LanguageOption.system;
    }
    if (locale.languageCode == 'zh') {
      return LanguageOption.chinese;
    }
    return LanguageOption.english;
  }
}

enum LanguageOption { system, chinese, english }

class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  late LanguageOption _option;

  @override
  void initState() {
    super.initState();
    _option = LanguageOption.system;
    final locale = LocaleManager.localeNotifier.value;
    if (locale == null) {
      _option = LanguageOption.system;
    } else if (locale.languageCode == 'zh') {
      _option = LanguageOption.chinese;
    } else {
      _option = LanguageOption.english;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.languagePageTitle),
      ),
      body: ListView(
        children: [
          RadioListTile<LanguageOption>(
            value: LanguageOption.system,
            groupValue: _option,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _option = value;
              });
              LocaleManager.setSystem();
            },
            title: Text(l.languageOptionSystem),
            subtitle: Text(l.languageOptionSystemDetail),
          ),
          const Divider(height: 1),
          RadioListTile<LanguageOption>(
            value: LanguageOption.chinese,
            groupValue: _option,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _option = value;
              });
              LocaleManager.setChinese();
            },
            title: Text(l.languageOptionChinese),
            subtitle: Text(l.languageOptionChineseDetail),
          ),
          const Divider(height: 1),
          RadioListTile<LanguageOption>(
            value: LanguageOption.english,
            groupValue: _option,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _option = value;
              });
              LocaleManager.setEnglish();
            },
            title: Text(l.languageOptionEnglish),
            subtitle: Text(l.languageOptionEnglishDetail),
          ),
        ],
      ),
    );
  }
}
