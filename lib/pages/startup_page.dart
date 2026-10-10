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
      // 【合规】仅打开原生隐私闸门，**不在这里初始化穿山甲广告 SDK**。
      //
      // 原实现会在用户同意隐私政策（≈刚登录进入主页）时立刻初始化广告 SDK，
      // 导致 SDK 在用户尚未接触任何广告时就读取设备与「应用安装列表」，
      // MIUI 随即弹出系统级「获取安装应用信息」授权弹窗——属于
      // 「提前索取权限、且未以自定义弹窗同步告知目的」。
      //
      // 改为懒加载：只有首次真正渲染广告位时
      // （PangleBannerPlatformView → MediationSdkInitializer.ensureInitialized）
      // 才初始化 SDK，届时用户已明确停留在含广告位的页面上。
      await MediationService.grantPrivacyConsent();
      await AppEnv.ads.init();
      // 国内微信支付链路：fluwx/微信 SDK 的注册推迟到用户打开会员页时再执行
      // （会员页自身会调用 AppEnv.iap.init()），避免登录后立刻初始化第三方 SDK。
      // 海外商店内购链路仍需在启动时建立 BillingClient 连接，以补发未完成的交易。
      if (!AppEnv.iap.isThirdPartyPaymentEnabled) {
        await AppEnv.iap.init();
      }
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
