import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../models/detection_event.dart';

import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';
import '../utils/log_utils.dart';
import '../l10n/app_localizations.dart';
import 'package:image/image.dart' as img;


class CameraEndpointPage extends StatefulWidget {
  const CameraEndpointPage({super.key, required this.onSwitchToMonitor});

  final VoidCallback onSwitchToMonitor;

  @override
  State<CameraEndpointPage> createState() => _CameraEndpointPageState();
}

class _CameraEndpointPageState extends State<CameraEndpointPage> with WidgetsBindingObserver {
  String _role = 'camera';
  final _localRenderer = RTCVideoRenderer();
  bool _isVideoActive = false;
  bool _isMicMuted = true; // 默认关闭麦克风

  // Detection & Recording
  final GlobalKey _videoKey = GlobalKey();
  PoseDetector? _poseDetector;
  bool _isDetecting = false;
  bool _isRecording = false;
  Timer? _detectTimer;
  MediaRecorder? _mediaRecorder;
  bool _isLoggingOut = false;
  
  // WebRTC signaling
  Signaling? _signaling;
  String? _selfId;
  List<dynamic> _peers = [];
  bool _isConnected = false;
  String? _currentUserEmail;
  
  // Foreground service channel
  static const MethodChannel _serviceChannel = MethodChannel('camera_service');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRenderer();
    _initDetector();
    _loadUserInfo();
    _cleanupOldRecordings();
  }

  Future<void> _cleanupOldRecordings() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    final db = DatabaseHelper();
    final oldEvents = await db.getEventsBefore(cutoff);
    
    int deletedCount = 0;
    for (final event in oldEvents) {
      if (event.imagePath != null) {
        final f = File(event.imagePath!);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (e) {
            LogUtils.e('CameraEndpoint', 'Failed to delete old image: ${event.imagePath}', e);
          }
        }
      }
      if (event.videoPath != null) {
        final f = File(event.videoPath!);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (e) {
            LogUtils.e('CameraEndpoint', 'Failed to delete old video: ${event.videoPath}', e);
          }
        }
      }
      if (event.id != null) {
        await db.deleteEvent(event.id!);
        deletedCount++;
      }
    }
    
    if (deletedCount > 0) {
      LogUtils.i('CameraEndpoint', 'Cleaned up $deletedCount old recordings');
    }
  }


  void _loadUserInfo() async {
    final user = await SessionManager.getUser();
    _currentUserEmail = user?.email;
    await _checkAndRequestNotificationPermission();
    _connectSignaling();
  }
  
  Future<void> _checkAndRequestNotificationPermission() async {
    try {
      // 请求忽略电池优化（重要：保持网络连接）
      await _serviceChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      
      // 检查通知权限
      final hasPermission = await _serviceChannel.invokeMethod<bool>('checkNotificationPermission') ?? false;
      
      if (!hasPermission) {
        await _serviceChannel.invokeMethod('requestNotificationPermission');
        await Future.delayed(const Duration(seconds: 1));
        final granted = await _serviceChannel.invokeMethod<bool>('checkNotificationPermission') ?? false;

        if (granted) {
          await _startForegroundService();
          if (mounted) {
            final isIgnoringBatteryOptimizations =
                await _serviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${l.cameraEndpointServiceStarted}\n${isIgnoringBatteryOptimizations ? l.cameraEndpointBatteryOptimizationsOff : l.cameraEndpointBatteryOptimizationsOn}',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else {
          if (mounted) {
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.cameraEndpointNotificationPermissionRequired),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        // 已有权限，直接启动服务
        await _startForegroundService();
        if (mounted) {
          final isIgnoringBatteryOptimizations = await _serviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${l.cameraEndpointServiceStarted}\n${isIgnoringBatteryOptimizations ? l.cameraEndpointBatteryOptimizationsOff : l.cameraEndpointBatteryOptimizationsOn}',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Permission check error', e);
      // Android 12以下不需要运行时权限，直接启动服务
      if (mounted) {
        await _startForegroundService();
      }
    }
  }
  
  Future<void> _startForegroundService() async {
    try {
      await _serviceChannel.invokeMethod('startForegroundService');
      LogUtils.i('CameraEndpoint', 'Foreground service started');
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Failed to start foreground service', e);
      if (mounted) {
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l.cameraEndpointServiceStartFailed}$e'),
              duration: const Duration(seconds: 3),
            ),
          );
      }
    }
  }
  
  Future<void> _stopForegroundService() async {
    try {
      await _serviceChannel.invokeMethod('stopForegroundService');
      LogUtils.i('CameraEndpoint', 'Foreground service stopped');
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Failed to stop foreground service', e);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectTimer?.cancel();
    _poseDetector?.close();
   _localRenderer.dispose();
    super.dispose();
  }

  Future<void> _releaseResources() async {
    WidgetsBinding.instance.removeObserver(this);
    _stopDetectionTimer();
    _poseDetector?.close();
    await _signaling?.close();
    _stopVideo();
    await _stopForegroundService();
    await _localRenderer.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LogUtils.i('CameraEndpoint', 'AppLifecycleState changed to $state');
    if (state == AppLifecycleState.resumed) {
      // 当应用回到前台时，强制重启视频流以解决编码器卡死问题
      _signaling?.restartVideo();
      
      // 检查连接状态，如果未连接则尝试重连
      if (!_isConnected) {
        LogUtils.w('CameraEndpoint', 'Resumed but disconnected, forcing reconnect...');
        _signaling?.connect();
      }
    }
  }

  void _initRenderer() async {
    await _localRenderer.initialize();
  }

  void _connectSignaling() async {
    _signaling = Signaling(defaultAuthHost, context, 
        userEmail: _currentUserEmail, 
        deviceType: 'camera');
    
    // 设置回调函数在连接之前
    _signaling!.onSignalingStateChange = (SignalingState state) {
      LogUtils.i('CameraEndpoint', 'Signaling state changed: $state');
      setState(() {
        _isConnected = state == SignalingState.ConnectionOpen;
      });
      
      // 处理连接关闭状态，确保重连时 UI 正确反馈
      if (state == SignalingState.ConnectionClosed || state == SignalingState.ConnectionError) {
        if (mounted) {
          LogUtils.w('CameraEndpoint', '与服务器连接断开，正在尝试重连...');
        }
      }

      if (state == SignalingState.ConnectionOpen) {
        _startVideo();
         if (mounted) {
           LogUtils.i('CameraEndpoint', '已连接到服务器');
        }
      }
    };

    _signaling!.onPeersUpdate = (event) {
      LogUtils.d('CameraEndpoint', 'Peers updated: $event');
      setState(() {
        _selfId = event['self'];
        _peers = event['peers'];
        // 如果收到peers更新，说明已经连接成功
        if (!_isConnected) {
          _isConnected = true;
        }
      });
    };

    _signaling!.onLocalStream = (stream) {
      LogUtils.i('CameraEndpoint', 'Local stream received');
      _localRenderer.srcObject = stream;
      setState(() {
        _isVideoActive = true;
      });

      // 默认静音
      if (_isMicMuted) {
        final audioTracks = stream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          audioTracks[0].enabled = false;
        }
      }
    };

    _signaling!.onCallStateChange = (Session session, CallState state) {
      LogUtils.i('CameraEndpoint', 'Call state changed: $state');
      switch (state) {
        case CallState.CallStateRinging:
          // 验证邮箱权限后自动接受来电
          if (_validateEmailPermission(session)) {
            _signaling?.accept(session.sid, 'video');
            LogUtils.i('CameraEndpoint', '监控端已连接');
          } else {
            _signaling?.reject(session.sid);
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.cameraEndpointEmailVerifyFailed),
                backgroundColor: Colors.red,
              ),
            );
          }
          break;
        case CallState.CallStateConnected:
          LogUtils.i('CameraEndpoint', '视频通话已连接');
          break;
        case CallState.CallStateBye:
          LogUtils.i('CameraEndpoint', '监控端已断开');
          break;
        default:
          break;
      }
    };

    // DataChannel: receive messages from monitor while video is live.
    _signaling!.onDataChannel = (session, dc) {
      LogUtils.i('CameraEndpoint', 'DataChannel opened: ${dc.label}');
    };
    _signaling!.onDataChannelMessage = (session, dc, data) async {
      final msg = data.isBinary ? '[binary ${data.binary.length} bytes]' : data.text;
      LogUtils.d('CameraEndpoint', 'DataChannel message: $msg');
      if (!data.isBinary) {
        try {
          final decoded = jsonDecode(data.text);
          
          if (decoded is Map && decoded['type'] == 'get_events') {
            LogUtils.i('CameraEndpoint', 'Received get_events request');
            final int limit = decoded['limit'] ?? 15;
            final int offset = decoded['offset'] ?? 0;
            
            try {
              final events = await DatabaseHelper().getEvents(limit: limit, offset: offset);
              // Convert events to List<Map>
              final eventsList = events.map((e) => e.toMap()).toList();
              
              final response = {
                'type': 'events_list',
                'data': eventsList,
                'offset': offset,
              };
              
              final jsonResponse = jsonEncode(response);
              LogUtils.i('CameraEndpoint', 'Sending events_list response, length: ${jsonResponse.length} bytes');
              _signaling?.sendData(session.sid, jsonResponse);
              LogUtils.i('CameraEndpoint', 'Sent ${events.length} events (offset: $offset, limit: $limit)');
            } catch (e) {
              LogUtils.e('CameraEndpoint', 'Error getting events', e);
            }
            return;
          }

          if (decoded is Map && decoded['type'] == 'get_thumbnail') {
             final int eventId = decoded['id'];
             LogUtils.i('CameraEndpoint', 'Received get_thumbnail request for event $eventId');
             
             try {
               final event = await DatabaseHelper().getEventById(eventId);
               if (event != null && event.imagePath != null) {
                  final file = File(event.imagePath!);
                  if (await file.exists()) {
                    final bytes = await file.readAsBytes();
                    final image = img.decodeImage(bytes);
                    if (image != null) {
                       final thumbnail = img.copyResize(image, width: 200);
                       final thumbnailBytes = img.encodeJpg(thumbnail, quality: 70);
                       final base64Thumb = base64Encode(thumbnailBytes);
                       
                       _signaling?.sendData(session.sid, jsonEncode({
                         'type': 'thumbnail',
                         'id': eventId,
                         'data': base64Thumb
                       }));
                       LogUtils.d('CameraEndpoint', 'Sent thumbnail for event $eventId, size: ${base64Thumb.length}');
                    }
                  }
               }
             } catch (e) {
               LogUtils.e('CameraEndpoint', 'Error sending thumbnail for $eventId', e);
             }
             return;
          }

          if (decoded is Map && decoded['type'] == 'delete_event') {
             final int eventId = decoded['id'];
             LogUtils.i('CameraEndpoint', 'Received delete_event request for event $eventId');
             
             try {
               final event = await DatabaseHelper().getEventById(eventId);
               if (event != null) {
                  await DatabaseHelper().deleteEvent(eventId);
                  
                  if (event.videoPath != null) {
                    final f = File(event.videoPath!);
                    if (await f.exists()) await f.delete();
                  }
                  if (event.imagePath != null) {
                    final f = File(event.imagePath!);
                    if (await f.exists()) await f.delete();
                  }
                  
                  _signaling?.sendData(session.sid, jsonEncode({
                    'type': 'delete_event_success',
                    'id': eventId
                  }));
                  LogUtils.i('CameraEndpoint', 'Event $eventId deleted successfully');
               } else {
                 _signaling?.sendData(session.sid, jsonEncode({
                    'type': 'delete_event_error',
                    'id': eventId,
                    'message': 'Event not found'
                  }));
               }
             } catch (e) {
               LogUtils.e('CameraEndpoint', 'Error deleting event $eventId', e);
               _signaling?.sendData(session.sid, jsonEncode({
                  'type': 'delete_event_error',
                  'id': eventId,
                  'message': e.toString()
                }));
             }
             return;
          }

          if (decoded is Map && decoded['type'] == 'camera_mic') {
            final enabled = decoded['enabled'] == true;
            _signaling?.setMicEnabled(enabled);
            setState(() {
              _isMicMuted = !enabled;
            });
            if (mounted) {
              final l = AppLocalizations.of(context);
              LogUtils.i(
                'CameraEndpoint',
                enabled ? l.cameraEndpointLogMicOn : l.cameraEndpointLogMicOff,
              );
            }
            return;
          }

          if (decoded is Map && decoded['type'] == 'get_video') {
            final int eventId = decoded['id'];
            LogUtils.i('CameraEndpoint', 'Received get_video request for event $eventId');
            
            try {
              final event = await DatabaseHelper().getEventById(eventId);
              if (event == null || event.videoPath == null) {
                LogUtils.w('CameraEndpoint', 'Video not found for event $eventId');
                _signaling?.sendData(session.sid, jsonEncode({
                  'type': 'video_error',
                  'message': 'Video not found',
                  'id': eventId
                }));
                return;
              }
              
              final file = File(event.videoPath!);
              if (!await file.exists()) {
                 LogUtils.w('CameraEndpoint', 'Video file missing: ${event.videoPath}');
                  _signaling?.sendData(session.sid, jsonEncode({
                  'type': 'video_error',
                  'message': 'Video file missing',
                  'id': eventId
                }));
                return;
              }
              
              final fileSize = await file.length();
              LogUtils.i('CameraEndpoint', 'Sending video: ${event.videoPath} ($fileSize bytes)');
              
              _signaling?.sendData(session.sid, jsonEncode({
                'type': 'video_start',
                'id': eventId,
                'size': fileSize
              }));
              
              // Chunk size 16KB to be safe with WebRTC DataChannel
              const int chunkSize = 16 * 1024;
              final raf = await file.open(mode: FileMode.read);
              int bytesSent = 0;
              
              while (bytesSent < fileSize) {
                // If channel closes or session ends, we should probably stop?
                // But catching exception on send might be enough.
                final chunk = await raf.read(chunkSize);
                if (chunk.isEmpty) break;
                
                _signaling?.sendBinaryData(session.sid, chunk);
                bytesSent += chunk.length;
                
                // Small delay to prevent flooding
                await Future.delayed(const Duration(milliseconds: 5));
              }
              
              await raf.close();
              
              _signaling?.sendData(session.sid, jsonEncode({
                'type': 'video_end',
                'id': eventId
              }));
              LogUtils.i('CameraEndpoint', 'Video sent successfully');
              
            } catch (e) {
               LogUtils.e('CameraEndpoint', 'Error sending video', e);
               _signaling?.sendData(session.sid, jsonEncode({
                  'type': 'video_error',
                  'message': 'Internal error: $e',
                  'id': eventId
                }));
            }
            return;
          }
        } catch (_) {
          // fallthrough: treat as plain text
        }
      }
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      LogUtils.i('CameraEndpoint', '${l.cameraEndpointLogMonitorMessage}$msg');
    };

    // 连接到服务器
    await _signaling!.connect();
  }

  bool _validateEmailPermission(Session session) {
    // 检查当前用户邮箱
    if (_currentUserEmail == null) {
      LogUtils.w('CameraEndpoint', 'No logged in user');
      return false;
    }

    // 从peers列表中找到对应的peer信息
    final callerPeer = _peers.firstWhere(
      (peer) => peer['id'] == session.pid,
      orElse: () => null,
    );

    if (callerPeer == null) {
      LogUtils.w('CameraEndpoint', 'Caller peer not found');
      return false;
    }

    // 从user_agent中提取邮箱信息
    final userAgent = callerPeer['user_agent'] as String? ?? '';
    final emailMatch = RegExp(r'email:([^|]+)').firstMatch(userAgent);
    final callerEmail = emailMatch?.group(1);

    LogUtils.d('CameraEndpoint', 'Current user email: $_currentUserEmail');
    LogUtils.d('CameraEndpoint', 'Caller email: $callerEmail');
    LogUtils.d('CameraEndpoint', 'Caller user_agent: $userAgent');

    // 验证邮箱是否匹配
    return callerEmail == _currentUserEmail;
  }

  void _startVideo() async {
    if (_signaling != null) {
      // 增加延迟，确保冷启动时相机硬件准备就绪（模拟 restartVideo 在后台切前台时的行为）
      await Future.delayed(const Duration(milliseconds: 500));
      await _signaling!.restartVideo();
    }
  }

  void _stopVideo() async {
    try {
      _localRenderer.srcObject = null;
      setState(() {
        _isVideoActive = false;
      });
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Error stopping video', e);
    }
  }

  void _toggleMic() {
    _signaling?.muteMic();
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
  }

  bool _isSwitchingCamera = false;

  void _switchCamera() async {
    if (_isSwitchingCamera) return;
    
    setState(() {
      _isSwitchingCamera = true;
    });
    
    try {
      await _signaling?.switchCamera();
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() {
      _isLoggingOut = true;
    });
    try {
      // 必须先释放资源（包括前台服务和WebRTC连接），否则会有资源泄漏风险
      await _releaseResources();
      
      await SessionManager.clear();
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsLogoutSuccess)),
      );
      // Go to login page and clear navigation stack.
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  void _showLogoutDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.settingsLogoutDialogTitle),
        content: Text(l.settingsLogoutDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.settingsLogoutDialogCancel),
          ),
          ElevatedButton(
            onPressed: _isLoggingOut
                ? null
                : () async {
                    // Close the dialog first.
                    Navigator.pop(context);
                    await _logout();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l.settingsLogoutDialogConfirm),
          ),
        ],
      ),
    );
  }

  void _initDetector() {
    // 使用单张图片模式和精确模型以提高检测准确率
    final options = PoseDetectorOptions(
      mode: PoseDetectionMode.single,
      model: PoseDetectionModel.accurate,
    );
    _poseDetector = PoseDetector(options: options);
    
    _startDetectionTimer();
  }

  void _startDetectionTimer() {
    _detectTimer?.cancel();
    // 每10秒检测一次
    _detectTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _performDetection();
    });
  }

  void _stopDetectionTimer() {
    _detectTimer?.cancel();
    _detectTimer = null;
  }

  Future<void> _performDetection() async {
    if (_isRecording || _isDetecting || _poseDetector == null) return;
    if (!_isVideoActive) return;

    _isDetecting = true;
    try {
      // 1. 单次检测 (内部已包含严格的拓扑校验和关键点数量要求)
      bool isDetected = await _detectPersonInCurrentFrame();
      
      if (isDetected) {
        LogUtils.i('CameraEndpoint', '检测到人物 (严格模式)，准备录制');
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/captureFrame.png');
        if (await file.exists()) {
          final appDir = await getApplicationDocumentsDirectory();
          final snapshotDir = Directory('${appDir.path}/snapshots');
          if (!await snapshotDir.exists()) {
            await snapshotDir.create(recursive: true);
          }
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final imagePath = '${snapshotDir.path}/snapshot_$timestamp.png';
          
          await file.copy(imagePath);
          _startTenSecondsRecording(imagePath);
          await _sendAlertWithSnapshot(imagePath);
        }
      }
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Error in detection loop', e);
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> _sendAlertWithSnapshot(String imagePath) async {
    try {
      final user = await SessionManager.getUser();
      if (user == null) {
        LogUtils.w('CameraEndpoint', 'No logged in user, skip alert upload');
        return;
      }

      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : Platform.operatingSystem;

      final body = <String, dynamic>{
        'email': user.email,
        'platform': platform,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'camera_id': _selfId,
      };

      final uri = Uri.parse('https://rephone.top/api/push/alert');
      final client = HttpClient();

      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      LogUtils.i(
        'CameraEndpoint',
        'Alert push response [${response.statusCode}]: $respBody',
      );

      client.close(force: true);
    } catch (e, st) {
      LogUtils.e('CameraEndpoint', 'Failed to send alert snapshot', e, st);
    }
  }

  Future<bool> _detectPersonInCurrentFrame() async {
    try {
      final videoTracks = _localRenderer.srcObject?.getVideoTracks();
      if (videoTracks == null || videoTracks.isEmpty) return false;

      final track = videoTracks.first;
      await (track as dynamic).captureFrame();
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/captureFrame.png');
      if (!await file.exists()) return false;

      final inputImage = InputImage.fromFilePath(file.path);
      final poses = await _poseDetector!.processImage(inputImage);
      
      for (final pose in poses) {
        // 1. 提高基础置信度阈值 (0.60 -> 0.75) 以减少误报
        const double minConfidence = 0.75;
        
        // 2. 核心关键点定义 (面部 + 躯干)
        final coreLandmarks = [
          pose.landmarks[PoseLandmarkType.nose],
          pose.landmarks[PoseLandmarkType.leftShoulder],
          pose.landmarks[PoseLandmarkType.rightShoulder],
          pose.landmarks[PoseLandmarkType.leftHip],
          pose.landmarks[PoseLandmarkType.rightHip],
        ];

        // 3. 统计核心部位命中数
        int validCoreCount = 0;
        for (final landmark in coreLandmarks) {
          if ((landmark?.likelihood ?? 0) > minConfidence) {
            validCoreCount++;
          }
        }

        // 4. 统计全身高置信度关键点总数
        int totalConfidentLandmarks = 0;
        pose.landmarks.forEach((_, landmark) {
          if (landmark.likelihood > minConfidence) {
            totalConfidentLandmarks++;
          }
        });

        // 5. 综合判定策略 (更严格):
        // 策略A: 至少检测到3个核心部位 (如头+肩+肩，肩+肩+腰) 且 通过拓扑检查
        // 策略B: 只有全身点数特别多 (>=5) 且 通过拓扑检查
        // 之前的 >=2 太容易被椅子靠背等物体误报 (只识别出双肩)
        bool topologyPass = _checkBodyTopology(pose);
        
        if (topologyPass) {
          if ((validCoreCount >= 3 && totalConfidentLandmarks >= 3) || totalConfidentLandmarks >= 5) {
            LogUtils.d('CameraEndpoint', 'Frame detected person: Core=$validCoreCount, Total=$totalConfidentLandmarks');
            return true;
          }
        }
      }
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Single frame detection error', e);
    }
    return false;
  }

  bool _checkBodyTopology(Pose pose) {
    final landmarks = pose.landmarks;
    final nose = landmarks[PoseLandmarkType.nose];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    
    // 稍微降低校验阈值，避免过度过滤
    const double minConf = 0.60; 
    
    // 1. 检查躯干直立性 (肩膀在臀部上方)
    // 图像坐标系Y向下增加，所以头部Y < 脚部Y
    if (leftShoulder != null && leftHip != null && 
        leftShoulder.likelihood > minConf && leftHip.likelihood > minConf) {
      if (leftShoulder.y > leftHip.y) {
         // LogUtils.d('CameraEndpoint', 'Topology reject: L-Shoulder below L-Hip');
         return false; 
      }
    }
    if (rightShoulder != null && rightHip != null && 
        rightShoulder.likelihood > minConf && rightHip.likelihood > minConf) {
      if (rightShoulder.y > rightHip.y) {
         // LogUtils.d('CameraEndpoint', 'Topology reject: R-Shoulder below R-Hip');
         return false;
      }
    }

    // 2. 检查头部位置 (鼻子在肩膀上方)
    if (nose != null && nose.likelihood > minConf) {
      if (leftShoulder != null && leftShoulder.likelihood > minConf) {
        if (nose.y > leftShoulder.y) {
           // LogUtils.d('CameraEndpoint', 'Topology reject: Nose below L-Shoulder');
           return false;
        }
      }
      if (rightShoulder != null && rightShoulder.likelihood > minConf) {
        if (nose.y > rightShoulder.y) {
           // LogUtils.d('CameraEndpoint', 'Topology reject: Nose below R-Shoulder');
           return false;
        }
      }
    }
    
    return true;
  }

  Future<void> _startTenSecondsRecording(String imagePath) async {
    if (_isRecording) return;
    _isRecording = true;
    _stopDetectionTimer(); // Stop detection timer during recording

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/recordings');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${saveDir.path}/event_$timestamp.mp4';

      _mediaRecorder = MediaRecorder();
      // Use the first video track from the local stream
      final tracks = _localRenderer.srcObject?.getVideoTracks();
      if (tracks == null || tracks.isEmpty) {
         LogUtils.w('CameraEndpoint', 'No video tracks available for recording');
         _isRecording = false;
         _startDetectionTimer(); // Resume detection on error
         return;
      }
      await _mediaRecorder!.start(
        filePath, 
        videoTrack: tracks.first
      );
      
      LogUtils.i('CameraEndpoint', 'Start recording: $filePath');

      // 为避免编码器冷启动造成的时长偏差，增加轻微补偿（约500ms）
      Future.delayed(const Duration(milliseconds: 10500), () async {
        try {
          await _mediaRecorder?.stop();
        } catch (e) {
          LogUtils.e('CameraEndpoint', 'Recording stop error', e);
        }
        _isRecording = false;
        
        await DatabaseHelper().insertEvent(DetectionEvent(
          timestamp: timestamp,
          imagePath: imagePath,
          videoPath: filePath,
        ));
        LogUtils.i('CameraEndpoint', 'Event saved to database');

        LogUtils.i('CameraEndpoint', 'Recording finished. Cooldown for 10 seconds.');
        _mediaRecorder = null;
        
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) {
             _startDetectionTimer();
             LogUtils.i('CameraEndpoint', 'Cooldown finished, detection resumed.');
          }
        });
      });
      
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Recording error', e);
      _isRecording = false;
      _startDetectionTimer(); // Resume detection on error
      _mediaRecorder = null;
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) {
            final l = AppLocalizations.of(context);
            return AlertDialog(
              title: Text(l.cameraEndpointExitDialogTitle),
              content: Text(l.cameraEndpointExitDialogContent),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l.commonCancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l.commonConfirm),
                ),
              ],
            );
          },
        );

        if (shouldExit == true) {
          await _releaseResources();
          if (mounted) {
             SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.inversePrimary,
        centerTitle: true,
        title: Text(AppLocalizations.of(context).cameraEndpointTitle),
        leadingWidth: 140,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CameraRoleMenu(
              value: _role,
              onSelected: (role) async {
                if (role == 'monitor') {
                  widget.onSwitchToMonitor();
                  return;
                }
                setState(() {
                  _role = 'camera';
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('camera_role', 'camera');
              },
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _showLogoutDialog,
            tooltip: AppLocalizations.of(context).settingsLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 连接状态指示器
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: _isConnected ? Colors.green : Colors.red,
            child: Builder(
              builder: (context) {
                final l = AppLocalizations.of(context);
                final text = _isConnected
                    ? l.cameraEndpointConnectedWithId.replaceFirst('{id}', _selfId ?? '')
                    : l.cameraEndpointConnecting;
                return Text(
                  text,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                );
              },
            ),
          ),
          // 视频预览
          Expanded(
            child: _isVideoActive
                ? Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: const BoxDecoration(color: Colors.black),
                        child: RepaintBoundary(
                          key: _videoKey,
                          child: RTCVideoView(_localRenderer, mirror: true),
                        ),
                      ),
                      Positioned(
                        bottom: 30,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [

                            FloatingActionButton(
                              heroTag: 'mic_btn',
                              onPressed: _toggleMic,
                              backgroundColor:
                                  _isMicMuted ? Colors.red : Colors.white,
                              child: Icon(
                                _isMicMuted ? Icons.mic_off : Icons.mic,
                                color:
                                    _isMicMuted ? Colors.white : Colors.black,
                              ),
                            ),
                            FloatingActionButton(
                              heroTag: 'cam_btn',
                              onPressed: _isSwitchingCamera ? null : _switchCamera,
                              backgroundColor: Colors.white,
                              child: _isSwitchingCamera
                                  ? const CircularProgressIndicator(strokeWidth: 2)
                                  : const Icon(Icons.switch_camera, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),
        ],
      ),
    ));
  }
}



class _CameraRoleMenu extends StatelessWidget {
  const _CameraRoleMenu({
    required this.value,
    required this.onSelected,
  });

  final String value;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isMonitor = value == 'monitor';
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'monitor',
          child: Text(l.cameraRoleMonitor),
        ),
        PopupMenuItem(
          value: 'camera',
          child: Text(l.cameraRoleCamera),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMonitor ? l.cameraRoleMonitor : l.cameraRoleCamera,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}
