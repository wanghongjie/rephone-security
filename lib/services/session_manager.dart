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
    } catch (e) {
      _fallbackLoggedIn = false;
      _fallbackEmail = null;
      _fallbackUserId = null;
    }
  }
}

