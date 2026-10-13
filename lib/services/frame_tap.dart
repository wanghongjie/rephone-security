import 'package:flutter/services.dart';

import '../utils/log_utils.dart';

/// 一帧来自原生侧的 RGB 缩略图（`rephone_frame_tap` 通道的返回结构）。
class FrameSample {
  const FrameSample({
    required this.width,
    required this.height,
    required this.rgb,
  });

  final int width;
  final int height;

  /// 长度恒为 `width * height * 3`，通道顺序 RGB。
  final Uint8List rgb;
}

/// 人物检测取帧通道。
///
/// 与 `MediaStreamTrack.captureFrame()` 的本质区别：原生侧是一个**常驻**的
/// VideoSink / RTCVideoRenderer，帧一直在缓存里更新，Dart 侧只按需取「最新一帧」。
///
/// 而 `captureFrame()` 每次调用都会在 native 新建一个 sink，轨道无帧时既不回调
/// 也不注销（10s 一次的检测 = 每 10 秒泄漏一个 native sink，Android 旋转分支
/// 还会额外泄漏两张全分辨率 Bitmap）。
///
/// 使用方必须保证：track 被销毁或重建前调用 [detach]，否则原生轨道会一直
/// 强引用取样器。
class FrameTap {
  FrameTap._();

  static final FrameTap instance = FrameTap._();

  static const MethodChannel _channel = MethodChannel('rephone_frame_tap');

  /// 挂到 [trackId] 对应的本地视频轨道上，输出 `width x height` 的 RGB 缩略图。
  ///
  /// 重复调用是安全的：原生侧会先摘掉旧的 sink 再挂新的。
  /// 轨道不存在时返回 false（例如 WebRTC 尚未建连）。
  Future<bool> attach(String trackId, int width, int height) async {
    try {
      final result = await _channel.invokeMethod<bool>('attach', <String, dynamic>{
        'trackId': trackId,
        'width': width,
        'height': height,
      });
      return result ?? false;
    } on MissingPluginException catch (e) {
      LogUtils.w('FrameTap', 'channel not implemented on this platform: $e');
      return false;
    } on PlatformException catch (e) {
      LogUtils.w('FrameTap', 'attach failed: ${e.code} ${e.message}');
      return false;
    }
  }

  /// 摘掉 sink 并清空缓存。页面退出 / 释放资源 / 重建流之前必须调用。
  Future<void> detach() async {
    try {
      await _channel.invokeMethod<void>('detach');
    } on MissingPluginException {
      // 平台未实现，忽略
    } on PlatformException catch (e) {
      LogUtils.w('FrameTap', 'detach failed: ${e.code} ${e.message}');
    }
  }

  /// 取最新一帧。
  ///
  /// 返回 null 有两种含义，调用方都应当直接跳过本次推理：
  ///  * 还没有收到过任何帧；
  ///  * 画面相较上次取样没有变化（原生侧帧差判断）。
  Future<FrameSample?> latest() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('latest');
      if (result == null) return null;
      final rgb = result['rgb'];
      if (rgb is! Uint8List) return null;
      final width = result['width'];
      final height = result['height'];
      if (width is! int || height is! int) return null;
      return FrameSample(width: width, height: height, rgb: rgb);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      LogUtils.w('FrameTap', 'latest failed: ${e.code} ${e.message}');
      return null;
    }
  }

  /// 采样统计，用于验证「是否真的只挂了一个 sink / 缓存是否在更新」。
  /// Android 目前才有实现，iOS / 未实现平台返回 null。
  Future<Map<Object?, Object?>?> stats() async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>('stats');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
