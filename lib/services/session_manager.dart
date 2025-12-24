import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';

class SessionManager {
  static const _keyLoggedIn = 'logged_in';
  static const _keyEmail = 'user_email';
  static const _keyUserId = 'user_id';
  static bool _fallbackLoggedIn = false;
  static String? _fallbackEmail;
  static int? _fallbackUserId;

  /// Returns true if a previous login session is stored.
  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyLoggedIn) ?? false;
    } catch (e) {
      // Fallback to in-memory state if plugin is unavailable (e.g. hot reload without rebuild).
      return _fallbackLoggedIn;
    }
  }

  static Future<AuthUser?> getUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool(_keyLoggedIn) ?? false;
      if (!loggedIn) return null;
      final email = prefs.getString(_keyEmail);
      final id = prefs.getInt(_keyUserId);
      if (email == null || id == null) return null;
      return AuthUser(id: id, email: email);
    } catch (e) {
      if (!_fallbackLoggedIn || _fallbackEmail == null || _fallbackUserId == null) {
        return null;
      }
      return AuthUser(id: _fallbackUserId!, email: _fallbackEmail!);
    }
  }

  static Future<void> saveUser(AuthUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLoggedIn, true);
      await prefs.setString(_keyEmail, user.email);
      await prefs.setInt(_keyUserId, user.id);
    } catch (e) {
      _fallbackLoggedIn = true;
      _fallbackEmail = user.email;
      _fallbackUserId = user.id;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLoggedIn);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyUserId);
      await prefs.remove('device_role');
    } catch (e) {
      _fallbackLoggedIn = false;
      _fallbackEmail = null;
      _fallbackUserId = null;
    }
  }

  /// 保存相机端用户（扫码绑定时使用）
  /// 使用同一个邮箱存储，通过 device_role 区分角色
  static Future<void> saveCameraUser(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 使用统一的邮箱存储
      await prefs.setBool(_keyLoggedIn, true);
      await prefs.setString(_keyEmail, email);
      await prefs.setString('device_role', 'camera');
      // 临时用户ID，实际应该从登录接口获取
      await prefs.setInt(_keyUserId, 0);
    } catch (e) {
      // Fallback
      _fallbackLoggedIn = true;
      _fallbackEmail = email;
      _fallbackUserId = 0;
    }
  }

  /// 设置设备角色（camera 或 monitor）
  static Future<void> setDeviceRole(String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_role', role);
    } catch (e) {
      // Fallback ignored
    }
  }

  /// 获取设备角色（camera 或 monitor）
  static Future<String?> getDeviceRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('device_role');
    } catch (e) {
      return null;
    }
  }
}

