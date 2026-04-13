import Flutter
import UIKit
import FirebaseCore
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    GeneratedPluginRegistrant.register(with: self)

    func registerCameraServiceChannel() {
      // CallKit 功能已移除，此通道保留占位以避免 Flutter 侧旧代码调用崩溃
      guard let controller = window?.rootViewController as? FlutterViewController else { return }
      let channel = FlutterMethodChannel(name: "camera_service", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getAppMarket":
          result("global")
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    registerCameraServiceChannel()
    registerScreenWakeChannel()
    if window?.rootViewController == nil {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        registerCameraServiceChannel()
        self.registerScreenWakeChannel()
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 当 wakelock_plus 的 channel 不可用时，用系统 API 防止熄屏（仅用于熄屏模式）
  private func registerScreenWakeChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "rephone_screen_wake", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setIdleTimerDisabled",
            let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = enabled
        result(true)
      }
    }
  }
}
