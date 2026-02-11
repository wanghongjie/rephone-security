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
        // 请求通知权限
        await _serviceChannel.invokeMethod('requestNotificationPermission');
        
        // 等待用户响应（权限对话框可能需要时间）
        await Future.delayed(const Duration(seconds: 1));
        
        // 再次检查权限状态
        final granted = await _serviceChannel.invokeMethod<bool>('checkNotificationPermission') ?? false;
        
        if (granted) {
          await _startForegroundService();
          if (mounted) {
            final isIgnoringBatteryOptimizations = await _serviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
            ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                content: Text('权限已授予，前台服务已启动\n${isIgnoringBatteryOptimizations ? '电池优化已关闭，运行状态良好' : '建议在设置中关闭电池优化以保证连接稳定'}'),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('需要通知权限以保持相机在后台运行，请在设置中授予权限'),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        // 已有权限，直接启动服务
        await _startForegroundService();
        if (mounted) {
          final isIgnoringBatteryOptimizations = await _serviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
              content: Text('前台服务已启动\n${isIgnoringBatteryOptimizations ? '电池优化已关闭，运行状态良好' : '建议在设置中关闭电池优化以保证连接稳定'}'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动前台服务失败: $e'),
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('拒绝连接：邮箱验证失败'),
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
            try {
              final events = await DatabaseHelper().getEvents();
              // Convert events to List<Map>
              final eventsList = events.map((e) => e.toMap()).toList();
              
              final response = {
                'type': 'events_list',
                'data': eventsList,
              };
              
              _signaling?.sendData(session.sid, jsonEncode(response));
              LogUtils.i('CameraEndpoint', 'Sent ${events.length} events');
            } catch (e) {
              LogUtils.e('CameraEndpoint', 'Error getting events', e);
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
              LogUtils.i('CameraEndpoint', enabled ? '监控端已开启相机端声音' : '监控端已关闭相机端声音');
            }
            return;
          }
        } catch (_) {
          // fallthrough: treat as plain text
        }
      }
      if (!mounted) return;
      LogUtils.i('CameraEndpoint', '监控端消息: $msg');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出登录')),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账户吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _initDetector() {
    final options = PoseDetectorOptions(mode: PoseDetectionMode.stream);
    _poseDetector = PoseDetector(options: options);
    
    _startDetectionTimer();
  }

  void _startDetectionTimer() {
    _detectTimer?.cancel();
    // 每秒检测一次
    _detectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
      RenderRepaintBoundary? boundary = _videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      
      ui.Image image = await boundary.toImage();
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/frame_temp.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final inputImage = InputImage.fromFilePath(file.path);
      final poses = await _poseDetector!.processImage(inputImage);

      if (poses.isNotEmpty) {
        // 保存快照到永久目录
        final appDir = await getApplicationDocumentsDirectory();
        final snapshotDir = Directory('${appDir.path}/snapshots');
        if (!await snapshotDir.exists()) {
          await snapshotDir.create(recursive: true);
        }
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imagePath = '${snapshotDir.path}/snapshot_$timestamp.png';
        final imageFile = File(imagePath);
        await imageFile.writeAsBytes(byteData.buffer.asUint8List());

        LogUtils.i('CameraEndpoint', '检测到人物，开始录制');
        _startTenSecondsRecording(imagePath);
      }
    } catch (e) {
      LogUtils.e('CameraEndpoint', 'Detection error', e);
    } finally {
      _isDetecting = false;
    }
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

      // 10秒后停止
      Future.delayed(const Duration(seconds: 10), () async {
        await _mediaRecorder?.stop();
        _isRecording = false;
        
        // 记录到数据库
        await DatabaseHelper().insertEvent(DetectionEvent(
          timestamp: timestamp,
          imagePath: imagePath,
          videoPath: filePath,
        ));
        LogUtils.i('CameraEndpoint', 'Event saved to database');

        LogUtils.i('CameraEndpoint', 'Recording finished. Cooldown for 10 seconds.');
        _mediaRecorder = null;
        
        // 10秒冷却时间后恢复检测
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) { // 确保页面还存在
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
          builder: (context) => AlertDialog(
            title: const Text('退出相机'),
            content: const Text('确定要退出相机端吗？\n退出后将停止视频采集和前台服务。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确定'),
              ),
            ],
          ),
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
        title: const Text('相机端'),
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
            tooltip: '退出登录',
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
            child: Text(
              _isConnected ? '已连接服务器 (ID: $_selfId)' : '连接服务器中...',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
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
    final isMonitor = value == 'monitor';
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'monitor',
          child: Text('监控端'),
        ),
        PopupMenuItem(
          value: 'camera',
          child: Text('相机端'),
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
              isMonitor ? '监控端' : '相机端',
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
