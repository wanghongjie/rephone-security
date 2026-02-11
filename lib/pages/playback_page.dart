import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/camera_device.dart';
import '../models/detection_event.dart'; // 需要用到 DetectionEvent 模型来解析，或者直接用 Map
import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';
import '../utils/log_utils.dart';

class PlaybackPage extends StatefulWidget {
  final CameraDevice camera;

  const PlaybackPage({
    super.key,
    required this.camera,
  });

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  Signaling? _signaling;
  String? _currentUserEmail;
  bool _isConnected = false;
  bool _isConnecting = true;
  List<Map<String, dynamic>> _events = []; // 存储接收到的事件数据
  Session? _currentSession;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _signaling?.close();
    super.dispose();
  }

  void _loadUserInfo() async {
    final user = await SessionManager.getUser();
    _currentUserEmail = user?.email;
    _connectSignaling();
  }

  void _connectSignaling() async {
    _signaling = Signaling(defaultAuthHost, context,
        userEmail: _currentUserEmail, 
        useLocalMedia: false,
        deviceType: 'monitor');

    _signaling!.onSignalingStateChange = (SignalingState state) {
      LogUtils.i('PlaybackPage', 'Signaling state: $state');
      if (state == SignalingState.ConnectionClosed) {
         if (mounted) {
           setState(() {
             _isConnected = false;
             _isConnecting = false;
           });
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('信令服务器连接断开')),
           );
         }
      }
    };

    _signaling!.onPeersUpdate = (event) {
      final peers = event['peers'] as List;
      final cameraOnline = peers.any((p) => p['id'] == widget.camera.id);
      
      if (cameraOnline && _currentSession == null) {
        LogUtils.i('PlaybackPage', 'Found camera online, initiating connection...');
        // 发起 DataChannel 连接 (media='data')
        _signaling!.invite(widget.camera.id, 'data', false);
      } else if (!cameraOnline) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('相机设备不在线')),
          );
        }
      }
    };

    _signaling!.onCallStateChange = (Session session, CallState state) {
      LogUtils.i('PlaybackPage', 'Call state: $state');
      if (state == CallState.CallStateConnected) {
        _currentSession = session;
        if (mounted) {
          setState(() {
            _isConnected = true;
            _isConnecting = false;
          });
        }
        // 连接建立后，稍作延迟发送请求，确保 DataChannel 就绪
        // 注意：DataChannel 的开启可能比 CallStateConnected 稍晚，或者需要等待 onDataChannelOpen
        // 但 Signaling 类封装了，sendData 会检查 dc 是否为 null
        // 最好在 onDataChannel 回调中发送，或者重试
      } else if (state == CallState.CallStateBye) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _currentSession = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('连接已断开')),
          );
        }
      }
    };

    _signaling!.onDataChannel = (Session session, RTCDataChannel dc) {
      LogUtils.i('PlaybackPage', 'DataChannel created: ${dc.label}, state: ${dc.state}');
      
      if (dc.state.toString() == 'RTCDataChannelState.RTCDataChannelOpen') {
        _requestEventList(session.sid);
      }
      
      // 监听状态变化，确保连接打开后再发送
       dc.onDataChannelState = (state) {
         LogUtils.i('PlaybackPage', 'DataChannel state changed: $state');
         // Temporary workaround for enum value mismatch
         if (state.toString() == 'RTCDataChannelState.RTCDataChannelOpen') {
           _requestEventList(session.sid);
         }
       };
    };

    _signaling!.onDataChannelMessage = (Session session, RTCDataChannel dc, RTCDataChannelMessage data) {
      if (data.isBinary) return;
      
      try {
        final json = jsonDecode(data.text);
        if (json['type'] == 'events_list') {
          final List<dynamic> list = json['data'];
          LogUtils.i('PlaybackPage', 'Received ${list.length} events');
          if (mounted) {
            setState(() {
              _events = List<Map<String, dynamic>>.from(list);
            });
          }
        }
      } catch (e) {
        LogUtils.e('PlaybackPage', 'Error parsing message', e);
      }
    };

    await _signaling!.connect();
  }

  void _requestEventList(String sessionId) {
    LogUtils.i('PlaybackPage', 'Requesting event list...');
    _signaling!.sendData(sessionId, jsonEncode({
      'type': 'get_events',
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.camera.name} - SD卡回看'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接相机...'),
          ],
        ),
      );
    }

    if (!_isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.signal_wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('无法连接到相机'),
            TextButton(
              onPressed: () {
                setState(() => _isConnecting = true);
                _connectSignaling();
              }, 
              child: const Text('重试')
            ),
          ],
        ),
      );
    }

    if (_events.isEmpty) {
      return const Center(
        child: Text('暂无录制记录'),
      );
    }

    return ListView.builder(
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        final timestamp = event['timestamp'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        return ListTile(
          leading: const Icon(Icons.video_file, color: Colors.blue),
          title: Text(date.toString().split('.')[0]), // 简单格式化
          subtitle: Text('ID: ${event['id']}'),
          onTap: () {
            // TODO: 实现点击播放或查看图片
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('播放功能开发中...')),
            );
          },
        );
      },
    );
  }
}
