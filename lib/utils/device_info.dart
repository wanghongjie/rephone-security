import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/session_manager.dart';
import 'log_utils.dart';

class DeviceInfo {
  static const String _deviceIdKeyPrefix = 'device_id_';
  /// Android 专用：同型号部分机型 ANDROID_ID 会重复，用此 key 存一份“设备唯一种子”参与生成 ID
  static const String _androidDeviceSeedKey = 'device_unique_seed_android';
  
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
        LogUtils.i('DeviceInfo', 'Using cached device ID for $deviceType: $cachedId');
        return cachedId;
      }
      
      // Android：同型号部分机型 ANDROID_ID 相同，用“设备唯一种子”参与生成，保证每台设备不同
      String? androidSeed;
      if (Platform.isAndroid) {
        androidSeed = prefs.getString(_androidDeviceSeedKey);
        if (androidSeed == null || androidSeed.isEmpty) {
          androidSeed = _generateSecureRandomSeed();
          await prefs.setString(_androidDeviceSeedKey, androidSeed);
        }
      }
      
      // 生成新的设备ID
      final deviceId = await _generateDeviceId(deviceType, androidSeed);
      
      // 保存到本地
      await prefs.setString(key, deviceId);
      LogUtils.i('DeviceInfo', 'Generated new device ID for $deviceType: $deviceId');
      
      return deviceId;
    } catch (e) {
      LogUtils.e('DeviceInfo', 'Error getting device ID, using fallback', e);
      // 如果出错，使用基于时间的fallback
      return _generateFallbackId(deviceType);
    }
  }
  
  /// 生成设备ID
  /// [androidSeed] 仅 Android 使用：与 ANDROID_ID 组合，避免同型号机型 ANDROID_ID 重复导致 ID 相同
  static Future<String> _generateDeviceId(String deviceType, [String? androidSeed]) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceIdentifier = '';
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Android ID 在部分机型（如部分华为同型号）会重复，叠加设备唯一种子保证唯一
        deviceIdentifier = androidInfo.id;
        if (androidSeed != null && androidSeed.isNotEmpty) {
          deviceIdentifier = '${deviceIdentifier}_$androidSeed';
        }
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
      
      // 组合：{hash}_{role}
      final deviceId = '${hashStr}_$deviceType';
      
      return deviceId;
    } catch (e) {
      LogUtils.e('DeviceInfo', 'Error generating device ID', e);
      return _generateFallbackId(deviceType);
    }
  }
  
  /// 生成fallback ID（当无法获取设备信息时）
  static String _generateFallbackId(String deviceType) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hash = _simpleHash(timestamp.toString());
    final hashStr = hash.toString().padLeft(8, '0').substring(0, 8);
    return '${hashStr}_$deviceType';
  }
  
  /// 生成一次性的随机种子（用于 Android 设备唯一 ID 的补充）
  static String _generateSecureRandomSeed() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
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
      LogUtils.i('DeviceInfo', 'Cleared device ID for $deviceType');
    } catch (e) {
      LogUtils.e('DeviceInfo', 'Error clearing device ID', e);
    }
  }

  /// 获取可读设备名称（用于默认相机名称）
  static Future<String> getReadableDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final brand = android.brand ?? '';
        final model = android.model ?? '';
        final result = [brand, model].where((s) => s.isNotEmpty).join(' ');
        if (result.isNotEmpty) return result;
        return 'Android device';
      }
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        final name = ios.name ?? '';
        final model = ios.model ?? '';
        if (name.isNotEmpty) return name;
        if (model.isNotEmpty) return model;
        return 'iPhone';
      }
      return Platform.localHostname;
    } catch (e) {
      LogUtils.e('DeviceInfo', 'Error getting readable device name', e);
      return 'Camera device';
    }
  }
  
  /// 获取当前设备ID（不生成新的）
  static Future<String?> getCurrentDeviceId(String deviceType) async {
    try {
      final key = '$_deviceIdKeyPrefix$deviceType';
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      LogUtils.e('DeviceInfo', 'Error getting current device ID', e);
      return null;
    }
  }
}
