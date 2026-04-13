import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Android：`global` flavor 使用 AdMob；`china` 不使用 AdMob（可后续接国内 SDK）。
/// iOS：始终视为 `global`。
class AppMarket {
  AppMarket._();

  static String _value = 'global';

  static String get value => _value;

  static bool get adMobEnabled => _value != 'china';

  static Future<void> init() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) {
      _value = 'global';
      return;
    }
    try {
      const channel = MethodChannel('camera_service');
      final s = await channel.invokeMethod<String>('getAppMarket');
      if (s == null || s.isEmpty) {
        _value = 'global';
      } else {
        _value = s;
      }
    } catch (_) {
      _value = 'global';
    }
  }
}
