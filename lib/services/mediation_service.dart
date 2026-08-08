import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_market.dart';
import '../utils/log_utils.dart';

class MediationService {
  MediationService._();

  static const MethodChannel _platformChannel = MethodChannel('camera_service');
  static bool _initialized = false;

  /// 初始化国内广告 SDK（Android Pangle）。若当前市场非国内、或已初始化、或非 Android，则直接跳过。
  ///
  /// 统一入口：main_china.dart / 隐私同意回调均可以调用本方法；内部负责去重。
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

  /// 兼容旧调用点（同意隐私后初始化）。
  static Future<void> initAfterPrivacyConsent() => initSdkIfNeeded();
}
