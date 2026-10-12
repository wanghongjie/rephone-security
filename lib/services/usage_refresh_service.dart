import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_market.dart';
import '../utils/log_utils.dart';

/// 应用自启动 / 关联启动开关（仅 Android + 国内版生效）。
///
/// 合规背景：工信部信管函〔2020〕164 号文第 6 项要求——
/// 「APP 未向用户告知且未经用户同意，或无合理的使用场景，频繁自启动或
/// 关联启动第三方 APP」属于违规。原生侧 [UsageRefreshManager] 的周期任务
/// （WorkManager）会在应用退出后被系统拉起，属于「应用自启动」行为。
///
/// 因此这里统一收敛两个约束：
/// 1. **明示**：隐私政策弹窗与《隐私政策》全文均已说明场景、目的、频率与必要性；
/// 2. **同意后 + 可关闭**：只有在用户点击隐私政策「同意」之后才注册周期任务，
///    且用户可随时在「通用设置 → 隐私设置 → 后台保活自启动」中关闭。
class UsageRefreshService {
  UsageRefreshService._();

  static const MethodChannel _platformChannel = MethodChannel('camera_service');

  static const String _keyAutoStartEnabled = 'usage_refresh_enabled';

  /// 是否允许后台保活自启动。
  ///
  /// 未做过选择时返回 `true`（隐私政策弹窗已明示，用户点「同意」即视为同意该行为）。
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoStartEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 设置是否允许后台保活自启动，并同步到原生侧。
  ///
  /// 原生侧收到后会据此注册或取消 WorkManager 周期任务；
  /// 同时仍受「隐私政策已同意」闸门约束，未同意前不会注册。
  static Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoStartEnabled, value);
    } catch (_) {
      // 存储失败不影响原生侧同步
    }
    await _syncToNative(value);
  }

  /// 把当前偏好同步到原生侧（同意隐私政策后调用）。
  static Future<void> sync() async {
    await _syncToNative(await isEnabled());
  }

  static Future<void> _syncToNative(bool value) async {
    if (!Platform.isAndroid) return;
    if (AppMarket.value.toLowerCase() != 'china') return;
    try {
      await _platformChannel.invokeMethod<bool>(
        'setUsageRefreshEnabled',
        {'enabled': value},
      );
      LogUtils.i('UsageRefreshService', 'setUsageRefreshEnabled($value) ok');
    } catch (e, st) {
      LogUtils.e('UsageRefreshService', 'setUsageRefreshEnabled failed', e, st);
    }
  }
}
