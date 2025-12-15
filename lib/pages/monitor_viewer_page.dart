import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';

class MonitorViewerPage extends StatefulWidget {
  const MonitorViewerPage({super.key, required this.cameraName});

  final String cameraName;

  @override
  State<MonitorViewerPage> createState() => _MonitorViewerPageState();
}

class _MonitorViewerPageState extends State<MonitorViewerPage> {
  final _remoteRenderer = RTCVideoRenderer();
  Signaling? _signaling;
  String? _selfId;
  List<dynamic> _peers = [];
  bool _isConnected = false;
  bool _inCall = false;
  Session? _session;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _loadUserInfo();
  }

  void _loadUserInfo() async {
    final user = await SessionManager.getUser();
    _currentUserEmail = user?.email;
    _connectSignaling();
  }

  @override
  void dispose() {
    _hangUp();
    _signaling?.close();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  void _connectSignaling() async {
    _signaling = Signaling(defaultAuthHost, context, userEmail: _currentUserEmail);
    
    // 设置回调函数在连接之前
    _signaling!.onSignalingStateChange = (SignalingState state) {
      print('Monitor signaling state changed: $state');
      setState(() {
        _isConnected = state == SignalingState.ConnectionOpen;
      });
    };

    _signaling!.onPeersUpdate = (event) {
      print('Monitor peers updated: $event');
      setState(() {
        _selfId = event['self'];
        _peers = event['peers'];
        // 如果收到peers更新，说明已经连接成功
        if (!_isConnected) {
          _isConnected = true;
        }
      });
      
      // 自动发起连接到相机端
      if (_peers.isNotEmpty && !_inCall) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _callCamera();
        });
      }
    };

    _signaling!.onCallStateChange = (Session session, CallState state) {
      print('Monitor call state changed: $state');
      switch (state) {
        case CallState.CallStateNew:
          setState(() {
            _session = session;
          });
          break;
        case CallState.CallStateConnected:
          setState(() {
            _inCall = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('视频连接成功')),
          );
          break;
        case CallState.CallStateBye:
          setState(() {
            _inCall = false;
            _session = null;
            _remoteRenderer.srcObject = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('视频通话已结束')),
          );
          break;
        case CallState.CallStateInvite:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('正在呼叫相机端...')),
          );
          break;
        default:
          break;
      }
    };

    _signaling!.onAddRemoteStream = (session, stream) {
      print('Monitor remote stream added');
      _remoteRenderer.srcObject = stream;
      setState(() {});
    };

    _signaling!.onRemoveRemoteStream = (session, stream) {
      print('Monitor remote stream removed');
      _remoteRenderer.srcObject = null;
      setState(() {});
    };

    // 连接到服务器
    await _signaling!.connect();
  }

  void _callCamera() {
    if (_signaling != null && _peers.isNotEmpty) {
      // 找到第一个非自己的peer（相机端）
      final cameraPeer = _peers.firstWhere(
        (peer) => peer['id'] != _selfId,
        orElse: () => null,
      );
      
      if (cameraPeer != null) {
        _signaling!.invite(cameraPeer['id'], 'video', false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到在线的相机端')),
        );
      }
    }
  }

  void _hangUp() {
    if (_session != null) {
      _signaling?.bye(_session!.sid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('监控 - ${widget.cameraName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
          // 视频显示区域
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(color: Colors.black),
              child: _inCall && _remoteRenderer.srcObject != null
                  ? RTCVideoView(_remoteRenderer)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_off,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _inCall ? '等待视频流...' : '点击下方按钮连接相机',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          // 状态显示区域
          if (!_inCall && _isConnected)
            Container(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  _peers.isEmpty ? '等待相机端上线...' : '正在连接相机端...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          // 在线设备列表
          if (_isConnected && _peers.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('在线设备:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            label: Text('相机端 ${peer['id']}'),
                            backgroundColor: Colors.orange.shade100,
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
