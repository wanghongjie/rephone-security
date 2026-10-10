import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../widgets/permission_rationale_dialog.dart';
import 'permission_kind.dart';

/// 统一的运行时权限申请入口。
///
/// 合规要求（工信部信管〔2020〕164 号 / 小米开发者生态政策）：
/// 1. 调起系统权限弹窗**之前**，必须先弹自定义弹窗同步告知索取权限的目的；
/// 2. 用户明确拒绝后不得反复弹窗骚扰（不强制、不频繁）；
/// 3. 权限被永久拒绝时不再触发系统弹窗，改为引导用户去系统设置。
///
/// 业务页面统一调用 [PermissionManager.ensure]，不要自己直接调用
/// `Permission.xxx.request()`，以保证每一处申请都带用途说明。
class PermissionManager {
  PermissionManager._();

  static const MethodChannel _platformChannel = MethodChannel('camera_service');

  /// 同一权限的并发申请去重，避免同时弹出多个说明弹窗。
  static final Map<AppPermissionKind, Future<bool>> _pending = {};

  /// 电池优化属于「非必要、且由页面自动触发」的权限，
  /// 用户拒绝后 3 天内不再自动提示，避免频繁索要。
  static const Duration _batteryDeclineCooldown = Duration(days: 3);

  /// 本次 App 进程内已经提示过的权限（目前只对电池优化生效）。
  static final Set<AppPermissionKind> _promptedInSession = {};

  /// 申请权限：已授权直接返回 `true`；否则先弹自定义说明弹窗，
  /// 用户点击「同意并继续」后才调起系统权限弹窗。
  ///
  /// - [guideToSettingsOnDeny]：系统弹窗被拒绝后，是否额外弹一个
  ///   「去系统设置开启」的引导弹窗（仅用于用户主动点击触发的场景）。
  /// - 返回值：`true` 表示权限已获得。
  static Future<bool> ensure(
    BuildContext context,
    AppPermissionKind kind, {
    bool guideToSettingsOnDeny = false,
  }) async {
    final pending = _pending[kind];
    if (pending != null) return pending;

    final future = _ensure(
      context,
      kind,
      guideToSettingsOnDeny: guideToSettingsOnDeny,
    );
    _pending[kind] = future;
    try {
      return await future;
    } finally {
      _pending.remove(kind);
    }
  }

  /// 当前是否已拥有该权限（不弹任何弹窗）。
  static Future<bool> isGranted(AppPermissionKind kind) => _isGranted(kind);

  static Future<bool> _ensure(
    BuildContext context,
    AppPermissionKind kind, {
    required bool guideToSettingsOnDeny,
  }) async {
    if (await _isGranted(kind)) return true;

    // 已被永久拒绝（用户勾选「不再询问」）：不再触发系统弹窗，避免频繁索要。
    if (await _isPermanentlyDenied(kind)) {
      if (context.mounted) await _showSettingsGuide(context);
      return false;
    }

    // 电池优化属于非必需的增强项，且由页面自动触发：
    // 每次 App 进程内最多提示一次，近期被拒绝过则不再打扰，避免「频繁索要」。
    if (kind == AppPermissionKind.batteryOptimization) {
      if (_promptedInSession.contains(kind)) return false;
      if (await _isRecentlyDeclined(kind)) return false;
    }

    if (!context.mounted) return false;
    final agreed = await PermissionRationaleDialog.show(context, kind);

    // 只有**真正弹过窗**才消耗「本次进程一次」的名额。
    //
    // 之前是弹窗之前就 add，结果：授予相机/麦克风权限时 Android 会重建 Activity，
    // 走到电池优化这一步时 context 往往已失效并被上面的 `!context.mounted` 拦下，
    // 名额却被白白消耗 → 表现为「第一次进相机端不弹，下次进来才弹」。
    if (kind == AppPermissionKind.batteryOptimization) {
      _promptedInSession.add(kind);
    }

    if (agreed != true) {
      await _markDeclined(kind);
      return false;
    }

    final granted = await _requestSystemPermission(kind);
    if (granted) return true;

    if (!context.mounted) return false;
    if (guideToSettingsOnDeny) {
      await _showSettingsGuide(context);
    }
    return false;
  }

