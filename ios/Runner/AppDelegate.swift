import Flutter
import UIKit
import FirebaseCore
import UserNotifications
import WebRTC
import flutter_webrtc

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// 常驻帧取样器。页面退出 / 重建流时必须 detach，否则 RTCVideoTrack 一直强引用它。
  private var frameTap: FrameTap?

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
    registerFrameTapChannel()
    if window?.rootViewController == nil {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        registerCameraServiceChannel()
        self.registerScreenWakeChannel()
        self.registerFrameTapChannel()
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

  // MARK: - rephone_frame_tap

  /// 人物检测取帧通道：常驻 RTCVideoRenderer，替代会泄漏 native renderer 的 captureFrame()
  private func registerFrameTapChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "rephone_frame_tap",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "attach":
        let args = call.arguments as? [String: Any]
        guard let trackId = args?["trackId"] as? String else {
          result(FlutterError(code: "NO_TRACK", message: "trackId missing", details: nil))
          return
        }
        let width = args?["width"] as? Int ?? 300
        let height = args?["height"] as? Int ?? 300
        guard let plugin = FlutterWebRTCPlugin.sharedSingleton(),
              let track = plugin.track(forId: trackId, peerConnectionId: nil) as? RTCVideoTrack else {
          result(FlutterError(code: "NO_TRACK", message: "video track not found: \(trackId)", details: nil))
          return
        }
        // 先摘旧 renderer 再挂新的：restartVideo() 会换 track，
        // 漏掉 detach 会让旧 RTCVideoTrack 一直强引用 FrameTap。
        self.frameTap?.detach()
        let tap = FrameTap(outWidth: width, outHeight: height)
        tap.attach(track)
        self.frameTap = tap
        result(true)

      case "detach":
        self.frameTap?.detach()
        self.frameTap = nil
        result(true)

      case "latest":
        guard let sample = self.frameTap?.take() else { result(nil); return }
        result([
          "width": sample.width,
          "height": sample.height,
          "rgb": FlutterStandardTypedData(bytes: Data(sample.rgb)),
        ])

      case "stats":
        result(self.frameTap?.stats() ?? ["attached": false])

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// MARK: -

/// 常驻帧取样器：往 `RTCVideoTrack` 上挂一个长期存在的 `RTCVideoRenderer`，
/// 在 `renderFrame` 里把当前帧降采样成模型输入尺寸的 RGB 缩略图并缓存，
/// Dart 侧按需取「最新一帧」。
///
/// ### 为什么不用 `MediaStreamTrack.captureFrame()`
/// flutter_webrtc 的 `FlutterRTCFrameCapturer` 每次调用都 `addRenderer`，
/// 只有收到第一帧才 `removeRenderer`；轨道无帧时既不注销也不回调，Future 会永久挂起，
/// 10s 一次的检测会持续堆积 renderer。本类只 add/remove 一次，且不持有 FlutterResult。
///
/// ### 约束
/// 1. `detach()` 必须在页面销毁 / 释放资源 / **重建流之前** 调用；
/// 2. `RTCVideoTrack` 被更换（`Signaling.restartVideo()`）后必须重新 `attach()`。
private final class FrameTap: NSObject, RTCVideoRenderer {
  private let outWidth: Int
  private let outHeight: Int
  private let minIntervalMs: Int64
  private let changeThreshold: Float

  private let lock = NSLock()
  private var track: RTCVideoTrack?
  private var latestRgb: [UInt8]?
  private var latestWidth: Int = 0
  private var latestHeight: Int = 0
  private var hasUpdate = false
  /// 上一次取样（而非上一次入库）的灰度，用作下一帧比较基线。
  private var prevGray: [UInt8]?
  private var lastProcessMs: Int64 = 0
  private var frameCount: Int64 = 0
  private var updateCount: Int64 = 0

  init(outWidth: Int, outHeight: Int, minIntervalMs: Int64 = 500, changeThreshold: Float = 3.0) {
    self.outWidth = outWidth
    self.outHeight = outHeight
    self.minIntervalMs = minIntervalMs
    self.changeThreshold = changeThreshold
    super.init()
  }

  func attach(_ videoTrack: RTCVideoTrack) {
    detach()
    lock.lock()
    latestRgb = nil
    prevGray = nil
    hasUpdate = false
    lock.unlock()

    track = videoTrack
    videoTrack.add(self)
    NSLog("[FrameTap] attached track=%@ out=%dx%d", videoTrack.trackId, outWidth, outHeight)
  }

  func detach() {
    if let current = track {
      current.remove(self)
    }
    track = nil
    lock.lock()
    latestRgb = nil
    prevGray = nil
    hasUpdate = false
    lock.unlock()
    NSLog("[FrameTap] detached")
  }

  /// 取最新一帧；返回 nil 表示画面没变化，Dart 侧应跳过本次推理。
  func take() -> (width: Int, height: Int, rgb: [UInt8])? {
    lock.lock()
    defer { lock.unlock() }
    guard hasUpdate, let rgb = latestRgb else { return nil }
    hasUpdate = false
    return (latestWidth, latestHeight, rgb)
  }

  func stats() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return ["attached": track != nil, "frames": frameCount, "updates": updateCount]
  }

  // MARK: RTCVideoRenderer

  func setSize(_ size: CGSize) {
    // no-op：我们只需要像素，不关心显示尺寸
  }

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame = frame else { return }

    lock.lock()
    frameCount += 1
    lock.unlock()

    // renderFrame 回调在 WebRTC 的视频线程上，这里必须快速返回，只做节流。
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    if now - lastProcessMs < minIntervalMs { return }
    lastProcessMs = now

    let rotation = frame.rotation.rawValue
    let swap = rotation == 90 || rotation == 270
    let dstW = swap ? outHeight : outWidth
    let dstH = swap ? outWidth : outHeight

    guard let rgb = sampleRgb(frame: frame, rotation: rotation, dstW: dstW, dstH: dstH),
          !rgb.isEmpty else { return }

    let gray = toGray(rgb)
    lock.lock()
    defer { lock.unlock() }
    // 基线每次取样都更新：缓慢变化（有人走近）会累积到超过阈值，
    // 不会因为「每帧变化都很小」而永远检测不到。
    let baseline = prevGray
    prevGray = gray
    let diff = baseline == nil ? Float.greatestFiniteMagnitude : meanAbsDiff(baseline!, gray)
    guard baseline == nil || diff >= changeThreshold else { return }

    latestRgb = rgb
    latestWidth = dstW
    latestHeight = dstH
    hasUpdate = true
    updateCount += 1
  }

  /// 把 I420 帧按 dstW×dstH 采样成 RGB 三通道。
  /// 全手工采样，不依赖 CIImage / UIImage / CGImage —— 后者正是旧方案的开销与泄漏源。
  private func sampleRgb(frame: RTCVideoFrame, rotation: Int, dstW: Int, dstH: Int) -> [UInt8]? {
    let i420 = frame.buffer.toI420()
    let srcW = Int(i420.width)
    let srcH = Int(i420.height)
    guard srcW > 0, srcH > 0 else { return nil }

    let yPtr = i420.dataY
    let uPtr = i420.dataU
    let vPtr = i420.dataV
    let sy = Int(i420.strideY)
    let su = Int(i420.strideU)
    let sv = Int(i420.strideV)

    var rgb = [UInt8](repeating: 0, count: dstW * dstH * 3)
    var o = 0
    for dy in 0..<dstH {
      let ny = (Float(dy) + 0.5) / Float(dstH)
      for dx in 0..<dstW {
        let nx = (Float(dx) + 0.5) / Float(dstW)
        // rotation = 显示前需要顺时针旋转的角度，这里反推源坐标。
        var sxN = nx
        var syN = ny
        switch rotation {
        case 90: sxN = ny; syN = 1 - nx
        case 180: sxN = 1 - nx; syN = 1 - ny
        case 270: sxN = 1 - ny; syN = nx
        default: break
        }
        let sx = min(srcW - 1, max(0, Int(sxN * Float(srcW))))
        let syy = min(srcH - 1, max(0, Int(syN * Float(srcH))))

        let yv = Int(yPtr[syy * sy + sx])
        let cu = Int(uPtr[(syy / 2) * su + (sx / 2)]) - 128
        let cv = Int(vPtr[(syy / 2) * sv + (sx / 2)]) - 128
        let c = yv - 16
        // BT.601 full-range YUV -> RGB
        rgb[o] = UInt8(clamping: (298 * c + 409 * cv + 128) >> 8)
        rgb[o + 1] = UInt8(clamping: (298 * c - 100 * cu - 208 * cv + 128) >> 8)
        rgb[o + 2] = UInt8(clamping: (298 * c + 516 * cu + 128) >> 8)
        o += 3
      }
    }
    return rgb
  }

  private func toGray(_ rgb: [UInt8]) -> [UInt8] {
    var gray = [UInt8](repeating: 0, count: rgb.count / 3)
    var i = 0
    var j = 0
    while i + 2 < rgb.count {
      let r = Int(rgb[i])
      let g = Int(rgb[i + 1])
      let b = Int(rgb[i + 2])
      gray[j] = UInt8(clamping: (r * 77 + g * 150 + b * 29) >> 8)
      i += 3
      j += 1
    }
    return gray
  }

  private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return Float.greatestFiniteMagnitude }
    var sum = 0
    for i in 0..<a.count {
      sum += abs(Int(a[i]) - Int(b[i]))
    }
    return Float(sum) / Float(a.count)
  }
}
