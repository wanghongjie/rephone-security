import 'package:flutter/material.dart';
import '../services/session_manager.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _currentUserEmail;
  final String _membershipLevel = '基础版';
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
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
      icon: Icons.account_circle,
      title: '账户信息',
      subtitle: '编辑个人资料',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.security,
      title: '安全设置',
      subtitle: '密码、双重验证',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.notifications,
      title: '通知设置',
      subtitle: '推送、邮件通知',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.privacy_tip,
      title: '隐私设置',
      subtitle: '数据使用、权限管理',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.family_restroom,
      title: '家庭共享',
      subtitle: '管理家庭成员',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.storage,
      title: '存储管理',
      subtitle: '云存储使用情况',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.help,
      title: '帮助中心',
      subtitle: '常见问题、联系客服',
      onTap: null,
    ),
    SettingItem(
      icon: Icons.info,
      title: '关于我们',
      subtitle: '版本信息、用户协议',
      onTap: null,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildUserProfile(),
            const SizedBox(height: 24),
            _buildSettingsList(),
            const SizedBox(height: 24),
            _buildLogoutButton(),
          ],
        ),
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

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _showLogoutDialog,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text(
          '退出登录',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _onSettingTap(SettingItem item) {
    if (item.onTap != null) {
      item.onTap!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开 ${item.title}')),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账户吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
            child: const Text('确定'),
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
        const SnackBar(content: Text('已退出登录')),
      );
      // Go to login page and clear navigation stack.
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoggingOut = false;
      });
    }
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