  /// 引导用户去系统设置开启权限（含明确的「取消」按钮，不强制跳转）。
  static Future<void> _showSettingsGuide(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.appPermissionsDeniedHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.appPermissionsOpenSettings),
          ),
        ],
      ),
    );
    if (go == true) {
      await openAppSettings();
    }
  }

  // —————————————————————————— 状态查询 ——————————————————————————

  static Future<bool> _isGranted(AppPermissionKind kind) async {
    switch (kind) {
      case AppPermissionKind.camera:
        return (await Permission.camera.status).isGranted;
      case AppPermissionKind.microphone:
        return (await Permission.microphone.status).isGranted;
      case AppPermissionKind.cameraAndMicrophone:
        final camera = await Permission.camera.status;
        final mic = await Permission.microphone.status;
        return camera.isGranted && mic.isGranted;
      case AppPermissionKind.photos:
        return _isGalleryGranted();
      case AppPermissionKind.notification:
        if (Platform.isAndroid) {
          try {
            return await _platformChannel
                    .invokeMethod<bool>('checkNotificationPermission') ??
                false;
          } catch (_) {
            return (await Permission.notification.status).isGranted;
          }
        }
        final status = await Permission.notification.status;
        return status.isGranted || status.isLimited;
      case AppPermissionKind.batteryOptimization:
        if (!Platform.isAndroid) return true;
        try {
          return await _platformChannel
                  .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
              false;
        } catch (_) {
          return false;
        }
    }
  }

  static Future<bool> _isGalleryGranted() async {
    if (Platform.isIOS) {
      final addOnly = await Permission.photosAddOnly.status;
      if (addOnly.isGranted || addOnly.isLimited) return true;
      final photos = await Permission.photos.status;
      return photos.isGranted || photos.isLimited;
    }
    if (Platform.isAndroid) {
      // Android 10+（API 29+）通过 MediaStore 保存到相册无需运行时权限。
      final sdk = await _androidSdkInt();
      if (sdk != null && sdk <= 28) {
        final storage = await Permission.storage.status;
        return storage.isGranted || storage.isLimited;
      }
      return true;
    }
    return true;
  }

  static Future<bool> _isPermanentlyDenied(AppPermissionKind kind) async {
    switch (kind) {
      case AppPermissionKind.camera:
        return (await Permission.camera.status).isPermanentlyDenied;
      case AppPermissionKind.microphone:
        return (await Permission.microphone.status).isPermanentlyDenied;
      case AppPermissionKind.cameraAndMicrophone:
        final camera = await Permission.camera.status;
        final mic = await Permission.microphone.status;
        return camera.isPermanentlyDenied || mic.isPermanentlyDenied;
      case AppPermissionKind.photos:
        if (Platform.isIOS) {
          final addOnly = await Permission.photosAddOnly.status;
          final photos = await Permission.photos.status;
          return addOnly.isPermanentlyDenied || photos.isPermanentlyDenied;
        }
        if (Platform.isAndroid) {
          final sdk = await _androidSdkInt();
          if (sdk != null && sdk <= 28) {
            return (await Permission.storage.status).isPermanentlyDenied;
          }
        }
        return false;
      case AppPermissionKind.notification:
        if (Platform.isAndroid) {
          final sdk = await _androidSdkInt();
          // Android 12 及以下没有通知运行时权限，不存在「不再询问」状态。
          if (sdk == null || sdk < 33) return false;
        }
        return (await Permission.notification.status).isPermanentlyDenied;
      case AppPermissionKind.batteryOptimization:
        return false;
    }
  }

  // —————————————————————————— 系统权限申请 ——————————————————————————

  static Future<bool> _requestSystemPermission(AppPermissionKind kind) async {
    switch (kind) {
      case AppPermissionKind.camera:
        return (await Permission.camera.request()).isGranted;
      case AppPermissionKind.microphone:
        return (await Permission.microphone.request()).isGranted;
      case AppPermissionKind.cameraAndMicrophone:
        final statuses =
            await <Permission>[Permission.camera, Permission.microphone].request();
        return statuses[Permission.camera]?.isGranted == true &&
            statuses[Permission.microphone]?.isGranted == true;
      case AppPermissionKind.photos:
        return _requestGalleryPermission();
      case AppPermissionKind.notification:
        return _requestNotificationPermission();
      case AppPermissionKind.batteryOptimization:
        return _requestBatteryOptimizationExemption();
    }
  }

  static Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final addOnly = await Permission.photosAddOnly.request();
      if (addOnly.isGranted || addOnly.isLimited) return true;
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }
    if (Platform.isAndroid) {
      final sdk = await _androidSdkInt();
      if (sdk != null && sdk <= 28) {
        final storage = await Permission.storage.request();
        return storage.isGranted || storage.isLimited;
      }
      return true;
    }
    return true;
  }

  static Future<bool> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      try {
        await _platformChannel.invokeMethod('requestNotificationPermission');
        // 系统弹窗是异步的：轮询等待用户做出选择（最多约 2s）再回读结果。
        //
        // 只等固定 800ms 时，用户往往还没点完，就会走到下面
        // Permission.notification.request()，于是**又弹一次**系统弹窗，
        // 表现为「刚给完通知权限又弹一次」，体验与合规观感都很差。
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final granted = await _platformChannel
                  .invokeMethod<bool>('checkNotificationPermission') ??
              false;
          if (granted) return true;
        }
      } catch (_) {
        // 原生通道不可用时回退到 permission_handler。
      }
    }
    final status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  }

  /// 电池优化豁免走的是系统设置页，无法同步拿到结果，
  /// 这里只负责「用户同意后」拉起系统页面，结果由调用方按需回查。
  static Future<bool> _requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;
    try {
      await _platformChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      return false;
    }
    return false;
  }

  // —————————————————————————— 拒绝冷却（防频繁索要）——————————————————————————

  static String _declineKey(AppPermissionKind kind) =>
      'permission_declined_at_${kind.name}';

  static Future<bool> _isRecentlyDeclined(AppPermissionKind kind) async {
    if (kind != AppPermissionKind.batteryOptimization) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_declineKey(kind));
      if (at == null) return false;
      final declinedAt = DateTime.fromMillisecondsSinceEpoch(at);
      return DateTime.now().difference(declinedAt) < _batteryDeclineCooldown;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markDeclined(AppPermissionKind kind) async {
    if (kind != AppPermissionKind.batteryOptimization) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _declineKey(kind),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // 记录失败不影响主流程。
    }
  }

  static int? _cachedSdkInt;

  static Future<int?> _androidSdkInt() async {
    if (!Platform.isAndroid) return null;
    final cached = _cachedSdkInt;
    if (cached != null) return cached;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _cachedSdkInt = info.version.sdkInt;
      return _cachedSdkInt;
    } catch (_) {
      return null;
    }
  }
}
