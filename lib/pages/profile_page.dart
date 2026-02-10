import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
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
  final String _membershipLevel = '基础版';

  // Banner ad
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadBannerAd();
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
    });
  }

  final List<SettingItem> _settingItems = [
    SettingItem(
      icon: Icons.help,
      title: '帮助中心',
      subtitle: '常见问题、联系客服',
      onTap: null, // wired in build to keep context available
    ),
    SettingItem(
      icon: Icons.info,
      title: '关于我们',
      subtitle: '版本信息、用户协议',
      onTap: null, // wired in build to keep context available
    ),
    SettingItem(
      icon: Icons.settings,
      title: '通用设置',
      subtitle: '账号注销、退出登录',
      onTap: null, // wired in build to keep context available
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
            _currentUserEmail ?? '未登录',
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
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _membershipLevel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSettingsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '设置',
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
            return _buildSettingItem(_settingItems[index]);
          },
        ),
      ],
    );
  }

  Widget _buildSettingItem(SettingItem item) {
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
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          item.subtitle,
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
    if (item.title == '帮助中心') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HelpCenterPage()),
      );
      return;
    }
    if (item.title == '关于我们') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AboutPage()),
      );
      return;
    }
    if (item.title == '通用设置') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
      );
      return;
    }
    if (item.onTap != null) {
      item.onTap!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('打开 ${item.title}')),
    );
  }
}

class SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
}
