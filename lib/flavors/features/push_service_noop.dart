import 'package:flutter/material.dart';

import '../service_facades.dart';

/// 国内版 / 通用的推送空实现：不初始化任何 SDK，也不上报 token。
///
/// 后续接入 HMS / 小米 / OPPO / vivo 等国内推送平台，
/// 可新建 `push_service_<vendor>.dart` 并在国内入口注入该实现。
///
/// 注：本文件不依赖 FCM / Firebase / 第三方 Push SDK，可安全被国内入口引用。
class NoopPushService implements PushService {
  @override
  Future<void> init() async {}

  @override
  Future<void> reportTokenForLoggedInMonitor({String? forceToken}) async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> registerMonitorPushIfNeeded() async {}
}
