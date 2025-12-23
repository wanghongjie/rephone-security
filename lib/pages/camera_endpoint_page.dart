import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';

class CameraEndpointPage extends StatefulWidget {
  const CameraEndpointPage({super.key, required this.onSwitchToMonitor});

  final VoidCallback onSwitchToMonitor;

  @override
  State<CameraEndpointPage> createState() => _CameraEndpointPageState();
}

class _CameraEndpointPageState extends State<CameraEndpointPage> {
  String _role = 'camera';
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  bool _isVideoActive = false;
  bool _isMicMuted = true; // 默认关闭麦克风
  
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
    _initRenderer();
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('权限已授予，前台服务已启动\n建议在设置中关闭电池优化以保证连接稳定'),
                duration: Duration(seconds: 4),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('前台服务已启动\n建议在设置中关闭电池优化以保证连接稳定'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Camera: Permission check error: $e');
      // Android 12以下不需要运行时权限，直接启动服务
      if (mounted) {
        await _startForegroundService();
      }
    }
  }
  
  Future<void> _startForegroundService() async {
    try {
      await _serviceChannel.invokeMethod('startForegroundService');
      print('Camera: Foreground service started');
    } catch (e) {
      print('Camera: Failed to start foreground service: $e');
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
      print('Camera: Foreground service stopped');
    } catch (e) {
      print('Camera: Failed to stop foreground service: $e');
    }
  }

  @override
  void dispose() {
    _signaling?.close();
    _stopVideo();
    _stopForegroundService();
    _localRenderer.dispose();
    super.dispose();
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
      print('Signaling state changed: $state');
      setState(() {
        _isConnected = state == SignalingState.ConnectionOpen;
      });
      if (state == SignalingState.ConnectionOpen) {
        _startVideo();
      }
    };

    _signaling!.onPeersUpdate = (event) {
      print('Peers updated: $event');
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
      print('Local stream received');
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
      print('Call state changed: $state');
      switch (state) {
        case CallState.CallStateRinging:
          // 验证邮箱权限后自动接受来电
          if (_validateEmailPermission(session)) {
            _signaling?.accept(session.sid, 'video');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('监控端已连接')),
            );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('视频通话已连接')),
          );
          break;
        case CallState.CallStateBye:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('监控端已断开')),
          );
          break;
        default:
          break;
      }
    };

    // 连接到服务器
    await _signaling!.connect();
  }

  bool _validateEmailPermission(Session session) {
    // 检查当前用户邮箱
    if (_currentUserEmail == null) {
      print('Camera: No logged in user');
      return false;
    }

    // 从peers列表中找到对应的peer信息
    final callerPeer = _peers.firstWhere(
      (peer) => peer['id'] == session.pid,
      orElse: () => null,
    );

    if (callerPeer == null) {
      print('Camera: Caller peer not found');
      return false;
    }

    // 从user_agent中提取邮箱信息
    final userAgent = callerPeer['user_agent'] as String? ?? '';
    final emailMatch = RegExp(r'email:([^|]+)').firstMatch(userAgent);
    final callerEmail = emailMatch?.group(1);

    print('Camera: Current user email: $_currentUserEmail');
    print('Camera: Caller email: $callerEmail');
    print('Camera: Caller user_agent: $userAgent');

    // 验证邮箱是否匹配
    return callerEmail == _currentUserEmail;
  }

  void _startVideo() async {
    if (_signaling != null) {
      await _signaling!.createStream('video');
    }
  }

  void _stopVideo() async {
    try {
      await _localStream?.dispose();
      _localRenderer.srcObject = null;
      setState(() {
        _isVideoActive = false;
      });
    } catch (e) {
      print('Error stopping video: $e');
    }
  }

  void _toggleMic() {
    _signaling?.muteMic();
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
  }

  void _switchCamera() {
    _signaling?.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
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
                        child: RTCVideoView(_localRenderer, mirror: true),
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
                              onPressed: _switchCamera,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.switch_camera,
                                  color: Colors.black),
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
          // 在线监控端列表
          if (_isConnected && _peers.isNotEmpty)
            Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('在线监控端:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _peers.length,
                      itemBuilder: (context, index) {
                        final peer = _peers[index];
                        if (peer['id'] == _selfId) return const SizedBox();
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text('监控端 ${peer['id']}'),
                            backgroundColor: Colors.blue.shade100,
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
