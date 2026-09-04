import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// 隐私设置页：提供「个性化推荐」开关。
///
/// 说明：国内版当前尚未接入真实广告/推荐 SDK，开关仅用于保存用户的
/// 偏好选择（供后续服务上线时遵循），不产生任何实际的个性化推荐行为。
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  static const _keyPersonalizedRec = 'personalized_recommendation_enabled';

  bool _recEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recEnabled = prefs.getBool(_keyPersonalizedRec) ?? false;
      _loaded = true;
    });
  }

  Future<void> _setPersonalizedRecommendation(bool value) async {
    setState(() {
      _recEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPersonalizedRec, value);
    _showSaved();
  }

  void _showSaved() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).privacySettingSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsPrivacy),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 8),
                _buildSwitchItem(
                  title: l.privacyPersonalizedRecTitle,
                  subtitle: l.privacyPersonalizedRecSubtitle,
                  value: _recEnabled,
                  onChanged: _setPersonalizedRecommendation,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    l.privacyPersonalizedRecPageDesc,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ),
    );
  }
}
