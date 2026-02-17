import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../services/signaling.dart';
import '../services/session_manager.dart';
import '../config/server_config.dart';
import '../utils/log_utils.dart';

class MonitorViewerPage extends StatefulWidget {
  const MonitorViewerPage({
    super.key, 
    required this.cameraName,
    required this.cameraDeviceId,
  });

  final String cameraName;
  final String cameraDeviceId; // 相机端设备ID

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
  String? _connectedCameraId; // 当前连接的相机端ID
  bool _cameraMicEnabled = false; // 监控端控制：相机端麦克风是否开启

  // Recording
  MediaStream? _remoteStream;
  MediaRecorder? _mediaRecorder;
  String? _recordingPath;

  bool get _isRecording => _mediaRecorder != null;
  bool _isSavingToGallery = false;
  int? _androidSdkInt;

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
    _stopRecording(showToast: false);
    _hangUp();
    _signaling?.close();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  void _connectSignaling() async {
    _signaling = Signaling(defaultAuthHost, context,
        userEmail: _currentUserEmail, 
        useLocalMedia: false,
        deviceType: 'monitor');

    // 设置回调函数在连接之前
    _signaling!.onSignalingStateChange = (SignalingState state) {
      LogUtils.i('MonitorViewer', 'Signaling state changed: $state');
      setState(() {
        _isConnected = state == SignalingState.ConnectionOpen;
      });
    };

    _signaling!.onPeersUpdate = (event) {
      LogUtils.d('MonitorViewer', 'Peers updated: $event');
      setState(() {
        _selfId = event['self'];
        _peers = event['peers'];
        // 如果收到peers更新，说明已经连接成功
        if (!_isConnected) {
          _isConnected = true;
        }
      });
      
      // 检查相机端是否离线
      if (_connectedCameraId != null) {
        final cameraStillOnline = _peers.any((peer) => peer['id'] == _connectedCameraId);
        if (!cameraStillOnline) {
          // 相机端已离线，返回上一页
          LogUtils.w('MonitorViewer', 'Camera $_connectedCameraId went offline, returning to previous page');
          if (mounted) {
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.playbackConnectFailed),
                duration: const Duration(seconds: 2),
              ),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          }
          return;
        }
      }
      
