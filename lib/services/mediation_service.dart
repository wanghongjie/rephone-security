import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_market.dart';
import '../utils/log_utils.dart';

class MediationService {
  MediationService._();

  static const MethodChannel _platformChannel = MethodChannel('camera_service');
  static bool _initialized = false;

  /// 通知原生侧：用户已同意隐私政策，允许初始化穿山甲（Pangle）广告 SDK。
  ///
  /// 原生侧 [PrivacyConsentGate] 默认关闭；只有本方法被调用后，闸门才会打开，
  /// 穿山甲 SDK 才允许调用 TTAdSdk.init/start（从而读取 OAID 等设备信息）。
  static Future<void> grantPrivacyConsent() async {
    if (!Platform.isAndroid) return;
    if (AppMarket.value.toLowerCase() != 'china') return;

    try {
      await _platformChannel.invokeMethod<bool>('grantPrivacyConsent');
      LogUtils.i('MediationService', 'grantPrivacyConsent ok');
    } catch (e, st) {
      LogUtils.e('MediationService', 'grantPrivacyConsent failed', e, st);
    }
  }

  /// 初始化国内广告 SDK（Android Pangle）。若当前市场非国内、或已初始化、或非 Android，则直接跳过。
  ///
  /// 注意：本方法内部不做隐私同意判定，调用方必须已确保用户同意隐私政策
  /// （或先前已调用 [grantPrivacyConsent]）；原生侧闸门会拒绝未同意时的初始化请求。
  static Future<void> initSdkIfNeeded() async {
    if (_initialized) return;
    if (!Platform.isAndroid) return;
    if (AppMarket.value.toLowerCase() != 'china') return;

    try {
      final ok = await _platformChannel.invokeMethod<bool>('initMediationAdSdk');
      _initialized = ok ?? false;
      LogUtils.i('MediationService', 'initMediationAdSdk result: $_initialized');
    } catch (e, st) {
      LogUtils.e('MediationService', 'initMediationAdSdk failed', e, st);
    }
  }

  /// 用户在隐私政策弹窗点击「同意」后调用：先打开原生闸门，再初始化 SDK。
  ///
  /// 【合规】当前**不再有调用方**：广告 SDK 改为懒加载，仅在实际渲染广告位时
  /// （PangleBannerPlatformView → ensureInitialized）初始化，避免用户刚登录
  /// 就触发 SDK 读取设备/应用安装列表。保留本方法仅用于未来「开屏广告」等
  /// 必须在启动时预热的场景，届时需配合自定义告知弹窗一并使用。
  static Future<void> initAfterPrivacyConsent() async {
    await grantPrivacyConsent();
    await initSdkIfNeeded();
  }
}
