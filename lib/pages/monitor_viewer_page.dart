import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
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
  bool _monitorTalkbackOn = false; // 监控端本地麦克风 → 相机端播放（对讲）

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
    _restoreDefaultAudioRoute();
    // 清理 signaling 回调，避免在页面销毁后仍然触发 setState
    if (_signaling != null) {
      _signaling!
        ..onSignalingStateChange = null
        ..onPeersUpdate = null
        ..onCallStateChange = null
        ..onAddRemoteStream = null
        ..onRemoveRemoteStream = null
        ..onAddRemoteAudioStream = null;
    }
    _signaling?.close();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  /// Android: earpiece is often effectively silent for WebRTC remote audio.
  /// iOS: WebRTC 内部用 `PlayAndRecord`；若用 `remoteOnly`（playback）易与 RTCAudioSession
  /// 抢会话，冷启动常见 -50 且首次无声。监控页统一用 [AppleAudioIOMode.localAndRemote] +
  /// 扬声器（未开对讲时也不采音，仅会话类别与引擎一致）。
  void _preferSpeakerForRemotePlayback() {
    if (Platform.isAndroid) {
      Helper.setSpeakerphoneOn(true).catchError((Object e, StackTrace st) {
        LogUtils.w('MonitorViewer', 'setSpeakerphoneOn: $e');
      });
    } else if (Platform.isIOS) {
      unawaited(_applyIosMonitorAudioMode());
    }
  }

  Future<void> _applyIosMonitorAudioMode() async {
    if (!Platform.isIOS) return;
    try {
      await Helper.setAppleAudioIOMode(
        AppleAudioIOMode.localAndRemote,
        preferSpeakerOutput: true,
      );
    } catch (e) {
      LogUtils.w('MonitorViewer', 'setAppleAudioIOMode: $e');
    }
  }

  /// 相机端单流音视频；unified-plan 下 audio/video `onTrack` 顺序不定，有视频轨时绑定
  /// 主渲染器；音频轨后到时会再次回调，再赋一次 `srcObject` 以便部分机型刷新播放。
  void _syncRemoteStream(MediaStream stream) {
    _remoteStream = stream;
    if (stream.getVideoTracks().isNotEmpty) {
      _remoteRenderer.srcObject = stream;
    }
    _preferSpeakerForRemotePlayback();
  }

  void _restoreDefaultAudioRoute() {
    if (Platform.isAndroid) {
      Helper.setSpeakerphoneOn(false).catchError((Object e, StackTrace st) {
        LogUtils.w('MonitorViewer', 'reset audio route: $e');
      });
    } else if (Platform.isIOS) {
      unawaited(_applyIosMonitorAudioModeNone());
    }
  }

  Future<void> _applyIosMonitorAudioModeNone() async {
    try {
      await Helper.setAppleAudioIOMode(AppleAudioIOMode.none);
    } catch (e) {
      LogUtils.w('MonitorViewer', 'setAppleAudioIOMode none: $e');
    }
  }

  void _connectSignaling() async {
    _signaling = Signaling(defaultAuthHost, context,
        userEmail: _currentUserEmail, 
        useLocalMedia: false,
        deviceType: 'monitor');

    // 设置回调函数在连接之前
    _signaling!.onSignalingStateChange = (SignalingState state) {
      LogUtils.i('MonitorViewer', 'Signaling state changed: $state');
      if (!mounted) return;
      setState(() {
        _isConnected = state == SignalingState.ConnectionOpen;
      });
    };

    _signaling!.onPeersUpdate = (event) {
      LogUtils.d('MonitorViewer', 'Peers updated: $event');
      if (!mounted) return;
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
          if (!mounted) return;
          setState(() {
            _session = session;
          });
          break;
        case CallState.CallStateConnected:
          if (!mounted) return;
          setState(() {
            _inCall = true;
            // 记录连接的相机端ID
            _connectedCameraId = session.pid;
          });
          LogUtils.i('MonitorViewer', '视频连接成功');
          if (Platform.isIOS) {
            final sid = session.sid;
            Future<void>.delayed(const Duration(milliseconds: 900), () {
              if (!mounted || !_inCall || _session?.sid != sid) return;
              unawaited(_applyIosMonitorAudioMode());
            });
          }
          break;
        case CallState.CallStateBye:
          _stopRecording(showToast: false);
          _restoreDefaultAudioRoute();
          if (!mounted) return;
          setState(() {
            _inCall = false;
            _session = null;
            _remoteRenderer.srcObject = null;
            _remoteStream = null;
            _connectedCameraId = null;
            _cameraMicEnabled = false;
            _monitorTalkbackOn = false;
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
      LogUtils.i('MonitorViewer', 'Remote stream added (video track)');
      _syncRemoteStream(stream);
      if (!mounted) return;
      setState(() {});
    };

    _signaling!.onAddRemoteAudioStream = (session, stream) {
      LogUtils.i(
        'MonitorViewer',
        'Remote audio track: v=${stream.getVideoTracks().length} a=${stream.getAudioTracks().length}',
      );
      _syncRemoteStream(stream);
      if (!mounted) return;
      setState(() {});
    };

    _signaling!.onRemoveRemoteStream = (session, stream) {
      LogUtils.i('MonitorViewer', 'Remote stream removed');
      _stopRecording(showToast: false);
      _restoreDefaultAudioRoute();
      _remoteStream = null;
      _remoteRenderer.srcObject = null;
      if (!mounted) return;
      setState(() {});
    };

    // 连接到服务器
    await _signaling!.connect();
  }

  void _callCamera() {
    if (!mounted) return;
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
        final l = AppLocalizations.of(context);
        LogUtils.w('MonitorViewer', 'Camera ${widget.cameraDeviceId} not found in peers list');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.monitorViewerCameraOffline
                  .replaceFirst('{name}', widget.cameraName),
            ),
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
    if (!mounted) return;
    setState(() {
      _cameraMicEnabled = nextEnabled;
    });
  }

  Future<void> _toggleMonitorTalkback() async {
    final session = _session;
    final signaling = _signaling;
    if (session == null || signaling == null) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cameraEndpointConnecting)),
      );
      return;
    }
    final wantOn = !_monitorTalkbackOn;
    if (wantOn) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.monitorViewerMicPermissionRequired)),
        );
        return;
      }
    }
    try {
      // iOS: PlayAndRecord 须在 getUserMedia 之前就绪（与页面常驻的 localAndRemote 一致）。
      if (wantOn && Platform.isIOS) {
        setState(() => _monitorTalkbackOn = true);
        await _applyIosMonitorAudioMode();
      }
      await signaling.setMonitorTalkbackEnabled(session, wantOn);
      if (!mounted) return;
      if (wantOn && !Platform.isIOS) {
        setState(() => _monitorTalkbackOn = true);
      } else if (!wantOn) {
        setState(() => _monitorTalkbackOn = false);
      }
    } catch (e) {
      if (wantOn && Platform.isIOS) {
        setState(() => _monitorTalkbackOn = false);
        await _applyIosMonitorAudioMode();
      }
      LogUtils.e('MonitorViewer', 'Talkback failed', e);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.monitorViewerTalkbackFailed}$e')),
      );
    }
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

      if (!mounted) return;
      setState(() {
        _mediaRecorder = recorder;
        _recordingPath = path;
      });
    } catch (e) {
      try {
        await _mediaRecorder?.stop();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _mediaRecorder = null;
          _recordingPath = null;
        });
      } else {
        _mediaRecorder = null;
        _recordingPath = null;
      }
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.monitorViewerRecordStartFailed}$e')),
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
    } catch (e) {
      LogUtils.e('MonitorViewer', 'Stop recording failed', e);
    }

    if (!mounted) {
      _mediaRecorder = null;
      _recordingPath = null;
      return;
    }

    setState(() {
      _mediaRecorder = null;
      _recordingPath = null;
    });

    if (!mounted) return;

    // Auto save to gallery when user explicitly stopped recording.
    if (showToast && savedPath != null) {
      final file = File(savedPath);
      if (!await file.exists() || await file.length() == 0) {
        LogUtils.e('MonitorViewer', 'Recording failed: File is empty or does not exist');
        if (mounted) {
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.playbackRecordingNotSupported)),
          );
        }
        return;
      }
      await _saveVideoToGallery(savedPath);
      // Optional: Cleanup temp file after saving? 
      // GallerySaver usually copies the file. We can delete the original if needed.
      // await file.delete(); 
    }
  }

  Future<void> _saveVideoToGallery(String path) async {
    if (_isSavingToGallery) return;
    if (!mounted) return;
    setState(() {
      _isSavingToGallery = true;
    });

    try {
      bool ok = false;
      if (Platform.isIOS) {
        ok = await GallerySaver.saveVideo(
              path,
              albumName: 'RePhone Security',
            ) ==
            true;
        if (!ok) {
          final addOnly = await Permission.photosAddOnly.request();
          if (!(addOnly.isGranted || addOnly.isLimited)) {
            final photos = await Permission.photos.request();
            if (!(photos.isGranted || photos.isLimited)) {
              if (mounted) {
                final l = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.playbackPhotosPermissionIosHint)),
                );
              }
              return;
            }
          }
          ok = await GallerySaver.saveVideo(
                path,
                albumName: 'RePhone Security',
              ) ==
              true;
        }
      } else {
        final permissionOk = await _requestGalleryPermissionIfNeeded();
        if (!permissionOk) {
          if (mounted) {
            final l = AppLocalizations.of(context);
            final message = Platform.isIOS
                ? l.playbackPhotosPermissionIosHint
                : l.playbackPhotosPermissionAndroidHint;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
          return;
        }
        ok = await GallerySaver.saveVideo(
              path,
              albumName: 'RePhone Security',
            ) ==
            true;
      }

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
        // 截图失败或解码异常不影响返回，最多等 1 秒
        try {
          await _captureSnapshot().timeout(const Duration(seconds: 1));
        } catch (_) {
          // ignore errors / timeout
        }
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.cameraName),
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
                              child: Text(
                                l.monitorViewerRecLabel,
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
                                ? l.monitorViewerWaiting
                                : l.playbackConnecting,
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
          if (_inCall)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlBtn(
                    context,
                    icon: _cameraMicEnabled ? Icons.volume_up : Icons.volume_off,
                    label: _cameraMicEnabled
                        ? l.cameraEndpointLogMicOn
                        : l.cameraEndpointLogMicOff,
                    onTap: _toggleCameraMic,
                  ),
                  _buildControlBtn(
                    context,
                    icon: _monitorTalkbackOn ? Icons.mic : Icons.mic_off,
                    label: _monitorTalkbackOn
                        ? l.monitorViewerTalkbackOn
                        : l.monitorViewerTalkbackOff,
                    onTap: _toggleMonitorTalkback,
                    iconColor:
                        _monitorTalkbackOn ? Colors.green : null,
                  ),
                  if (_remoteStream != null)
                    _buildControlBtn(
                      context,
                      icon: _isRecording
                          ? Icons.stop_circle_outlined
                          : Icons.fiber_manual_record,
                      label: _isRecording
                          ? l.cameraEndpointRecordSaved
                          : l.cameraEndpointRecord10s,
                      onTap: _isRecording ? _stopRecording : _startRecording,
                      iconColor: _isRecording ? Colors.red : null,
                    ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildControlBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: iconColor ?? Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
