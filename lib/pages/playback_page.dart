import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'membership_page.dart';
import 'video_player_page.dart';
import '../models/camera_device.dart';
import '../models/detection_event.dart'; // 需要用到 DetectionEvent 模型来解析，或者直接用 Map
import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';
import '../utils/log_utils.dart';
import '../l10n/app_localizations.dart';

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
  
  bool _isCurrentlyMember = false;

  // Pagination
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _isFirstLoading = true;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 15;
  Completer<void>? _refreshCompleter;

  // Video download state
  bool _isDownloadingVideo = false;
  bool _isSavingToGallery = false;
  int? _downloadingEventId;
  int _receivedVideoBytes = 0;
  int _totalVideoBytes = 0;
  IOSink? _videoFileSink;
  File? _tempVideoFile;
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);

  // Thumbnail cache
  final Map<int, Uint8List?> _thumbnailCache = {};

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

  Future<void> _checkVipBeforeAction(VoidCallback action) async {
    if (_isCurrentlyMember) {
      action();
      return;
    }

    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.playbackVipRequiredTitle),
        content: Text(l.playbackVipRequiredContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Navigate to Home and switch to Membership tab (index 1)
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/home',
                (route) => false,
                arguments: 1,
              );
            },
            child: Text(l.playbackVipRequiredButton),
          ),
        ],
      ),
    );
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
    if (mounted) {
      setState(() {
        _isCurrentlyMember = (user?.vipLevel ?? 0) > 0;
      });
    }
    _connectSignaling();
  }

  void _connectSignaling() async {
    _signaling = Signaling(defaultAuthHost, context,
        userEmail: _currentUserEmail, 
        useLocalMedia: false,
        deviceType: 'monitor');

    _signaling!.onSignalingStateChange = (SignalingState state) {
      LogUtils.i('PlaybackPage', 'Signaling state: $state');
      if (state == SignalingState.ConnectionClosed || state == SignalingState.ConnectionError) {
         if (mounted) {
           setState(() {
             _isConnected = false;
             _isConnecting = false;
             _currentSession = null;
             _events.clear();
           });
         }
      }
    };

    _signaling!.onPeersUpdate = (event) {
      final peers = event['peers'] as List;
      final cameraOnline = peers.any((p) => p['id'] == widget.camera.id);
      
      LogUtils.d('PlaybackPage', 'Peers update. Camera online: $cameraOnline, Current session: ${_currentSession?.sid}');
      
      if (cameraOnline && _currentSession == null) {
        LogUtils.i('PlaybackPage', 'Found camera online, initiating connection...');
        // 发起 DataChannel 连接 (media='data')
        _signaling!.invite(widget.camera.id, 'data', false);
      } else if (!cameraOnline) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
          });
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
        }
      }
    };

    _signaling!.onDataChannel = (Session session, RTCDataChannel dc) {
      LogUtils.i('PlaybackPage', 'DataChannel created: ${dc.label}, state: ${dc.state}');
      
      if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
        _requestEventList(session.sid, offset: 0);
      }
      
      // 监听状态变化，确保连接打开后再发送
       dc.onDataChannelState = (state) {
         LogUtils.i('PlaybackPage', 'DataChannel state changed: $state');
         if (state == RTCDataChannelState.RTCDataChannelOpen) {
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
                
                if (finalFile != null && await finalFile.exists()) {
                   if (_isSavingToGallery) {
                      bool? success = await GallerySaver.saveVideo(finalFile.path);
                      if (mounted) {
                        final l = AppLocalizations.of(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success == true ? l.tr('playbackSaveToGallerySuccess') : l.tr('playbackSaveToGalleryFailed'))),
                        );
                      }
                   } else {
                      // Navigate to player
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => VideoPlayerPage(
                            videoFile: finalFile!,
                            title: AppLocalizations.of(context).tr('playbackVideoTitle'),
                          ),
                        ),
                      );
                   }
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
               Navigator.pop(context);
               final l = AppLocalizations.of(context);
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('${l.tr('playbackGetVideoFailed')}: ${json['message']}')),
               );
             }
           }
           return;
        }

        if (json['type'] == 'delete_event_success') {
           final int id = json['id'];
           if (mounted) {
             setState(() {
               _events.removeWhere((e) => e['id'] == id);
             });
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('删除成功')),
             );
           }
           return;
        }

        if (json['type'] == 'delete_event_error') {
           final String message = json['message'] ?? 'Unknown error';
           if (mounted) {
             final l = AppLocalizations.of(context);
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('${l.tr('playbackDeleteEventFailed')}: $message')),
             );
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
            
            // Complete refresh if needed
            if (offset == 0 && _refreshCompleter != null && !_refreshCompleter!.isCompleted) {
              _refreshCompleter!.complete();
              _refreshCompleter = null;
            }
            
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
        
        if (json['type'] == 'thumbnail') {
           final int id = json['id'];
           final String data = json['data'];
           
           try {
             final bytes = base64Decode(data);
             if (mounted) {
               setState(() {
                 _thumbnailCache[id] = bytes;
               });
             }
           } catch (e) {
             LogUtils.e('PlaybackPage', 'Error decoding thumbnail for $id', e);
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

  Future<void> _startVideoAction(Map<String, dynamic> event, {required bool saveToGallery}) async {
    if (_isDownloadingVideo) return;
    
    final int eventId = event['id'];
    final tempDir = await getTemporaryDirectory();
    
    // Check if video already exists in cache
    try {
      final cacheFile = File('${tempDir.path}/video_${eventId}.mp4');
      if (await cacheFile.exists()) {
        LogUtils.i('PlaybackPage', 'Video $eventId found in cache');
        if (saveToGallery) {
           bool? success = await GallerySaver.saveVideo(cacheFile.path);
           if (mounted) {
             final l = AppLocalizations.of(context);
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text(success == true ? l.tr('playbackSaveToGallerySuccess') : l.tr('playbackSaveToGalleryFailed'))),
             );
           }
        } else {
           if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => VideoPlayerPage(
                    videoFile: cacheFile,
                    title: AppLocalizations.of(context).tr('playbackVideoTitle'),
                  ),
                ),
              );
           }
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
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.tr('playbackCreateTempFileFailed'))),
        );
      }
      return;
    }
    
    setState(() {
      _isDownloadingVideo = true;
      _isSavingToGallery = saveToGallery;
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
          title: Text(saveToGallery ? AppLocalizations.of(context).tr('playbackDownloadingAndSaving') : AppLocalizations.of(context).tr('playbackFetchingVideo')),
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
              child: Text(AppLocalizations.of(context).commonCancel),
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

  void _deleteEvent(Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条录像吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _signaling!.sendData(_currentSession!.sid, jsonEncode({
                'type': 'delete_event',
                'id': event['id']
              }));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _requestEventList(String sessionId, {required int offset}) {
    LogUtils.i('PlaybackPage', 'Requesting event list (offset: $offset)...');
    _signaling!.sendData(sessionId, jsonEncode({
      'type': 'get_events',
      'limit': _pageSize,
      'offset': offset,
    }));
  }

  void _requestThumbnail(int eventId) {
    if (_thumbnailCache.containsKey(eventId)) return;
    
    // Use a placeholder to prevent duplicate requests
    _thumbnailCache[eventId] = null;
    
    LogUtils.d('PlaybackPage', 'Requesting thumbnail for event $eventId');
    _signaling!.sendData(_currentSession!.sid, jsonEncode({
      'type': 'get_thumbnail',
      'id': eventId,
    }));
  }
  
  Future<void> _onRefresh() async {
    if (!_isConnected || _currentSession == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('未连接到相机')),
        );
      }
      return;
    }
    
    _refreshCompleter = Completer<void>();
    _requestEventList(_currentSession!.sid, offset: 0);
    
    // Timeout fallback (5 seconds)
    Future.delayed(const Duration(seconds: 5), () {
       if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
          _refreshCompleter!.complete();
          _refreshCompleter = null;
       }
    });
    
    return _refreshCompleter!.future;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.playbackTitleSuffix),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final l = AppLocalizations.of(context);
    if (_isConnecting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.playbackConnecting),
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
            Text(l.playbackConnectFailed),
            TextButton(
              onPressed: () {
                setState(() {
                   _isConnecting = true;
                   _isFirstLoading = true;
                });
                _connectSignaling();
              },
              child: Text(l.playbackRetry),
            ),
          ],
        ),
      );
    }

    if (_isFirstLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.playbackLoadList),
          ],
        ),
      );
    }

    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Center(
                  child: Text(l.playbackEmpty),
                ),
              ),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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
        final int eventId = event['id'];
        final timestamp = event['timestamp'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        // Request thumbnail if not loaded
        if (!_thumbnailCache.containsKey(eventId)) {
           // Defer request to avoid build-phase side effects
           WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted && _currentSession != null) {
                _requestThumbnail(eventId);
             }
           });
        }
        
        Widget thumbnailWidget;
        final Uint8List? thumbnailBytes = _thumbnailCache[eventId];
        
        if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
           thumbnailWidget = Image.memory(
             thumbnailBytes, 
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
              _checkVipBeforeAction(() {
                _startVideoAction(event, saveToGallery: false);
              });
            },
            onLongPress: () {
              if (_currentSession == null) return;
              
              showModalBottomSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.save_alt),
                        title: const Text('保存到相册'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _startVideoAction(event, saveToGallery: true);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete, color: Colors.red),
                        title: const Text('删除', style: TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _deleteEvent(event);
                        },
                      ),
                    ],
                  ),
                ),
              );
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
                            Builder(
                              builder: (context) {
                                final l = AppLocalizations.of(context);
                                return Text(
                                  l.playbackSmartDetectionLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              },
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
    ),
  );
  }
}
