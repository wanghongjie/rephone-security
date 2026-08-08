import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';

/// Android：`global` flavor 使用 AdMob；`china` 不使用 AdMob（可后续接国内 SDK）。
/// iOS：若未显式通过 `MARKET` 注入，则默认视为 `global`。
///
/// 单一事实来源：以 `--dart-define=MARKET=china|global` 为准；
/// 平台侧 `getAppMarket` 仅用于 Debug 模式下的错位校验，避免入口(-t)与 flavor 不匹配。
class AppMarket {
  AppMarket._();

  static const String _kEnvMarket = String.fromEnvironment('MARKET', defaultValue: '');

  static String _value = 'global';

  /// 当前市场：`global` / `china`。
  static String get value => _value;

  /// 仅 global 市场启用 Google Mobile Ads。
  static bool get adMobEnabled => _value != 'china';

  static Future<void> init() async {
    _value = _resolveFromEnv();

    String? platformMarket;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('camera_service');
        platformMarket = await channel.invokeMethod<String>('getAppMarket');
      } catch (_) {
        platformMarket = null;
      }
    }

    if (kDebugMode) {
      _assertNoMisMatch(
        envMarket: const String.fromEnvironment('MARKET', defaultValue: ''),
        platformMarket: platformMarket,
      );
    }
  }

  static String _resolveFromEnv() {
    final raw = _kEnvMarket.trim().toLowerCase();
    if (raw == 'china') return 'china';
    if (raw == 'global') return 'global';
    // 未传 MARKET 时保持默认：兼容旧的构建方式
    return 'global';
  }

  static void _assertNoMisMatch({
    required String envMarket,
    required String? platformMarket,
  }) {
    if (envMarket.isEmpty) return;
    if (platformMarket == null || platformMarket.isEmpty) return;
    final env = envMarket.toLowerCase();
    final plat = platformMarket.toLowerCase();
    if (env != plat) {
      throw StateError(
        '[AppMarket] 构建参数与平台 flavor 不一致：'
        'MARKET=$env vs platform($plat)。请使用 scripts/build_flavors.sh 构建。',
      );
    }
  }
}
