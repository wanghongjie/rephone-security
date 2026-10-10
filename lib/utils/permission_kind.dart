import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 需要向用户说明用途的权限类型。
///
/// 合规要求（工信部信管〔2020〕164 号 / 小米开发者生态政策）：
/// 每次调起系统权限弹窗之前，必须先通过**自定义弹窗**同步告知用户
/// 「申请的是什么权限」「用来做什么」「涉及哪些信息」，由用户确认后才允许申请。
enum AppPermissionKind {
  /// 相机
  camera,

  /// 麦克风
  microphone,

  /// 相机 + 麦克风（一次性合并申请，只弹一次说明弹窗）
  cameraAndMicrophone,

  /// 相册 / 存储（保存录像、截图）
  photos,

  /// 通知（后台监控状态 + 告警推送）
  notification,

  /// 忽略电池优化（保持后台监控连接）
  batteryOptimization,
}

/// [AppPermissionKind] 与文案、图标的映射。
class PermissionKindText {
  PermissionKindText._();

  static IconData icon(AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.camera:
      case AppPermissionKind.cameraAndMicrophone:
        return Icons.videocam_outlined;
      case AppPermissionKind.microphone:
        return Icons.mic_none;
      case AppPermissionKind.photos:
        return Icons.photo_library_outlined;
      case AppPermissionKind.notification:
        return Icons.notifications_none;
      case AppPermissionKind.batteryOptimization:
        return Icons.battery_saver_outlined;
    }
  }

  static String title(AppLocalizations l, AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.camera:
        return l.permissionTitleCamera;
      case AppPermissionKind.microphone:
        return l.permissionTitleMicrophone;
      case AppPermissionKind.cameraAndMicrophone:
        return l.permissionTitleCameraMic;
      case AppPermissionKind.photos:
        return l.permissionTitlePhotos;
      case AppPermissionKind.notification:
        return l.permissionTitleNotification;
      case AppPermissionKind.batteryOptimization:
        return l.permissionTitleBattery;
    }
  }

  /// 索取权限的目的（必须让用户看懂「为什么要给」）。
  static String purpose(AppLocalizations l, AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.camera:
        return l.permissionPurposeCamera;
      case AppPermissionKind.microphone:
        return l.permissionPurposeMicrophone;
      case AppPermissionKind.cameraAndMicrophone:
        return '${l.permissionPurposeCamera}\n${l.permissionPurposeMicrophone}';
      case AppPermissionKind.photos:
        return l.permissionPurposePhotos;
      case AppPermissionKind.notification:
        return l.permissionPurposeNotification;
      case AppPermissionKind.batteryOptimization:
        return l.permissionPurposeBattery;
    }
  }

  /// 该权限会涉及到的用户信息。
  static String scope(AppLocalizations l, AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.camera:
        return l.permissionScopeCamera;
      case AppPermissionKind.microphone:
        return l.permissionScopeMicrophone;
      case AppPermissionKind.cameraAndMicrophone:
        return '${l.permissionScopeCamera}\n${l.permissionScopeMicrophone}';
      case AppPermissionKind.photos:
        return l.permissionScopePhotos;
      case AppPermissionKind.notification:
        return l.permissionScopeNotification;
      case AppPermissionKind.batteryOptimization:
        return l.permissionScopeBattery;
    }
  }
}
