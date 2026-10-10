import '../service_facades.dart';
import '../../services/push_service.dart' as legacy;

/// 海外版推送实现：直接复用现有 legacy `PushService`（FCM）。
///
/// 新业务代码统一走 [PushService] 门面；`services/push_service.dart` 只保留底层 FCM 细节，
/// 以便未来替换成其他 Push 提供商时不动业务代码。
///
/// 注：本文件只应被 `main.dart`（海外入口）import；
/// 国内入口 `main_china.dart` 不得引用本文件，从而不会带上 FCM / Firebase Messaging。
class GlobalFcmPushService implements PushService {
  @override
  Future<void> init() async {
    await legacy.PushService.init();
  }

  @override
  Future<void> reportTokenForLoggedInMonitor({String? forceToken}) async {
    await legacy.PushService.reportTokenForLoggedInMonitor(
        forceToken: forceToken);
  }

  @override
  Future<bool> requestNotificationPermission() async {
    // 只返回当前状态：实际申请必须由业务页面先弹出用途说明弹窗后
    // 通过 `PermissionManager` 触发，避免「未告知即索取权限」。
    try {
      await init();
      return legacy.PushService.hasNotificationPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> registerMonitorPushIfNeeded() async {
    await init();
    await reportTokenForLoggedInMonitor();
  }
}
