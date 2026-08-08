import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rephone_security/app.dart';
import 'package:rephone_security/flavors/app_env.dart';
import 'package:rephone_security/flavors/env_config.dart';
import 'package:rephone_security/flavors/placeholder_services.dart';
import 'package:rephone_security/l10n/app_localizations.dart';

/// Widget 测试：在测试环境下注入一份默认配置，避免 AppEnv 未注入报错。
void main() {
  group('App builds', () {
    setUp(() {
      if (!AppEnv.injected) {
        final toggles = chinaFeatureToggles();
        AppEnv.inject(
          config: chinaEnvConfig(),
          features: toggles,
          crash: PlaceholderCrashService(),
          push: PlaceholderPushService(),
          iap: PlaceholderIapService(toggles),
          ads: PlaceholderAdService(toggles),
        );
      }
    });

    testWidgets('RePhoneSecurityApp pumps', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RePhoneSecurityApp(),
      ));
      await tester.pump();
    });
  });
}
