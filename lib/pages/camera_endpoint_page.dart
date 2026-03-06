import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../db/database_helper.dart';
import '../models/detection_event.dart';

import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';
import '../utils/log_utils.dart';
import '../utils/navigation_service.dart';
import '../l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:wakelock_plus/wakelock_plus.dart';


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
  Interpreter? _personInterpreter;
  bool _personModelReady = false;
  bool _isDetecting = false;
  bool _isRecording = false;
  Timer? _detectTimer;
  MediaRecorder? _mediaRecorder;
  bool _isLoggingOut = false;

  // Banner ad (same style as camera list page)
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  
  // WebRTC signaling
  Signaling? _signaling;
  String? _selfId;
  List<dynamic> _peers = [];
  bool _isConnected = false;
  String? _currentUserEmail;
  bool _isFakeSleep = false;
  
  // Foreground service channel
  static const MethodChannel _serviceChannel = MethodChannel('camera_service');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBannerAd();
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
    await _checkAndRequestPermissions();
    _connectSignaling();
  }
  
  Future<void> _checkAndRequestPermissions() async {
    // 1. 请求相机和麦克风权限（两端通用）
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.cameraEndpointCameraMicPermissionRequired)),
        );
      }
      return;
    }

    // 2. Android：忽略电池优化 + 通知权限 + 前台服务，以便切到后台仍能持续视频
    //    iOS：无电池优化概念，无前台服务 API，不调用 MethodChannel
    if (Platform.isAndroid) {
      try {
        await _serviceChannel.invokeMethod('requestIgnoreBatteryOptimizations');
        final hasPermission = await _serviceChannel.invokeMethod<bool>('checkNotificationPermission') ?? false;

        if (!hasPermission) {
          await _serviceChannel.invokeMethod('requestNotificationPermission');
          await Future.delayed(const Duration(seconds: 1));
          final granted = await _serviceChannel.invokeMethod<bool>('checkNotificationPermission') ?? false;
          if (granted) {
            await _startForegroundService();
            if (mounted) _showAndroidServiceSnackBar();
          } else if (mounted) {
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.cameraEndpointNotificationPermissionRequired), duration: const Duration(seconds: 4)),
            );
          }
        } else {
          await _startForegroundService();
          if (mounted) _showAndroidServiceSnackBar();
        }
      } catch (e) {
        LogUtils.e('CameraEndpoint', 'Android permission/service error', e);
        if (mounted) await _startForegroundService();
      }
    }
  }

  /// iOS：通过 CallKit 上报/结束“正在通话”，使锁屏后仍能持续采集
  Future<void> _reportIosOngoingCall(bool start) async {
    if (!Platform.isIOS) return;
    try {
      if (start) {
        await _serviceChannel.invokeMethod('reportOngoingCall');
      } else {
        await _serviceChannel.invokeMethod('endOngoingCall');
      }
    } catch (e) {
      LogUtils.w('CameraEndpoint', 'reportOngoingCall/endOngoingCall failed: $e');
    }
  }

  Future<void> _showAndroidServiceSnackBar() async {
    bool isIgnoring = false;
    try {
      isIgnoring = await _serviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (_) {}
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${l.cameraEndpointServiceStarted}\n${isIgnoring ? l.cameraEndpointBatteryOptimizationsOff : l.cameraEndpointBatteryOptimizationsOn}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  Future<void> _startForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _serviceChannel.invokeMethod('startForegroundService');
      LogUtils.i('CameraEndpoint', 'Foreground service started');
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Failed to start foreground service', e);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.cameraEndpointServiceStartFailed}$e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _stopForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _serviceChannel.invokeMethod('stopForegroundService');
      LogUtils.i('CameraEndpoint', 'Foreground service stopped');
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Failed to stop foreground service', e);
    }
  }

  @override
  void dispose() {
    if (Platform.isIOS) WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _detectTimer?.cancel();
    _bannerAd?.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  Future<void> _releaseResources() async {
    if (Platform.isIOS) {
      WakelockPlus.disable();
      await _reportIosOngoingCall(false);
    }
    WidgetsBinding.instance.removeObserver(this);
    _stopDetectionTimer();
    await _signaling?.close();
    _stopVideo();
    await _stopForegroundService();
    await _localRenderer.dispose();
    _bannerAd?.dispose();
  }

  void _loadBannerAd() {
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/9214589741'
        : 'ca-app-pub-3940256099942544/2435281174';

    final ad = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isBannerAdReady = false;
          });
          LogUtils.w(
            'CameraEndpoint',
            'BannerAd failed to load: code=${error.code}, message=${error.message}, domain=${error.domain}',
          );
        },
      ),
    );

    ad.load();
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
          if (Platform.isIOS) _reportIosOngoingCall(true);
          break;
        case CallState.CallStateBye:
          LogUtils.i('CameraEndpoint', '监控端已断开');
          if (Platform.isIOS) _reportIosOngoingCall(false);
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
    _initPersonDetector();
    _startDetectionTimer();
  }

  Future<void> _initPersonDetector() async {
    if (_personInterpreter != null) return;
    try {
      // 需要你在 assets/ml/ 下放置 person_detection.tflite 模型
      _personInterpreter = await Interpreter.fromAsset('assets/ml/person_detection.tflite');
      _personModelReady = true;
      LogUtils.i('CameraEndpoint', 'TFLite person detector initialized');
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Failed to init TFLite person detector', e);
      _personModelReady = false;
    }
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
    if (_isRecording || _isDetecting) return;
    if (!_isVideoActive) return;

    _isDetecting = true;
    try {
      LogUtils.d('CameraEndpoint', 'Detection tick: start TFLite person detection');
      final bool isDetected = await _detectPersonWithTflite();
      if (isDetected) {
        LogUtils.i('CameraEndpoint', '检测到人物，准备录制');
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
      if (user.token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${user.token}');
      }
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      if (response.statusCode == 401) {
        NavigationService.handleUnauthorized();
      }
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

  Future<bool> _detectPersonWithTflite() async {
    try {
      if (!_personModelReady || _personInterpreter == null) {
        await _initPersonDetector();
        if (!_personModelReady || _personInterpreter == null) {
          LogUtils.w('CameraEndpoint', 'TFLite detector not ready, skip detection');
          return false;
        }
      }

      final videoTracks = _localRenderer.srcObject?.getVideoTracks();
      if (videoTracks == null || videoTracks.isEmpty) {
        LogUtils.w('CameraEndpoint', 'TFLite detection: no video tracks');
        return false;
      }

      final track = videoTracks.first;
      await (track as dynamic).captureFrame();

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/captureFrame.png');
      if (!await file.exists()) {
        LogUtils.w('CameraEndpoint', 'TFLite detection: captureFrame.png not found');
        return false;
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        LogUtils.w('CameraEndpoint', 'TFLite detection: decodeImage failed');
        return false;
      }

      final inputTensor = _personInterpreter!.getInputTensors().first;
      final shape = inputTensor.shape; // [1, height, width, 3]
      final height = shape[1];
      final width = shape[2];
      LogUtils.d('CameraEndpoint',
          'TFLite input tensor: type=${inputTensor.type}, shape=$shape, image=${image.width}x${image.height}');

      final resized = img.copyResize(image, width: width, height: height);

      // 根据模型输入类型决定是 uint8 还是 float32
      Object input;
      if (inputTensor.type == TensorType.uint8) {
        input = List.generate(
          1,
          (_) => List.generate(
            height,
            (y) => List.generate(
              width,
              (x) {
                final pixel = resized.getPixel(x, y);
                return [pixel.r, pixel.g, pixel.b];
              },
            ),
          ),
        );
      } else {
        // 默认按 float32 [0,1] 归一化
        input = List.generate(
          1,
          (_) => List.generate(
            height,
            (y) => List.generate(
              width,
              (x) {
                final pixel = resized.getPixel(x, y);
                final r = pixel.r / 255.0;
                final g = pixel.g / 255.0;
                final b = pixel.b / 255.0;
                return [r, g, b];
              },
            ),
          ),
        );
      }

      // 这里假设输出为典型的 SSD MobileNet 结构：
      // boxes: [1, numDetections, 4]
      // classes: [1, numDetections]
      // scores: [1, numDetections]
      // numDetections: [1]
      const int maxDetections = 10;
      final boxes = List.generate(
        1,
        (_) => List.generate(maxDetections, (_) => List.filled(4, 0.0)),
      );
      final classes = List.generate(
        1,
        (_) => List.filled(maxDetections, 0.0),
      );
      final scores = List.generate(
        1,
        (_) => List.filled(maxDetections, 0.0),
      );
      final numDetections = List.filled(1, 0.0);

      final outputs = <int, Object>{
        0: boxes,
        1: classes,
        2: scores,
        3: numDetections,
      };

      _personInterpreter!.runForMultipleInputs([input], outputs);

      final int count = numDetections[0].round().clamp(0, maxDetections);
      const double minScore = 0.6;
      // 对于官方 detect.tflite，标签文件通常是 0: person, 1: bicycle, ...
      const int personClassId = 0;

      LogUtils.d(
        'CameraEndpoint',
        'TFLite raw detections: count=$count, scores=${scores[0].take(count).toList()}, classes=${classes[0].take(count).toList()}',
      );

      for (int i = 0; i < count; i++) {
        final score = scores[0][i];
        final cls = classes[0][i].round();
        if (score >= minScore && cls == personClassId) {
          LogUtils.d(
            'CameraEndpoint',
            'TFLite detected person: idx=$i, score=$score, class=$cls',
          );
          return true;
        }
      }
      LogUtils.d(
        'CameraEndpoint',
        'TFLite: no person detected above threshold (minScore=$minScore, personClassId=$personClassId)',
      );
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'TFLite person detection error', e);
    }
    return false;
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
      child: Stack(
        children: [
          Scaffold(
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
                        final l = AppLocalizations.of(context);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l.switchToMonitorDialogTitle),
                            content: Text(l.switchToMonitorDialogContent),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(l.commonCancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l.commonConfirm),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await _releaseResources();
                          await SessionManager.clear();
                          if (!mounted) return;
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/auth',
                            (route) => false,
                          );
                        }
                      } else {
                        setState(() {
                          _role = 'camera';
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('camera_role', 'camera');
                      }
                    },
                  ),
                ),
              ),
              actions: [
                if (Platform.isIOS)
                  IconButton(
                    icon: const Icon(Icons.bedtime),
                    onPressed: () {
                      if (Platform.isIOS) WakelockPlus.enable();
                      setState(() {
                        _isFakeSleep = true;
                      });
                    },
                    tooltip:
                        AppLocalizations.of(context).cameraEndpointFakeSleepButton,
                  ),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: _isConnected ? Colors.green : Colors.red,
                  child: Builder(
                    builder: (context) {
                      final l = AppLocalizations.of(context);
                      final text = _isConnected
                          ? l.cameraEndpointConnectedWithId
                              .replaceFirst('{id}', _selfId ?? '')
                          : l.cameraEndpointConnecting;
                      return Text(
                        text,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: _isVideoActive
                      ? Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                color: Colors.black,
                                child: RepaintBoundary(
                                  key: _videoKey,
                                  child: RTCVideoView(
                                    _localRenderer,
                                    mirror: true,
                                    objectFit:
                                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 16,
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
                                      color: _isMicMuted
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  FloatingActionButton(
                                    heroTag: 'cam_btn',
                                    onPressed:
                                        _isSwitchingCamera ? null : _switchCamera,
                                    backgroundColor: Colors.white,
                                    child: _isSwitchingCamera
                                        ? const CircularProgressIndicator(
                                            strokeWidth: 2,
                                          )
                                        : const Icon(
                                            Icons.switch_camera,
                                            color: Colors.black,
                                          ),
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
                if (Platform.isIOS)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade100,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      AppLocalizations.of(context).cameraEndpointIosLockWarning,
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_isBannerAdReady && _bannerAd != null)
                  SafeArea(
                    top: false,
                    child: Container(
                      alignment: Alignment.center,
                      width: _bannerAd!.size.width.toDouble(),
                      height: _bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: _bannerAd!),
                    ),
                  ),
              ],
            ),
          ),
          if (Platform.isIOS && _isFakeSleep)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (Platform.isIOS) WakelockPlus.disable();
                  setState(() {
                    _isFakeSleep = false;
                  });
                },
                child: Container(color: Colors.black),
              ),
            ),
        ],
      ),
    );
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
