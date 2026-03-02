import 'dart:convert';
import 'dart:io';

import '../config/server_config.dart';
import 'session_manager.dart';

class FeedbackApi {
  FeedbackApi({
    String? host,
    int? port,
    bool? useHttps,
  })  : host = host ?? defaultAuthHost,
        port = port ?? defaultAuthPort,
        useHttps = useHttps ?? defaultAuthUseHttps;

  final String host;
  final int port;
  final bool useHttps;

  Uri _buildUri() => Uri(
        scheme: useHttps ? 'https' : 'http',
        host: host,
        port: port,
        path: '/api/feedback/submit',
      );

  Future<_HttpResult> _post(Map<String, dynamic> body) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri());
      req.headers.contentType = ContentType.json;
      final user = await SessionManager.getUser();
      if (user?.token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user!.token}');
      }
      req.write(jsonEncode(body));
      final resp = await req.close();
      final text = await utf8.decodeStream(resp);
      dynamic data;
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
      return _HttpResult(statusCode: resp.statusCode, data: data);
    } finally {
      client.close(force: true);
    }
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return fallback;
  }

  /// 提交意见反馈
  /// content: 必填，<= 5000
  /// email/device_id/contact: 可选
  Future<int?> submit({
    String? email,
    String? deviceId,
    required String content,
    String? contact,
  }) async {
    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty) {
      throw FeedbackApiException('content 必填');
    }
    if (trimmedContent.length > 5000) {
      throw FeedbackApiException('content 过长（最多 5000 字符）');
    }

    final body = <String, dynamic>{
      'content': trimmedContent,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'device_id': deviceId.trim(),
      if (contact != null && contact.trim().isNotEmpty) 'contact': contact.trim(),
    };

    final res = await _post(body);
    if (res.statusCode >= 400) {
      throw FeedbackApiException(_extractMessage(res.data, 'feedback submit failed'));
    }
    if (res.data is Map && res.data['success'] == false) {
      throw FeedbackApiException(_extractMessage(res.data, 'feedback submit failed'));
    }
    if (res.data is Map && res.data['data'] is Map) {
      final d = res.data['data'] as Map;
      final id = d['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
    }
    return null;
  }
}

class _HttpResult {
  _HttpResult({required this.statusCode, required this.data});
  final int statusCode;
  final dynamic data;
}

class FeedbackApiException implements Exception {
  FeedbackApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
