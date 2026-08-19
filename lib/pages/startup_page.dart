import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../flavors/app_env.dart';
import '../flavors/env_config.dart';
import '../services/privacy_consent_service.dart';
import '../services/session_manager.dart';
import '../widgets/privacy_policy_dialog.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _decideStartPage();
  }

  Future<void> _decideStartPage() async {
    try {
      // 国内版（Android + China 市场）首次启动需先确认隐私政策：
      // 同意后进入应用并持久化记录；拒绝则退出应用。
      if (Platform.isAndroid && AppEnv.config.market == Market.china) {
        final accepted = await PrivacyConsentService.hasAccepted();
        if (!mounted) return;
        if (!accepted) {
          final agreed = await PrivacyPolicyDialog.show(context);
          if (!mounted) return;
          if (!agreed) {
            await SystemNavigator.pop();
            return;
          }
          await PrivacyConsentService.accept();
        }
      }

      final loggedIn = await SessionManager.isLoggedIn();
      if (!mounted) return;
      if (loggedIn) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/welcome');
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
