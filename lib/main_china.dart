import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'flavors/app_env.dart';
import 'flavors/env_config.dart';
import 'flavors/features/ad_service_china.dart';
import 'flavors/features/crash_service_noop.dart';
import 'flavors/features/iap_service_china.dart';
import 'flavors/features/push_service_noop.dart';
import 'l10n/app_localizations.dart';
import 'utils/app_market.dart';
import 'utils/log_utils.dart';

/// 国内版入口（**仅 Android**，上架国内应用市场）。
///
/// - 注入 [chinaEnvConfig] / [chinaFeatureToggles]
/// - 不初始化 Firebase / Crashlytics / Google Mobile Ads
/// - 崩溃/推送使用 noop 实现；广告优先使用 Pangle
/// - **支付接入微信 APP 支付**（[ChinaWechatIapService] 封装了服务端下单 +
///   SDK 调起 + 轮询兜底全链路）
///
/// iOS 不走本入口：iOS 不区分国内/海外，统一使用 `lib/main.dart`（global 入口）
/// 走 Apple 内购（App Store / StoreKit）。构建脚本 `scripts/build_flavors.sh`
/// 已拒绝 `ios china` 组合。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LogUtils.init();
  await LocaleManager.init();
  await AppMarket.init();

  final config = chinaEnvConfig();
  final toggles = chinaFeatureToggles();

  AppEnv.inject(
    config: config,
    features: toggles,
    crash: NoopCrashService(),
    push: NoopPushService(),
    iap: ChinaWechatIapService(enabled: toggles.enableWechatPay),
    ads: ChinaPangleAdService(enablePangle: toggles.enablePangleAds),
  );

  // 沉浸式状态栏
  RePhoneSecurityApp.applySystemUIStyle();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  runApp(const RePhoneSecurityApp());

  // 【隐私合规】第三方 SDK（穿山甲广告 / 微信支付等）**禁止**在此处初始化。
  //
  // 上架审核要求：用户在点击隐私政策「同意」按钮前，APP 及集成的任何 SDK
  // 都不得调用系统隐私敏感接口（如读取 OAID / MAC 地址 / 传感器列表）。
  //
  // 因此统一改为：首次（及后续）启动由 StartupPage 确认隐私政策同意状态后，
  // 再统一触发第三方 SDK 初始化；原生侧另有 PrivacyConsentGate 闸门做二次兜底。
}
