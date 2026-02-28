import 'dart:convert';
import 'dart:io';

import '../config/server_config.dart';
import '../utils/log_utils.dart';

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
      
      final body = {
        'email': email,
      };
      
      LogUtils.d('PaymentApi', 'Refreshing subscription: $body');
      req.write(jsonEncode(body));
      
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Refresh response: ${resp.statusCode} $text');
      
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
