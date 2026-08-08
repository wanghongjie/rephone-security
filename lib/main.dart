import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'flavors/app_env.dart';
import 'flavors/env_config.dart';
import 'flavors/features/ad_service_global.dart';
import 'flavors/features/crash_service_global.dart';
import 'flavors/features/iap_service_global.dart';
import 'flavors/features/push_service_global.dart';
import 'l10n/app_localizations.dart';
import 'utils/app_market.dart';
import 'utils/log_utils.dart';

/// 海外版入口（上架 Play Store / App Store）。
///
/// - 注入 [globalEnvConfig] / [globalFeatureToggles]
/// - Firebase / Crashlytics / AdMob / FCM / IAP 均使用对应 global 实现
/// - 该文件仅 import `*_global.dart`，业务层不直接依赖具体 SDK 名
/// - Firebase 初始化使用官方推荐的 resource-based 模式：
///   Android 侧由 google-services Gradle 插件解析 `android/app/google-services.json`
///   生成 `res/values/values.xml` 中的字符串资源，
///   `FlutterFirebaseCorePlugin.optionsFromResource` 读取后初始化 DEFAULT 实例；
///   iOS 侧同理读取 `ios/Runner/GoogleService-Info.plist`。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LogUtils.init();
  await LocaleManager.init();
  await AppMarket.init();

  final config = globalEnvConfig();
  final toggles = globalFeatureToggles();

  if (toggles.enableFirebase) {
    await Firebase.initializeApp();
  }

  final crash = GlobalFirebaseCrashService();
  AppEnv.inject(
    config: config,
    features: toggles,
    crash: crash,
    push: GlobalFcmPushService(),
    iap: GlobalStoreIapService(enabled: toggles.enableInAppPurchase),
    ads: const GlobalAdMobService(enabled: true),
  );

  if (toggles.enableCrashReporting) {
    await crash.setupFlutterErrorHandlers();
  }

  // 沉浸式状态栏
  RePhoneSecurityApp.applySystemUIStyle();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  runApp(const RePhoneSecurityApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await AppEnv.ads.init();
    await AppEnv.iap.init();
    await AppEnv.push.init();
    await AppEnv.push.registerMonitorPushIfNeeded();
  });
}
