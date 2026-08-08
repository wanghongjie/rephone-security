import 'package:flutter/foundation.dart';

import '../flavors/app_env.dart';
import '../services/push_service.dart' as legacy;
import 'app_market.dart';

/// 便捷开关：基于当前 [AppEnv.config.market] 与能力开关推断的业务级 flag。
///
/// 业务页面直接使用这些 getter，避免散落地写 `if(AppMarket.value == 'global')`。
///
/// 注：Phase1 期间 [membershipEnabled] / [firebaseEnabled] / [adMobEnabled]
/// 作为过渡仍被老代码使用；Phase2 将逐步把所有调用点收敛到 [AppEnv.features] 语义字段。

/// 是否启用内购会员页（海外版 Play/App Store 内购可用）。
bool get membershipEnabled => AppEnv.features.enableInAppPurchase;

/// 是否启用 Firebase 相关能力（Crashlytics / FCM / Analytics 等）。
bool get firebaseEnabled => AppEnv.features.enableFirebase;

/// 是否启用 Google Mobile Ads 广告。
bool get adMobEnabled =>
    AppEnv.features.enableGoogleMobileAds && AppMarket.adMobEnabled;

/// FCM/Android 推送的 background isolate 回调：仅在 [firebaseEnabled] 时注册。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(dynamic message) async {
  if (!firebaseEnabled) return;
  await legacy.legacyFirebaseMessagingBackgroundHandler(message);
}

/// 当用户登录并切换到「监控端」角色时，按需初始化 FCM 并绑定当前账号推送 token。
Future<void> registerMonitorPushIfNeeded() async {
  if (!AppEnv.features.enableClientPush) return;
  try {
    await legacy.legacyRegisterMonitorPushIfNeeded();
  } catch (e, s) {
    debugPrint('registerMonitorPushIfNeeded failed: $e\n$s');
  }
}
