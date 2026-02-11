import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'video_player_page.dart';
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
  
  // Pagination
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _isFirstLoading = true;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 15;

  // Video download state
  bool _isDownloadingVideo = false;
  int? _downloadingEventId;
  int _receivedVideoBytes = 0;
  int _totalVideoBytes = 0;
  IOSink? _videoFileSink;
  File? _tempVideoFile;
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadUserInfo();
  }

  @override
  void dispose() {
    _signaling?.close();
    _scrollController.dispose();
    _progressNotifier.dispose();
    _videoFileSink?.close();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        _isConnected) {
      _loadMoreEvents();
    }
  }

  Future<void> _loadMoreEvents() async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    _requestEventList(_currentSession?.sid ?? '', offset: _currentOffset);
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
        _requestEventList(session.sid, offset: 0);
      }
      
      // 监听状态变化，确保连接打开后再发送
       dc.onDataChannelState = (state) {
         LogUtils.i('PlaybackPage', 'DataChannel state changed: $state');
         // Temporary workaround for enum value mismatch
         if (state.toString() == 'RTCDataChannelState.RTCDataChannelOpen') {
           _requestEventList(session.sid, offset: 0);
         }
       };
    };

    _signaling!.onDataChannelMessage = (Session session, RTCDataChannel dc, RTCDataChannelMessage data) async {
      if (data.isBinary) {
        if (_isDownloadingVideo && _videoFileSink != null) {
          _videoFileSink!.add(data.binary);
          _receivedVideoBytes += data.binary.length;
          if (_totalVideoBytes > 0) {
            _progressNotifier.value = _receivedVideoBytes / _totalVideoBytes;
          }
        }
        return;
      }
      
      try {
        final json = jsonDecode(data.text);
        
        if (json['type'] == 'video_start') {
            final int size = json['size'];
            final int id = json['id'];
            if (id == _downloadingEventId) {
              _totalVideoBytes = size;
              LogUtils.i('PlaybackPage', 'Started receiving video $id, size: $size');
            }
            return;
         }
         
         if (json['type'] == 'video_end') {
            final int id = json['id'];
            if (id == _downloadingEventId) {
              await _videoFileSink?.flush();
              await _videoFileSink?.close();
              _videoFileSink = null;
              
              // Rename .tmp to .mp4 to mark as complete
              File? finalFile;
              if (_tempVideoFile != null && await _tempVideoFile!.exists()) {
                final tempDir = await getTemporaryDirectory();
                final String finalPath = '${tempDir.path}/video_${id}.mp4';
                finalFile = await _tempVideoFile!.rename(finalPath);
              }
              
              _isDownloadingVideo = false;
              
              if (mounted) {
                Navigator.pop(context); // Close dialog
                
                // Navigate to player
                if (finalFile != null && await finalFile.exists()) {
                   Navigator.of(context).push(
                     MaterialPageRoute(
                       builder: (context) => VideoPlayerPage(
                         videoFile: finalFile!,
                         title: '回看录像',
                       ),
                     ),
                   );
                }
              }
              LogUtils.i('PlaybackPage', 'Video received and cached successfully');
            }
            return;
         }
        
        if (json['type'] == 'video_error') {
           if (json['id'] == _downloadingEventId) {
             _videoFileSink?.close();
             _videoFileSink = null;
             _isDownloadingVideo = false;
             if (mounted) {
               Navigator.pop(context); // Close dialog
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('获取视频失败: ${json['message']}')),
               );
             }
           }
           return;
        }

        if (json['type'] == 'events_list') {
          final List<dynamic> list = json['data'];
          final int offset = json['offset'] ?? 0;
          
          LogUtils.i('PlaybackPage', 'Received ${list.length} events (offset: $offset)');
          if (mounted) {
            setState(() {
              if (offset == 0) {
                _events = List<Map<String, dynamic>>.from(list);
              } else {
                _events.addAll(List<Map<String, dynamic>>.from(list));
              }
            });
            
            // Defer the loading state update to the next frame to ensure UI is rendered
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isLoadingMore = false;
                  _isFirstLoading = false;
                  _currentOffset = _events.length;
                  _hasMore = list.length >= _pageSize;
                });
              }
            });
          }
        }
      } catch (e) {
        LogUtils.e('PlaybackPage', 'Error parsing message', e);
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
            _isFirstLoading = false;
          });
        }
      }
    };

    await _signaling!.connect();
  }

  Future<void> _requestVideo(Map<String, dynamic> event) async {
    if (_isDownloadingVideo) return;
    
    final int eventId = event['id'];
    final tempDir = await getTemporaryDirectory();
    
    // Check if video already exists in cache
    try {
      final cacheFile = File('${tempDir.path}/video_${eventId}.mp4');
      if (await cacheFile.exists()) {
        LogUtils.i('PlaybackPage', 'Video $eventId found in cache, playing directly');
        if (mounted) {
           Navigator.of(context).push(
             MaterialPageRoute(
               builder: (context) => VideoPlayerPage(
                 videoFile: cacheFile,
                 title: '回看录像',
               ),
             ),
           );
        }
        return;
      }
    } catch (e) {
      LogUtils.e('PlaybackPage', 'Error checking video cache', e);
    }
    
    // Prepare for download - Open sink immediately to avoid race condition
    final tempFile = File('${tempDir.path}/video_${eventId}.tmp');
    IOSink? sink;
    try {
      sink = tempFile.openWrite();
    } catch (e) {
      LogUtils.e('PlaybackPage', 'Error opening video file for write', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法创建临时文件: $e')),
        );
      }
      return;
    }
    
    setState(() {
      _isDownloadingVideo = true;
      _downloadingEventId = eventId;
      _receivedVideoBytes = 0;
      _totalVideoBytes = 0;
      _progressNotifier.value = 0.0;
      _tempVideoFile = tempFile;
      _videoFileSink = sink;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在获取视频...'),
          content: ValueListenableBuilder<double>(
            valueListenable: _progressNotifier,
            builder: (context, value, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value > 0 ? value : null),
                  const SizedBox(height: 10),
                  Text('${(value * 100).toStringAsFixed(1)}%'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                 Navigator.pop(context);
                 setState(() {
                   _isDownloadingVideo = false;
                   _videoFileSink?.close();
                   _videoFileSink = null;
                 });
              },
              child: const Text('取消'),
            )
          ],
        ),
      ),
    );

    LogUtils.i('PlaybackPage', 'Requesting video for event $eventId');
    _signaling!.sendData(_currentSession!.sid, jsonEncode({
      'type': 'get_video',
      'id': eventId,
    }));
  }

  void _requestEventList(String sessionId, {required int offset}) {
    LogUtils.i('PlaybackPage', 'Requesting event list (offset: $offset)...');
    _signaling!.sendData(sessionId, jsonEncode({
      'type': 'get_events',
      'limit': _pageSize,
      'offset': offset,
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
                setState(() {
                   _isConnecting = true;
                   _isFirstLoading = true;
                });
                _connectSignaling();
              }, 
              child: const Text('重试')
            ),
          ],
        ),
      );
    }

    if (_isFirstLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载录像列表...'),
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
      controller: _scrollController,
      itemCount: _events.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _events.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        final event = _events[index];
        final timestamp = event['timestamp'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        Widget thumbnailWidget;
        final String? thumbnailData = event['thumbnail'];
        
        if (thumbnailData != null && thumbnailData.isNotEmpty) {
          try {
             final bytes = base64Decode(thumbnailData);
             thumbnailWidget = Image.memory(
               bytes, 
               width: 120, 
               height: 90, 
               fit: BoxFit.cover,
               errorBuilder: (context, error, stackTrace) {
                 return Container(
                   width: 120, 
                   height: 90,
                   color: Colors.grey[300],
                   child: const Icon(Icons.broken_image, color: Colors.grey),
                 );
               },
             );
          } catch (e) {
             thumbnailWidget = Container(
               width: 120, 
               height: 90,
               color: Colors.grey[300],
               child: const Icon(Icons.broken_image, color: Colors.grey),
             );
          }
        } else {
          thumbnailWidget = Container(
            width: 120, 
            height: 90,
            color: Colors.grey[200],
            child: const Icon(Icons.videocam, size: 40, color: Colors.blueGrey),
          );
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (_currentSession == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('未连接到相机，无法回看')),
                );
                return;
              }
              _requestVideo(event);
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: thumbnailWidget,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 14, 
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: Colors.blue[700]),
                            const SizedBox(width: 4),
                            Text(
                              '智能检测录像',
                              style: TextStyle(
                                fontSize: 13, 
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.play_circle_outline, size: 36, color: Colors.blue),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
