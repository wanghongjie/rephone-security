import 'dart:convert';
import 'dart:io';

import '../config/server_config.dart';
import '../models/auth_user.dart';

/// Simple API client for auth endpoints, using host/port style like turn.dart.
/// Accepts self-signed certs for dev, matching existing TURN client behavior.
class AuthApi {
  AuthApi({
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
        path: '/api/auth/$path',
      );

  Future<_HttpResult> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri(path));
      req.headers.contentType = ContentType.json;
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

  Future<bool> checkEmail(String email) async {
    final res = await _post('check-email', {'email': email});
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '检查邮箱失败'));
    }
    if (res.data is Map &&
        (res.data['data'] is Map) &&
        res.data['data']['registered'] != null) {
      return res.data['data']['registered'] == true;
    }
    throw AuthApiException('响应格式错误');
  }

  Future<AuthUser> login(String email, String password) async {
    final res = await _post('login', {'email': email, 'password': password});
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '登录失败'));
    }
    if (res.data is Map && res.data['data'] is Map) {
      return AuthUser.fromJson(res.data['data'] as Map<String, dynamic>);
    }
    throw AuthApiException('响应格式错误');
  }

  Future<void> verifyCode(String email, String code) async {
    final res = await _post('verify-code', {'email': email, 'code': code});
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '验证码校验失败'));
    }
  }

  Future<AuthUser> register({
    required String email,
    required String password,
  }) async {
    final res = await _post('register', {
      'email': email,
      'password': password,
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '注册失败'));
    }
    if (res.data is Map && res.data['data'] is Map) {
      return AuthUser.fromJson(res.data['data'] as Map<String, dynamic>);
    }
    throw AuthApiException('响应格式错误');
  }
}

class _HttpResult {
  _HttpResult({required this.statusCode, required this.data});

  final int statusCode;
  final dynamic data;
}

class AuthApiException implements Exception {
  AuthApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

