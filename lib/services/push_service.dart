import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../models/auth_user.dart';
import '../utils/log_utils.dart';
import '../utils/navigation_service.dart';
import 'session_manager.dart';

class PushService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;
  static const MethodChannel _platformChannel = MethodChannel('camera_service');
  static Future<void>? _pendingTokenReport;

  static Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      final hasPlayServices = await _isGooglePlayServicesAvailable();
      if (!hasPlayServices) {
        LogUtils.w(
          'PushService',
          'Google Play services not available, skip FCM initialization',
        );
        return;
      }
    }

    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      LogUtils.i('PushService', 'iOS permission: ${settings.authorizationStatus}');
    } else {
      final settings = await _messaging.requestPermission();
      LogUtils.i('PushService', 'Android permission: ${settings.authorizationStatus}');
    }

    await _messaging.setAutoInitEnabled(true);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      LogUtils.i('PushService', 'Foreground message: ${message.messageId ?? ''}');
    });

    _messaging.onTokenRefresh.listen((String newToken) async {
      LogUtils.i('PushService', 'FCM token refreshed: $newToken');
      await reportTokenForLoggedInMonitor(forceToken: newToken);
    });

    // 如果已经是登录状态，并且是 monitor 端，启动时主动刷新一次 token
    reportTokenForLoggedInMonitor();

    _initialized = true;
  }

  static Future<bool> _isGooglePlayServicesAvailable() async {
    try {
      final result = await _platformChannel.invokeMethod<bool>(
        'isGooglePlayServicesAvailable',
      );
      final available = result ?? false;
      LogUtils.i(
        'PushService',
        'Google Play services availability (Android): $available',
      );
      return available;
    } catch (e, st) {
      LogUtils.e(
        'PushService',
        'Failed to check Google Play services availability',
        e,
        st,
      );
      return false;
    }
  }

  static Future<void> reportTokenForLoggedInMonitor({String? forceToken}) async {
    if (_pendingTokenReport != null) {
      await _pendingTokenReport;
      return;
    }
    final completer = _reportTokenForLoggedInMonitorInternal(forceToken: forceToken);
    _pendingTokenReport = completer;
    try {
      await completer;
    } finally {
      _pendingTokenReport = null;
    }
  }

  static Future<void> _reportTokenForLoggedInMonitorInternal({String? forceToken}) async {
    try {
      final user = await SessionManager.getUser();
      final role = await SessionManager.getDeviceRole() ?? 'monitor';
      if (user == null) {
        LogUtils.i('PushService', 'Skip reporting token: no logged in user');
        return;
      }
      if (role != 'monitor') {
        LogUtils.i(
          'PushService',
          'Skip reporting token for non-monitor role: $role',
        );
        return;
      }
      final token = forceToken ?? await _getFcmTokenWithRetry();
      if (token == null) {
        LogUtils.w('PushService', 'FCM token is null, cannot report');
        return;
      }
      await _reportTokenToBackend(token, user: user, role: role);
    } catch (e, st) {
      LogUtils.e('PushService', 'Failed to report FCM token', e, st);
    }
  }

  static Future<String?> _getFcmTokenWithRetry() async {
    const maxAttempts = 8;
    var delayMs = 300;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (Platform.isIOS) {
        try {
          final apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) {
            LogUtils.i('PushService', 'APNs token ready');
          }
        } on FirebaseException catch (e) {
          if (e.code != 'apns-token-not-set') {
            rethrow;
          }
        } catch (_) {}
      }

      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          return token;
        }
      } on FirebaseException catch (e) {
        if (!(Platform.isIOS && e.code == 'apns-token-not-set')) {
          LogUtils.w('PushService', 'FCM token error (attempt $attempt): ${e.message}');
          // 不立即抛出，继续重试
        }
      } catch (e) {
        LogUtils.w('PushService', 'FCM token error (attempt $attempt): $e');
        // 捕获所有其他异常（如网络超时），继续重试
      }

      await Future.delayed(Duration(milliseconds: delayMs));
      if (delayMs < 2000) {
        delayMs = (delayMs * 2).clamp(300, 2000);
      }
    }

    return null;
  }

  static Future<void> _reportTokenToBackend(
    String token, {
    required AuthUser user,
    required String role,
  }) async {
    try {
      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : Platform.operatingSystem;

      final body = <String, dynamic>{
        'email': user.email,
        'platform': platform,
        'fcm_token': token,
      };

      final uri = Uri.parse('https://rephone.top/api/push/register');

      final client = HttpClient();

      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (user.token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user.token}');
      }
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      if (response.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }
      if (response.statusCode >= 400) {
        final responseBody = await response.transform(utf8.decoder).join();
        LogUtils.w(
          'PushService',
          'Report token failed [${response.statusCode}]: $responseBody',
        );
      } else {
        LogUtils.i('PushService', 'Report token success');
      }

      client.close(force: true);
    } catch (e, st) {
      LogUtils.e('PushService', 'Failed to report FCM token to backend', e);
    }
  }
}
