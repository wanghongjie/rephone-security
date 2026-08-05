import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/push_service.dart';
import 'app_market.dart';
import 'log_utils.dart';

bool get firebaseEnabled => AppMarket.value == 'global';
bool get membershipEnabled => AppMarket.value == 'global';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!firebaseEnabled) return;
  await Firebase.initializeApp();
  LogUtils.i('PushBackground', 'Message: ${message.messageId ?? ''}');
}

/// Camera 端不需要 FCM；仅在确认 [SessionManager] 角色为 monitor 后注册。
bool _monitorPushRegistrationDone = false;

Future<void> registerMonitorPushIfNeeded() async {
  if (!firebaseEnabled) return;
  if (_monitorPushRegistrationDone) return;
  _monitorPushRegistrationDone = true;
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await PushService.init();
}
