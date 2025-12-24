import 'dart:convert';
import 'dart:io';

import '../config/server_config.dart';

/// 设备绑定信息模型
class DeviceBinding {
  DeviceBinding({
    required this.id,
    required this.monitorEmail,
    required this.cameraEmail,
    required this.cameraDeviceId,
    this.cameraName,
    this.cameraLocation,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String monitorEmail;
  final String cameraEmail;
  final String cameraDeviceId;
  final String? cameraName;
  final String? cameraLocation;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DeviceBinding.fromJson(Map<String, dynamic> json) {
    try {
      // 处理 id（可能是 int 或 int64）
      int id;
      if (json['id'] is int) {
        id = json['id'] as int;
      } else if (json['id'] is num) {
        id = (json['id'] as num).toInt();
      } else {
        throw FormatException('Invalid id type: ${json['id']?.runtimeType ?? 'null'}');
      }

      // 处理时间字段
      DateTime parseDateTime(dynamic value) {
        if (value == null) {
          throw FormatException('DateTime value is null');
        }
        if (value is String) {
          if (value.isEmpty) {
            throw FormatException('DateTime string is empty');
          }
          try {
            return DateTime.parse(value);
          } catch (e) {
            throw FormatException('Failed to parse DateTime string "$value": $e');
          }
        } else if (value is int) {
          // 如果是时间戳（秒）
          return DateTime.fromMillisecondsSinceEpoch(value * 1000);
        } else if (value is num) {
          // 如果是数字时间戳
          return DateTime.fromMillisecondsSinceEpoch((value.toInt()) * 1000);
        }
        throw FormatException('Invalid datetime format: $value (type: ${value.runtimeType})');
      }

      // 处理字符串字段（空字符串转为 null）
      String? parseOptionalString(dynamic value) {
        if (value == null) return null;
        if (value is String) {
          return value.isEmpty ? null : value;
        }
        return value.toString();
      }

      return DeviceBinding(
        id: id,
        monitorEmail: json['monitor_email'] as String? ?? '',
        cameraEmail: json['camera_email'] as String? ?? '',
        cameraDeviceId: json['camera_device_id'] as String? ?? '',
        cameraName: parseOptionalString(json['camera_name']),
        cameraLocation: parseOptionalString(json['camera_location']),
        status: json['status'] as String? ?? 'active',
        createdAt: parseDateTime(json['created_at']),
        updatedAt: parseDateTime(json['updated_at']),
      );
    } catch (e, stackTrace) {
      print('DeviceBinding.fromJson error: $e');
      print('DeviceBinding.fromJson stack trace: $stackTrace');
      print('DeviceBinding.fromJson JSON data: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'monitor_email': monitorEmail,
      'camera_email': cameraEmail,
      'camera_device_id': cameraDeviceId,
      'camera_name': cameraName,
      'camera_location': cameraLocation,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// 添加绑定请求参数
class AddBindingRequest {
  AddBindingRequest({
    required this.monitorEmail,
    required this.cameraEmail,
    required this.cameraDeviceId,
    this.cameraName,
    this.cameraLocation,
  });

  final String monitorEmail;
  final String cameraEmail;
  final String cameraDeviceId;
  final String? cameraName;
  final String? cameraLocation;

  Map<String, dynamic> toJson() {
    return {
      'monitor_email': monitorEmail,
      'camera_email': cameraEmail,
      'camera_device_id': cameraDeviceId,
      if (cameraName != null) 'camera_name': cameraName,
      if (cameraLocation != null) 'camera_location': cameraLocation,
    };
  }
}

/// 设备绑定 API 客户端
/// 参考 auth_api.dart 的实现风格
class BindApi {
  BindApi({
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
        path: '/api/device/$path',
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

  Future<_HttpResult> _get(String path, Map<String, String>? queryParameters) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final uri = _buildUri(path);
      final uriWithQuery = queryParameters != null && queryParameters.isNotEmpty
          ? uri.replace(queryParameters: queryParameters)
          : uri;
      final req = await client.getUrl(uriWithQuery);
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

  /// 添加设备绑定关系
  /// [request] 绑定请求参数
  /// 返回绑定ID
  Future<int> addBinding(AddBindingRequest request) async {
    final res = await _post('add-binding', request.toJson());
    if (res.statusCode >= 400) {
      throw BindApiException(_extractMessage(res.data, '添加绑定失败'));
    }
    if (res.data is Map && res.data['data'] is Map) {
      final data = res.data['data'] as Map<String, dynamic>;
      if (data['id'] != null) {
        return data['id'] as int;
      }
    }
    throw BindApiException('响应格式错误：缺少绑定ID');
  }

  /// 获取监控端已绑定的相机端列表
  /// [monitorEmail] 监控端邮箱
  /// 返回绑定列表
  Future<List<DeviceBinding>> getBindings(String monitorEmail) async {
    final res = await _get('get-bindings', {'monitor_email': monitorEmail});
    if (res.statusCode >= 400) {
      throw BindApiException(_extractMessage(res.data, '获取绑定列表失败'));
    }
    
    // 打印响应以便调试
    print('BindApi.getBindings response: ${res.data}');
    print('BindApi.getBindings response type: ${res.data.runtimeType}');
    
    // 尝试解析响应
    if (res.data is Map) {
      final responseMap = res.data as Map<String, dynamic>;
      
      // 打印 Map 的所有键
      print('BindApi.getBindings response keys: ${responseMap.keys.toList()}');
      
      // 检查是否有 data 字段
      if (responseMap.containsKey('data')) {
        final data = responseMap['data'];
        print('BindApi.getBindings data field exists, type: ${data.runtimeType}');
        print('BindApi.getBindings data value: $data');
        
        // data 可能是 null（空结果）或数组
        if (data == null) {
          // 服务端返回 null 表示没有绑定关系，返回空列表
          print('BindApi.getBindings data is null, returning empty list');
          return <DeviceBinding>[];
        } else if (data is List) {
          print('BindApi.getBindings data is List, length: ${data.length}');
          try {
            final result = data
                .map((item) {
                  print('BindApi.getBindings processing item: $item (type: ${item.runtimeType})');
                  if (item is Map<String, dynamic>) {
                    return DeviceBinding.fromJson(item);
                  } else {
                    print('BindApi: Invalid item type in data list: ${item.runtimeType}');
                    return null;
                  }
                })
                .whereType<DeviceBinding>()
                .toList();
            print('BindApi.getBindings parsed ${result.length} bindings successfully');
            return result;
          } catch (e, stackTrace) {
            print('BindApi: Error parsing bindings list: $e');
            print('BindApi: Stack trace: $stackTrace');
            throw BindApiException('解析绑定列表失败: $e');
          }
        } else {
          print('BindApi: data field is not a List or null, type: ${data.runtimeType}, value: $data');
          throw BindApiException('响应格式错误: data 字段不是数组或 null 类型，实际类型: ${data.runtimeType}');
        }
      } else {
        // 打印所有键以便调试
        print('BindApi: data field not found in response. Available keys: ${responseMap.keys.toList()}');
        print('BindApi: Full response map: $responseMap');
        
        // 检查是否有 success 字段
        if (responseMap.containsKey('success')) {
          print('BindApi: success field value: ${responseMap['success']}');
        }
        
        throw BindApiException('响应格式错误: 缺少 data 字段');
      }
    } else if (res.data is List) {
      // 如果响应直接是数组
      print('BindApi.getBindings response is direct List');
      try {
        final dataList = res.data as List;
        return dataList
            .map((item) {
              if (item is Map<String, dynamic>) {
                return DeviceBinding.fromJson(item);
              }
              return null;
            })
            .whereType<DeviceBinding>()
            .toList();
      } catch (e) {
        print('BindApi: Error parsing direct list response: $e');
        throw BindApiException('解析绑定列表失败: $e');
      }
    }
    
    throw BindApiException('响应格式错误: 期望 Map 或 List，实际类型 ${res.data.runtimeType}');
  }
}

class _HttpResult {
  _HttpResult({required this.statusCode, required this.data});

  final int statusCode;
  final dynamic data;
}

class BindApiException implements Exception {
  BindApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

