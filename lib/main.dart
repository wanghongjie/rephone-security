import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'l10n/app_localizations.dart';
import 'pages/auth_page.dart';
import 'pages/main_page.dart';
import 'pages/startup_page.dart';
import 'pages/welcome_page.dart';
import 'utils/app_market.dart';
import 'utils/app_features.dart';
import 'utils/log_utils.dart';
import 'utils/navigation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志工具
  await LogUtils.init();
  await LocaleManager.init();
  await AppMarket.init();
  if (firebaseEnabled) {
    await Firebase.initializeApp();

    // 捕获 Flutter 框架抛出的异常
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // 捕获异步异常
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // FCM：见 [registerMonitorPushIfNeeded]，仅在监控端角色就绪后初始化。

  // 设置沉浸式状态栏
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // 状态栏透明
    statusBarIconBrightness: Brightness.dark, // Android 状态栏图标黑色
    statusBarBrightness: Brightness.light, // iOS 状态栏文字黑色
  ));

  runApp(const RePhoneSecurityApp());
  
  if (AppMarket.adMobEnabled) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: <String>['32269ED36C964717F118F673D33C50C3'],
        ),
      );
    });
  }
}

class RePhoneSecurityApp extends StatelessWidget {
  const RePhoneSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleManager.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          title: 'RePhone Security',
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            if (locale != null) {
              return locale;
            }
            return LocaleManager.resolveLocale(deviceLocale, supportedLocales);
          },
          initialRoute: '/',
          routes: {
            '/': (_) => const StartupPage(),
            '/welcome': (_) => const WelcomePage(),
            '/auth': (_) => const AuthPage(),
            '/home': (_) => const MainPage(),
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
