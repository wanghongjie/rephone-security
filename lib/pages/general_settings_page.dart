import 'package:flutter/material.dart';
import '../services/session_manager.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('通用设置'),
      ),
      body: ListView(
        children: [
          _buildSettingItem(
            icon: Icons.security,
            title: '应用权限',
            subtitle: '管理相机、麦克风等权限',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppPermissionsPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.lock_reset,
            title: '重置密码',
            subtitle: '修改当前账户登录密码',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.delete_forever,
            title: '注销账号',
            subtitle: '永久删除账号及所有数据',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeleteAccountPage()),
              );
            },
          ),
          _buildSettingItem(
            icon: Icons.logout,
            title: '退出登录',
            subtitle: '退出当前登录账户',
            onTap: _showLogoutDialog,
            isDestructive: false, // Logout is technically destructive but usually styled differently than delete
          ),
        ],
      ),
    );
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
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }
}
