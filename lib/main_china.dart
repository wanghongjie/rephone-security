import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'pages/auth_page.dart';
import 'pages/main_page.dart';
import 'pages/startup_page.dart';
import 'pages/welcome_page.dart';
import 'utils/app_market.dart';
import 'utils/log_utils.dart';
import 'utils/navigation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志工具
  await LogUtils.init();
  await LocaleManager.init();
  await AppMarket.init();

  // FCM：见 [registerMonitorPushIfNeeded]，仅在监控端角色就绪后初始化。

  // 设置沉浸式状态栏
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // 状态栏透明
    statusBarIconBrightness: Brightness.dark, // Android 状态栏图标黑色
    statusBarBrightness: Brightness.light, // iOS 状态栏文字黑色
  ));

  runApp(const RePhoneSecurityApp());
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
