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
import 'services/mediation_service.dart';
import 'utils/app_market.dart';
import 'utils/log_utils.dart';

/// 国内版入口（上架国内应用市场）。
///
/// - 注入 [chinaEnvConfig] / [chinaFeatureToggles]
/// - 不初始化 Firebase / Crashlytics / Google Mobile Ads
/// - 崩溃/推送使用 noop 实现；广告优先使用 Pangle；**支付接入微信 APP 支付**
///   （[ChinaWechatIapService] 封装了服务端下单 + SDK 调起 + 轮询兜底全链路）。
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

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (toggles.enablePangleAds) {
      await MediationService.initSdkIfNeeded();
    }
    await AppEnv.ads.init();
    await AppEnv.iap.init();
    await AppEnv.push.init();
    await AppEnv.push.registerMonitorPushIfNeeded();
    await AppEnv.crash.setupFlutterErrorHandlers();
  });
}
