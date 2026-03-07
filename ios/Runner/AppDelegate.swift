import Flutter
import UIKit
import FirebaseCore
import UserNotifications
import CallKit

// 通过 CallKit 上报“正在通话”，使 iOS 在锁屏/后台时仍保持应用运行，从而持续采集
class CallKitHelper: NSObject {
  private var provider: CXProvider?
  private var callController: CXCallController?
  private var currentCallUUID: UUID?
  private let callKitQueue = DispatchQueue(label: "com.rephone.callkit")
  private var startCallCompletion: ((Bool) -> Void)?

  func reportOngoingCall(completion: @escaping (Bool) -> Void) {
    callKitQueue.async { [weak self] in
      guard let self = self else { completion(false); return }
      if self.currentCallUUID != nil {
        completion(true)
        return
      }
      let uuid = UUID()
      self.currentCallUUID = uuid
      let config = CXProviderConfiguration(localizedName: "RePhone Camera")
      config.supportsVideo = true
      config.maximumCallsPerCallGroup = 1
      let provider = CXProvider(configuration: config)
      provider.setDelegate(self, queue: self.callKitQueue)
      self.provider = provider
      self.callController = CXCallController()
      self.startCallCompletion = completion

      let handle = CXHandle(type: .generic, value: "Monitor")
      let startAction = CXStartCallAction(call: uuid, handle: handle)
      startAction.isVideo = true
      let transaction = CXTransaction(action: startAction)
      self.callController?.request(transaction) { [weak self] error in
        if error != nil {
          self?.currentCallUUID = nil
          self?.startCallCompletion = nil
          DispatchQueue.main.async { completion(false) }
        }
      }
    }
  }

  func endOngoingCall(completion: ((Bool) -> Void)? = nil) {
    callKitQueue.async { [weak self] in
      guard let self = self, let uuid = self.currentCallUUID else {
        DispatchQueue.main.async { completion?(true) }
        return
      }
      let endAction = CXEndCallAction(call: uuid)
      let transaction = CXTransaction(action: endAction)
      self.callController?.request(transaction) { _ in }
      self.provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      self.currentCallUUID = nil
      self.provider = nil
      DispatchQueue.main.async { completion?(true) }
    }
  }
}

extension CallKitHelper: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    currentCallUUID = nil
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    action.fulfill()
    provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
    if let comp = startCallCompletion {
      startCallCompletion = nil
      DispatchQueue.main.async { comp(true) }
    }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    currentCallUUID = nil
    action.fulfill()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let callKitHelper = CallKitHelper()

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
      guard let controller = window?.rootViewController as? FlutterViewController else { return }
      let channel = FlutterMethodChannel(name: "camera_service", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "reportOngoingCall":
          self?.callKitHelper.reportOngoingCall { success in result(success) }
        case "endOngoingCall":
          self?.callKitHelper.endOngoingCall { result($0) }
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
