import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../services/session_manager.dart';

class DeviceInfo {
  static const String _deviceIdKeyPrefix = 'device_id_';
  
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
  
  /// 获取或生成固定的设备ID
  /// [deviceType] 设备类型：'camera' 或 'monitor'
  /// 返回格式：{设备唯一标识的hash}_{角色}_{6位随机数}
  static Future<String> getOrCreateDeviceId(String deviceType) async {
    if (deviceType != 'camera' && deviceType != 'monitor') {
      throw ArgumentError('deviceType must be "camera" or "monitor"');
    }
    
    final key = '$_deviceIdKeyPrefix$deviceType';
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedId = prefs.getString(key);
      
      if (cachedId != null && cachedId.isNotEmpty) {
        print('DeviceInfo: Using cached device ID for $deviceType: $cachedId');
        return cachedId;
      }
      
      // 生成新的设备ID
      final deviceId = await _generateDeviceId(deviceType);
      
      // 保存到本地
      await prefs.setString(key, deviceId);
      print('DeviceInfo: Generated new device ID for $deviceType: $deviceId');
      
      return deviceId;
    } catch (e) {
      print('DeviceInfo: Error getting device ID, using fallback: $e');
      // 如果出错，使用基于时间的fallback
      return _generateFallbackId(deviceType);
    }
  }
  
  /// 生成设备ID
  static Future<String> _generateDeviceId(String deviceType) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceIdentifier = '';
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // 使用 Android ID 作为设备唯一标识
        deviceIdentifier = androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // 使用 identifierForVendor 作为设备唯一标识
        deviceIdentifier = iosInfo.identifierForVendor ?? '';
      } else {
        // 其他平台使用 hostname
        deviceIdentifier = Platform.localHostname;
      }
      
      // 如果设备标识为空，使用hostname作为fallback
      if (deviceIdentifier.isEmpty) {
        deviceIdentifier = Platform.localHostname;
      }
      
      // 生成设备标识的hash（取前8位）
      final hash = _simpleHash(deviceIdentifier);
      final hashStr = hash.toString().padLeft(8, '0').substring(0, 8);
      
      // 生成6位随机数（用于区分同一设备的多次安装）
      final random = Random();
      final randomSuffix = random.nextInt(1000000).toString().padLeft(6, '0');
      
      // 组合：{hash}_{role}_{random}
      final deviceId = '${hashStr}_$deviceType$randomSuffix';
      
      return deviceId;
    } catch (e) {
      print('DeviceInfo: Error generating device ID: $e');
      return _generateFallbackId(deviceType);
    }
  }
  
  /// 生成fallback ID（当无法获取设备信息时）
  static String _generateFallbackId(String deviceType) {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = _simpleHash(timestamp.toString());
    final hashStr = hash.toString().padLeft(8, '0').substring(0, 8);
    final randomSuffix = random.nextInt(1000000).toString().padLeft(6, '0');
    return '${hashStr}_$deviceType$randomSuffix';
  }
  
  /// 简单的hash函数
  static int _simpleHash(String input) {
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash) + input.codeUnitAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash.abs();
  }
  
  /// 清除设备ID（用于测试或重置）
  static Future<void> clearDeviceId(String deviceType) async {
    try {
      final key = '$_deviceIdKeyPrefix$deviceType';
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      print('DeviceInfo: Cleared device ID for $deviceType');
    } catch (e) {
      print('DeviceInfo: Error clearing device ID: $e');
    }
  }
  
  /// 获取当前设备ID（不生成新的）
  static Future<String?> getCurrentDeviceId(String deviceType) async {
    try {
      final key = '$_deviceIdKeyPrefix$deviceType';
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      print('DeviceInfo: Error getting current device ID: $e');
      return null;
    }
  }
}
