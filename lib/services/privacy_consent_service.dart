import 'package:shared_preferences/shared_preferences.dart';

/// 国内版隐私政策同意状态管理。
///
/// 仅在 Android + China 市场生效：首次启动需弹窗确认，
/// 用户点击「同意」后持久化标记，后续启动不再弹出。
class PrivacyConsentService {
  PrivacyConsentService._();

  static const String _keyPrivacyAccepted = 'privacy_policy_accepted';

  /// 是否已同意隐私政策。
  static Future<bool> hasAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyPrivacyAccepted) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 记录用户已同意隐私政策。
  static Future<void> accept() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPrivacyAccepted, true);
    } catch (_) {
      // 存储失败不阻塞主流程
    }
  }
}
