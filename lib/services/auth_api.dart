import 'dart:convert';
import 'dart:io';

import '../config/server_config.dart';
import '../models/auth_user.dart';
import '../l10n/app_localizations.dart';
import 'session_manager.dart';

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

  Uri _buildUserUri(String path) => Uri(
        scheme: useHttps ? 'https' : 'http',
        host: host,
        port: port,
        path: '/api/user/$path',
      );

  Future<_HttpResult> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUri(path));
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

  Future<_HttpResult> _postUser(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final req = await client.postUrl(_buildUserUri(path));
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

  String _resolveLanguageTag() {
    final locale = LocaleManager.localeNotifier.value;
    if (locale == null) {
      return 'en-US';
    }
    if (locale.languageCode == 'zh') {
      return 'zh-CN';
    }
    return 'en-US';
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
    final res = await _post('login', {
      'email': email,
      'password': password,
      'language': _resolveLanguageTag(),
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '登录失败'));
    }
    if (res.data is Map && res.data['data'] is Map) {
      return AuthUser.fromJson(res.data['data'] as Map<String, dynamic>);
    }
    throw AuthApiException('响应格式错误');
  }

  Future<void> deleteAccount(String email, String password) async {
    final res = await _post('delete-account', {
      'email': email,
      'password': password,
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '注销账号失败'));
    }
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
      'language': _resolveLanguageTag(),
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '注册失败'));
    }
    if (res.data is Map && res.data['data'] is Map) {
      return AuthUser.fromJson(res.data['data'] as Map<String, dynamic>);
    }
    throw AuthApiException('响应格式错误');
  }

  Future<void> resetPassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final res = await _post('change-password', {
      'email': email,
      'old_password': oldPassword,
      'new_password': newPassword,
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '重置密码失败'));
    }
    // Check if success is true in response body, though status code usually handles errors
    if (res.data is Map && res.data['success'] == false) {
      throw AuthApiException(_extractMessage(res.data, '重置密码失败'));
    }
  }

  Future<void> sendPasswordResetCode(String email) async {
    final res = await _post('send-reset-code', {'email': email});
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '发送验证码失败'));
    }
  }

  Future<void> confirmResetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final res = await _post('reset-password', {
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '重置密码失败'));
    }
  }

  Future<void> updateLanguage({
    required String email,
    required String language,
  }) async {
    final res = await _postUser('update-language', {
      'email': email,
      'language': language,
    });
    if (res.statusCode >= 400) {
      throw AuthApiException(_extractMessage(res.data, '更新语言失败'));
    }
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
