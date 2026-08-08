import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'flavors/app_env.dart';
import 'l10n/app_localizations.dart';
import 'pages/auth_page.dart';
import 'pages/main_page.dart';
import 'pages/startup_page.dart';
import 'pages/welcome_page.dart';
import 'utils/navigation_service.dart';

/// 共享的 App Shell：两条入口（[main.dart] / [main_china.dart]）都挂载这同一个 MaterialApp，
/// 避免后续新增路由时需要在两份 main 中同步维护。
///
/// 该 Shell 只负责：主题、本地化、路由导航、沉浸式状态栏设置；
/// 差异化能力由入口注入到 [AppEnv] 中，业务页面通过 [AppEnv] 获取。
class RePhoneSecurityApp extends StatelessWidget {
  /// 构造 App Shell。
  const RePhoneSecurityApp({super.key});

  /// 启动前设置沉浸式状态栏（Android/iOS 通用）。
  static void applySystemUIStyle() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleManager.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: NavigationService.navigatorKey,
          title: AppEnv.config.appName,
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            if (locale != null) return locale;
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

  ThemeData _buildLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2196F3),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2196F3),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
    );
  }
}