      // 自动发起连接到指定的相机端
      if (_peers.isNotEmpty && !_inCall && _connectedCameraId == null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _callCamera();
        });
      }
    };

    _signaling!.onCallStateChange = (Session session, CallState state) {
      LogUtils.i('MonitorViewer', 'Call state changed: $state');
      switch (state) {
        case CallState.CallStateNew:
          setState(() {
            _session = session;
          });
          break;
        case CallState.CallStateConnected:
          setState(() {
            _inCall = true;
            // 记录连接的相机端ID
            _connectedCameraId = session.pid;
          });
          LogUtils.i('MonitorViewer', '视频连接成功');
          break;
        case CallState.CallStateBye:
          _stopRecording(showToast: false);
          setState(() {
            _inCall = false;
            _session = null;
            _remoteRenderer.srcObject = null;
            _remoteStream = null;
            _connectedCameraId = null;
          });
          // 如果是相机端主动断开，返回上一页
          if (mounted) {
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.playbackConnectFailed),
                duration: const Duration(seconds: 2),
              ),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          }
          break;
        case CallState.CallStateInvite:
          LogUtils.i('MonitorViewer', '正在呼叫相机端...');
          break;
        default:
          break;
      }
    };

    _signaling!.onAddRemoteStream = (session, stream) {
      LogUtils.i('MonitorViewer', 'Remote stream added');
      _remoteStream = stream;
      _remoteRenderer.srcObject = stream;
      setState(() {});
    };

    _signaling!.onRemoveRemoteStream = (session, stream) {
      LogUtils.i('MonitorViewer', 'Remote stream removed');
      _stopRecording(showToast: false);
      _remoteStream = null;
      _remoteRenderer.srcObject = null;
      setState(() {});
    };

    // 连接到服务器
    await _signaling!.connect();
  }

  void _callCamera() {
    if (_signaling != null && _peers.isNotEmpty) {
      // 根据传入的相机设备ID查找对应的peer
      final cameraPeer = _peers.firstWhere(
        (peer) => peer['id'] == widget.cameraDeviceId,
        orElse: () => null,
      );
      
      if (cameraPeer != null) {
        _connectedCameraId = cameraPeer['id'];
        LogUtils.i('MonitorViewer', 'Calling camera with ID: ${widget.cameraDeviceId}');
        _signaling!.invite(cameraPeer['id'], 'video', false);
      } else {
        LogUtils.w('MonitorViewer', 'Camera ${widget.cameraDeviceId} not found in peers list');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('相机端 ${widget.cameraName} 不在线'),
            duration: const Duration(seconds: 2),
          ),
        );
        // 如果指定的相机端不在线，返回上一页
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    }
  }

  void _hangUp() {
    _stopRecording(showToast: false);
    if (_session != null) {
      _signaling?.bye(_session!.sid);
    }
  }

  void _toggleCameraMic() {
    final sid = _session?.sid;
    if (sid == null) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cameraEndpointConnecting)),
      );
      return;
    }
    final nextEnabled = !_cameraMicEnabled;
    final payload = jsonEncode({
      'type': 'camera_mic',
      'enabled': nextEnabled,
    });
    _signaling?.sendData(sid, payload);
    setState(() {
      _cameraMicEnabled = nextEnabled;
    });
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nextEnabled
            ? l.cameraEndpointLogMicOn
            : l.cameraEndpointLogMicOff),
      ),
    );
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    final stream = _remoteStream;
    if (stream == null || stream.getVideoTracks().isEmpty) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.playbackGetVideoFailed)),
        );
      }
      return;
    }

    try {
      final recorder = MediaRecorder();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/rephone_${widget.cameraDeviceId}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      await recorder.start(
        path,
        videoTrack: stream.getVideoTracks().first,
      );

      setState(() {
        _mediaRecorder = recorder;
        _recordingPath = path;
      });

      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.cameraEndpointRecording)),
        );
      }
    } catch (e) {
      try {
        await _mediaRecorder?.stop();
      } catch (_) {}
      setState(() {
        _mediaRecorder = null;
        _recordingPath = null;
      });
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.cameraEndpointServiceStartFailed}$e')),
        );
      }
    }
  }

  Future<void> _stopRecording({bool showToast = true}) async {
    final recorder = _mediaRecorder;
    if (recorder == null) return;
    final savedPath = _recordingPath;

    try {
      await recorder.stop();
    } catch (_) {
      // ignore
    }

    setState(() {
      _mediaRecorder = null;
      _recordingPath = null;
    });

    if (!mounted) return;

    if (showToast) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cameraEndpointRecordSaved)),
      );
    }

    // Only show the action sheet when user explicitly stopped recording.
    if (showToast && savedPath != null) {
      await _showPostRecordingActionsSheet(savedPath);
    }
  }

  Future<void> _showPostRecordingActionsSheet(String path) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.cameraEndpointRecordSaved,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isSavingToGallery
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _saveVideoToGallery(path);
                        },
                  icon: _isSavingToGallery
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _isSavingToGallery
                        ? l.playbackDownloadingAndSaving
                        : l.playbackSaveToGallerySuccess,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: null, // TODO: implement share
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l.playbackGetVideoFailed),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.commonCancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveVideoToGallery(String path) async {
    if (_isSavingToGallery) return;
    setState(() {
      _isSavingToGallery = true;
    });

    try {
      final permissionOk = await _requestGalleryPermissionIfNeeded();
      if (!permissionOk) {
        if (mounted) {
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.appPermissionsPhotosSubtitle)),
          );
        }
        return;
      }

      final ok = await GallerySaver.saveVideo(
        path,
        albumName: 'RePhone Security',
      );

      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok == true
                ? l.playbackSaveToGallerySuccess
                : l.playbackSaveToGalleryFailed),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.playbackSaveToGalleryFailed}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingToGallery = false;
        });
      } else {
        _isSavingToGallery = false;
      }
    }
  }

  Future<bool> _requestGalleryPermissionIfNeeded() async {
    if (Platform.isIOS) {
      // iOS: request "add only" first if available, fallback to full photos.
      final addOnly = await Permission.photosAddOnly.request();
      if (addOnly.isGranted || addOnly.isLimited) return true;

      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }

    if (Platform.isAndroid) {
      // Android 10+ (API 29+) typically doesn't need runtime permission to save
      // media to gallery via MediaStore. Android 9 and below needs storage.
      final sdk = await _getAndroidSdkInt();
      if (sdk != null && sdk <= 28) {
        final storage = await Permission.storage.request();
        return storage.isGranted || storage.isLimited;
      }
      return true;
    }

    return true;
  }

  Future<int?> _getAndroidSdkInt() async {
    if (!Platform.isAndroid) return null;
    if (_androidSdkInt != null) return _androidSdkInt;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _androidSdkInt = info.version.sdkInt;
      return _androidSdkInt;
    } catch (_) {
      return null;
    }
  }

  Future<void> _captureSnapshot() async {
    if (!_inCall || _remoteRenderer.srcObject == null) return;

    try {
      final stream = _remoteRenderer.srcObject!;
      final tracks = stream.getVideoTracks();
      if (tracks.isEmpty) return;

      final track = tracks.first;
      final buffer = await track.captureFrame();
      final bytes = buffer.asUint8List();

      if (bytes.isNotEmpty) {
        final dir = await getApplicationDocumentsDirectory();
        final coversDir = Directory('${dir.path}/covers');
        if (!await coversDir.exists()) {
          await coversDir.create(recursive: true);
        }

        final file = File('${coversDir.path}/cover_${widget.cameraDeviceId}.jpg');
        await file.writeAsBytes(bytes);
        LogUtils.i('MonitorViewer', 'Snapshot saved to ${file.path}');
      }
    } catch (e) {
      LogUtils.e('MonitorViewer', 'Failed to capture snapshot: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _captureSnapshot();
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.cameraName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_inCall)
            IconButton(
              tooltip: _cameraMicEnabled
                  ? l.cameraEndpointLogMicOff
                  : l.cameraEndpointLogMicOn,
              onPressed: _toggleCameraMic,
              icon: Icon(
                _cameraMicEnabled ? Icons.volume_up : Icons.volume_off,
              ),
            ),
          if (_inCall && _remoteStream != null)
            IconButton(
              tooltip:
                  _isRecording ? l.cameraEndpointRecordSaved : l.cameraEndpointRecord10s,
              onPressed: _isRecording ? _stopRecording : _startRecording,
              icon: Icon(
                _isRecording ? Icons.stop : Icons.fiber_manual_record,
                color: _isRecording ? Colors.white : Colors.red,
              ),
            ),
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
              _isConnected
                  ? l.cameraEndpointConnectedWithId
                      .replaceFirst('{id}', _selfId ?? '')
                  : l.cameraEndpointConnecting,
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
                  ? Stack(
                      children: [
                        RTCVideoView(_remoteRenderer),
                        if (_isRecording)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'REC',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
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
                            _inCall
                                ? l.playbackConnecting
                                : l.cameraListEmptyHint,
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
                  l.playbackConnecting,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
