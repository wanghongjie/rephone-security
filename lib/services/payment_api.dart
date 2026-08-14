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
    String? basePlanId,
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
        'base_plan_id': basePlanId,
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

  // —————————— 微信支付（国内版） ——————————

  /// 创建微信 APP 支付订单 → 返回调起 SDK 所需的参数（含 out_trade_no 和 params Map）。
  ///
  /// 后端接口：POST /api/payment/wechat/create-order（已挂 AuthMiddleware，需带 Bearer Token）。
  ///
  /// 返回结构（成功时）：
  /// ```dart
  /// {
  ///   'success': true,
  ///   'data': {
  ///     'out_trade_no': 'wx2026...',
  ///     'params': {                // 可直接丢给 fluwx.payWithWeChat 的 PayWithWeChat 参数
  ///       'app_id': 'wx123',
  ///       'partner_id': '1600000000',
  ///       'prepay_id': 'wx123...',
  ///       'package': 'Sign=WXPay',
  ///       'nonce_str': 'abcd...',
  ///       'timestamp': '1234567890',
  ///       'sign': 'xxxx',
  ///     }
  ///   }
  /// }
  /// ```
  Future<Map<String, dynamic>?> createWechatOrder({
    required String productId,
    required String plan,
    required String email,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri('wechat/create-order'));
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }

      final body = {
        'product_id': productId,
        'plan': plan,
        'email': email,
      };

      LogUtils.d('PaymentApi', 'Create WeChat order: $body');
      req.write(jsonEncode(body));

      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Create WeChat order response: ${resp.statusCode} $text');

      if (resp.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(text);
          if (data['success'] == true) {
            return data['data'] as Map<String, dynamic>;
          }
        } catch (e) {
          LogUtils.e('PaymentApi', 'Create WeChat order parse failed', e);
        }
      }
      return null;
    } catch (e, st) {
      LogUtils.e('PaymentApi', 'Create WeChat order failed', e, st);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 客户端自报「微信 SDK 回调显示支付成功」→ 服务端不信任前端，
  /// 实际会主动查单或等待异步回调，本接口用于加速权益发放过程。
  ///
  /// 后端接口：POST /api/payment/wechat/verify（已挂 AuthMiddleware）。
  Future<Map<String, dynamic>?> verifyWechatOrder({
    required String outTradeNo,
    required String email,
    String? transactionId,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri('wechat/verify'));
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }

      final body = <String, dynamic>{
        'out_trade_no': outTradeNo,
        'email': email,
      };
      if (transactionId != null && transactionId.isNotEmpty) {
        body['transaction_id'] = transactionId;
      }

      LogUtils.d('PaymentApi', 'Verify WeChat order: $body');
      req.write(jsonEncode(body));

      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Verify WeChat order response: ${resp.statusCode} $text');

      if (resp.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(text);
          if (data['success'] == true) {
            return data['data'] as Map<String, dynamic>;
          }
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (e, st) {
      LogUtils.e('PaymentApi', 'Verify WeChat order failed', e, st);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 兜底查单：页面卡死或长期未收到 notify / verify 成功时，
  /// 客户端轮询此接口确认最终支付状态。
  ///
  /// 后端接口：POST /api/payment/wechat/query（已挂 AuthMiddleware）。
  Future<Map<String, dynamic>?> queryWechatOrder({
    required String outTradeNo,
    required String email,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri('wechat/query'));
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }

      final body = {
        'out_trade_no': outTradeNo,
        'email': email,
      };

      LogUtils.d('PaymentApi', 'Query WeChat order: $body');
      req.write(jsonEncode(body));

      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      LogUtils.d('PaymentApi', 'Query WeChat order response: ${resp.statusCode} $text');

      if (resp.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(text);
          if (data['success'] == true) {
            return data['data'] as Map<String, dynamic>;
          }
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (e, st) {
      LogUtils.e('PaymentApi', 'Query WeChat order failed', e, st);
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
