import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';

class SessionManager {
  static const _keyLoggedIn = 'logged_in';
  static const _keyEmail = 'user_email';
  static const _keyUserId = 'user_id';
  static const _keyDeviceRole = 'device_role';
   static const _keyVipLevel = 'vip_level';
  static const _keyExpireAt = 'expire_at';
  static bool _fallbackLoggedIn = false;
  static String? _fallbackEmail;
  static int? _fallbackUserId;
  static int? _fallbackVipLevel;
  static DateTime? _fallbackExpireAt;

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
      final vipLevel = prefs.getInt(_keyVipLevel) ?? 0;
      final expireAtStr = prefs.getString(_keyExpireAt);
      final expireAt = expireAtStr != null ? DateTime.tryParse(expireAtStr) : null;
      if (email == null || id == null) return null;
      return AuthUser(id: id, email: email, vipLevel: vipLevel, expireAt: expireAt);
    } catch (e) {
      if (!_fallbackLoggedIn || _fallbackEmail == null || _fallbackUserId == null) {
        return null;
      }
      return AuthUser(
        id: _fallbackUserId!,
        email: _fallbackEmail!,
        vipLevel: _fallbackVipLevel ?? 0,
        expireAt: _fallbackExpireAt,
      );
    }
  }

  static Future<void> saveUser(AuthUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLoggedIn, true);
      await prefs.setString(_keyEmail, user.email);
      await prefs.setInt(_keyUserId, user.id);
      await prefs.setInt(_keyVipLevel, user.vipLevel);
      if (user.expireAt != null) {
        await prefs.setString(_keyExpireAt, user.expireAt!.toIso8601String());
      } else {
        await prefs.remove(_keyExpireAt);
      }
      // 登录时默认设置为监控端
      if (!prefs.containsKey(_keyDeviceRole)) {
        await prefs.setString(_keyDeviceRole, 'monitor');
      }
    } catch (e) {
      _fallbackLoggedIn = true;
      _fallbackEmail = user.email;
      _fallbackUserId = user.id;
      _fallbackVipLevel = user.vipLevel;
      _fallbackExpireAt = user.expireAt;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLoggedIn);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyDeviceRole);
      await prefs.remove('camera_role');
      await prefs.remove(_keyVipLevel);
      await prefs.remove(_keyExpireAt);
    } catch (e) {
      _fallbackLoggedIn = false;
      _fallbackEmail = null;
      _fallbackUserId = null;
      _fallbackVipLevel = null;
      _fallbackExpireAt = null;
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
      await prefs.setString(_keyDeviceRole, 'camera');
      // 临时用户ID，实际应该从登录接口获取
      await prefs.setInt(_keyUserId, 0);
      await prefs.setInt(_keyVipLevel, 0);
      await prefs.remove(_keyExpireAt);
    } catch (e) {
      // Fallback
      _fallbackLoggedIn = true;
      _fallbackEmail = email;
      _fallbackUserId = 0;
      _fallbackVipLevel = 0;
      _fallbackExpireAt = null;
    }
  }

  /// 设置设备角色（camera 或 monitor）
  static Future<void> setDeviceRole(String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDeviceRole, role);
    } catch (e) {
      // Fallback ignored
    }
  }

  /// 获取设备角色（camera 或 monitor）
  static Future<String?> getDeviceRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyDeviceRole);
    } catch (e) {
      return null;
    }
  }
}
