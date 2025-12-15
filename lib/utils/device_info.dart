import 'dart:io';
import '../services/session_manager.dart';

class DeviceInfo {
  static String get label {
    return 'Flutter ' +
        Platform.operatingSystem +
        '(' +
        Platform.localHostname +
        ")";
  }

  static String get userAgent {
    // 注意：这是同步方法，但SessionManager.getUser()是异步的
    // 在实际使用中需要在连接前异步获取用户信息并缓存
    return 'flutter-webrtc/' + Platform.operatingSystem + '-plugin 0.0.1';
  }

  static String getUserAgentWithEmail(String email) {
    return 'flutter-webrtc/' + Platform.operatingSystem + '-plugin 0.0.1|email:$email';
  }
}
