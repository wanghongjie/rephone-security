import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../l10n/app_localizations.dart';
import '../utils/log_utils.dart';
import '../services/session_manager.dart';
import 'about_page.dart';
import 'general_settings_page.dart';
import 'help_center_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _currentUserEmail;

  // Banner ad
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  // 新增 VIP 状态
  bool _isVip = false;
  DateTime? _expireAt;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadBannerAd();
  }

  Future<void> refresh() async {
    await _loadUserInfo();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    // NOTE:
    // - These are Google's official Banner TEST ad unit IDs.
    // - Replace with your own Banner ad unit IDs when ready.
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';

    final ad = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isBannerAdReady = false;
          });
          // Keep quiet in UI; log only.
          LogUtils.w('ProfilePage', 'BannerAd failed to load: code=${error.code}, message=${error.message}, domain=${error.domain}');
        },
      ),
    );

    ad.load();
  }

  Future<void> _loadUserInfo() async {
    final user = await SessionManager.getUser();
    if (!mounted) return;
    setState(() {
      _currentUserEmail = user?.email;
      _isVip = (user?.vipLevel ?? 0) > 0;
      _expireAt = user?.expireAt;
    });
  }

  final List<SettingItem> _settingItems = const [
    SettingItem(
      id: 'helpCenter',
      icon: Icons.help,
    ),
    SettingItem(
      id: 'about',
      icon: Icons.info,
    ),
    SettingItem(
      id: 'generalSettings',
      icon: Icons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildUserProfile(),
                  const SizedBox(height: 24),
                  _buildSettingsList(),
                ],
              ),
            ),
          ),
          if (_isBannerAdReady && _bannerAd != null)
            SafeArea(
              top: false,
              child: Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserProfile() {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.mail_outline,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            _currentUserEmail ?? l.profileNotLoggedIn,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: (_isVip ? Colors.orange : Colors.white).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isVip)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.star, color: Colors.yellow, size: 14),
                  ),
                Text(
                  _isVip
                      ? '${l.membershipStatusPremium}${_expireAt != null ? " (${_formatDate(_expireAt!)})" : ""}'
                      : l.membershipPlanBasic,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildSettingsList() {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.profileSettingsTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _settingItems.length,
          itemBuilder: (context, index) {
            return _buildSettingItem(_settingItems[index], l);
          },
        ),
      ],
    );
  }

  Widget _buildSettingItem(SettingItem item, AppLocalizations l) {
    String title;
    String subtitle;
    switch (item.id) {
      case 'helpCenter':
        title = l.profileHelpCenter;
        subtitle = l.profileHelpCenterSubtitle;
        break;
      case 'about':
        title = l.profileAbout;
        subtitle = l.profileAboutSubtitle;
        break;
      case 'generalSettings':
        title = l.profileGeneralSettings;
        subtitle = l.profileGeneralSettingsSubtitle;
        break;
      default:
        title = '';
        subtitle = '';
        break;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            item.icon,
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
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _onSettingTap(item),
      ),
    );
  }

  void _onSettingTap(SettingItem item) {
    if (item.id == 'helpCenter') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HelpCenterPage()),
      );
      return;
    }
    if (item.id == 'about') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AboutPage()),
      );
      return;
    }
    if (item.id == 'generalSettings') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
      );
      return;
    }
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l.profileOpenPagePrefix}${item.id}')),
    );
  }
}

class SettingItem {
  final String id;
  final IconData icon;

  const SettingItem({
    required this.id,
    required this.icon,
  });
}
