import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../utils/log_utils.dart';

class PushService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

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

    final token = await _messaging.getToken();
    if (token != null) {
      LogUtils.i('PushService', 'FCM token: $token');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      LogUtils.i('PushService', 'Foreground message: ${message.messageId ?? ''}');
    });

    _initialized = true;
  }
}
