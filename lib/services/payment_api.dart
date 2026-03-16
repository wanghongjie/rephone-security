import 'dart:convert';
import 'dart:io';

import '../config/server_config.dart';
import '../utils/log_utils.dart';
import '../utils/navigation_service.dart';
import 'session_manager.dart';

class PaymentApi {
  PaymentApi({
    String? host,
    int? port,
    bool? useHttps,
  })  : host = host ?? defaultAuthHost,
        port = port ?? defaultAuthPort,
        useHttps = useHttps ?? defaultAuthUseHttps;

  final String host;
  final int port;
  final bool useHttps;

  Uri _buildUri(String path) => Uri(
        scheme: useHttps ? 'https' : 'http',
        host: host,
        port: port,
        path: '/api/payment/$path',
      );

  Future<Map<String, dynamic>?> verifyGooglePurchase({
    required String orderId,
    required String productId,
    required String purchaseToken,
    required String email,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri('verify/google'));
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }
      
      final body = {
        'order_id': orderId,
        'product_id': productId,
        'purchase_token': purchaseToken,
        'email': email,
        'platform': 'android',
      };
      
      LogUtils.d('PaymentApi', 'Verifying purchase: $body');
      req.write(jsonEncode(body));
      
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Verify response: ${resp.statusCode} $text');
      
      if (resp.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(text);
          if (data['success'] == true || data['status'] == 'success') {
            return data;
          }
        } catch (_) {
          return null;
        }
      }
      if (resp.statusCode == 402) {
        return {'subscription_expired': true};
      }
      return null;
    } catch (e, st) {
      LogUtils.e('PaymentApi', 'Verify failed', e, st);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> verifyApplePurchase({
    required String transactionId,
    required String productId,
    required String receiptData,
    required String email,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri('verify/apple'));
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }

      final body = {
        'transaction_id': transactionId,
        'product_id': productId,
        'receipt_data': receiptData,
        'email': email,
        'platform': 'ios',
      };

      LogUtils.d('PaymentApi', 'Verifying purchase: $body');
      req.write(jsonEncode(body));

      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Verify response: ${resp.statusCode} $text');

      if (resp.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(text);
          if (data['success'] == true || data['status'] == 'success') {
            return data;
          }
        } catch (_) {
          return null;
        }
      }
      // 402 = subscription expired (e.g. restore of past subscription)
      if (resp.statusCode == 402) {
        return {'subscription_expired': true};
      }
      return null;
    } catch (e, st) {
      LogUtils.e('PaymentApi', 'Verify failed', e, st);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> refreshSubscription({
    required String email,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri('refresh'));
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }
      
      final body = {
        'email': email,
      };
      
      LogUtils.d('PaymentApi', 'Refreshing subscription: $body');
      req.write(jsonEncode(body));
      
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Refresh response: ${resp.statusCode} $text');
      
      if (resp.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(text);
          if (data['success'] == true || data['status'] == 'success') {
            return data;
          }
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (e, st) {
      LogUtils.e('PaymentApi', 'Refresh failed', e, st);
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
