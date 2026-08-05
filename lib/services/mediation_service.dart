import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/app_market.dart';
import '../utils/log_utils.dart';

class MediationService {
  MediationService._();

  static const MethodChannel _platformChannel = MethodChannel('camera_service');
  static bool _initialized = false;

  static Future<void> initAfterPrivacyConsent() async {
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
}
