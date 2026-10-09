import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../flavors/app_env.dart';
import '../flavors/env_config.dart';
import '../services/mediation_service.dart';
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
      // 国内版（Android + China 市场）启动需先确认隐私政策：
      // 首次启动弹窗询问，同意后持久化记录；拒绝则退出应用。
      var consentGranted = false;
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
        consentGranted = true;
      }

      // 【隐私合规】只有确认用户已同意隐私政策后，才允许初始化第三方 SDK
      // （穿山甲广告 / 微信支付等），确保「同意前不调用任何隐私敏感接口」。
      // 不阻塞页面跳转，初始化在后台异步执行。
      if (consentGranted) {
        unawaited(_initChinaSdksAfterConsent());
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

  /// 用户已同意隐私政策后，统一初始化国内版第三方 SDK。
  ///
  /// 顺序：先打开原生隐私闸门（[MediationService.grantPrivacyConsent]），
  /// 再初始化穿山甲广告 / 微信支付 / 推送等。任一步失败都不影响应用启动。
  Future<void> _initChinaSdksAfterConsent() async {
    try {
      final features = AppEnv.features;
      if (features.enablePangleAds) {
        await MediationService.initAfterPrivacyConsent();
      }
      await AppEnv.ads.init();
      await AppEnv.iap.init();
      await AppEnv.push.init();
      await AppEnv.push.registerMonitorPushIfNeeded();
      await AppEnv.crash.setupFlutterErrorHandlers();
    } catch (_) {
      // 初始化失败不阻塞启动。
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
