import '../flavors/app_env.dart';
import 'app_market.dart';

/// 便捷开关：基于当前 [AppEnv.config.market] 与能力开关推断的业务级 flag。
///
/// 业务页面直接使用这些 getter，避免散落地写 `if(AppMarket.value == 'global')`。
///
/// 注：Phase1 期间 [membershipEnabled] / [firebaseEnabled] / [adMobEnabled]
/// 作为过渡仍被老代码使用；Phase2 将逐步把所有调用点收敛到 [AppEnv.features] 语义字段。

/// 是否启用「会员页」入口（底部导航 tabCameras → tabMembership → tabProfile）。
///
/// 只要以下任意一条成立，就返回 true：
///  1. [FeatureToggles.enableInAppPurchase] = true（海外 Play / App Store IAP 链路）
///  2. [FeatureToggles.enableWechatPay] = true（国内微信支付链路）
///
/// 说明：会员页 UI 本身在运行时会通过 [IapService.isThirdPartyPaymentEnabled]
/// 进一步分流，是走商店 `buy()` 还是走 `createServerOrder()`。
/// 该 getter 只控制「是否展示会员 tab / 页面是否被构建」，不涉及支付链路。
bool get membershipEnabled =>
    AppEnv.features.enableInAppPurchase || AppEnv.features.enableWechatPay;

/// 是否启用 Firebase 相关能力（Crashlytics / FCM / Analytics 等）。
bool get firebaseEnabled => AppEnv.features.enableFirebase;

/// 是否启用 Google Mobile Ads 广告。
bool get adMobEnabled =>
    AppEnv.features.enableGoogleMobileAds && AppMarket.adMobEnabled;
