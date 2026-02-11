import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform, File, Directory;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path_provider/path_provider.dart';
import 'monitor_viewer_page.dart';
import 'playback_page.dart';
import 'camera_settings_page.dart';
import '../services/bind_api.dart';
import '../services/session_manager.dart';
import 'qr_code_generator_page.dart';
import '../models/camera_device.dart';
import '../utils/log_utils.dart';

class CameraListPage extends StatefulWidget {
  const CameraListPage({super.key});

  @override
  State<CameraListPage> createState() => _CameraListPageState();
}

class _CameraListPageState extends State<CameraListPage> {
  final BindApi _bindApi = BindApi();
  List<CameraDevice> _cameras = [];
  Timer? _pollingTimer;
  bool _isLoading = true;
  String? _currentUserEmail;
  bool _isQRCodePageOpen = false; // 跟踪二维码页面是否打开

  // Banner ad
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  Directory? _docsDir;

  // Delete in-flight
  final Set<String> _deletingCameraIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadUserInfo();
    _initDocsDir();
  }

  Future<void> _initDocsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    if (mounted) {
      setState(() {
        _docsDir = dir;
      });
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    // NOTE:
    // - These are Google's official Banner TEST ad unit IDs.
    // - Replace with your own Banner ad unit IDs when ready.
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
          // Keep quiet in UI; log only.
          LogUtils.w('CameraListPage', 'BannerAd failed to load: code=${error.code}, message=${error.message}, domain=${error.domain}');
        },
      ),
    );

    ad.load();
  }

  void _loadUserInfo() async {
    final user = await SessionManager.getUser();
    setState(() {
      _currentUserEmail = user?.email;
    });
    if (_currentUserEmail != null) {
      // 进入页面时只获取一次，不开始轮询
      await _loadBindings(showLoading: true);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBindings({bool showLoading = false}) async {
    if (_currentUserEmail == null) return;

    try {
      if (showLoading) {
        setState(() {
          _isLoading = true;
        });
      }

      final bindings = await _bindApi.getBindings(_currentUserEmail!);
      
      setState(() {
        _cameras = bindings.map((binding) {
          return CameraDevice(
            id: binding.cameraDeviceId,
            name: binding.cameraName ?? '未命名设备',
            location: binding.cameraLocation ?? '未知位置',
            isOnline: binding.cameraOnline,
            lastSeen: binding.updatedAt,
            bindingId: binding.id,
          );
        }).toList();
        if (showLoading) {
          _isLoading = false;
        }
      });
    } catch (e) {
      if (showLoading) {
        setState(() {
          _isLoading = false;
        });
      }
      if (mounted && showLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载绑定列表失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startPolling() {
    // 每3秒轮询一次绑定关系
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final countBeforeLoad = _cameras.length;
      await _loadBindings(showLoading: false);
      
      // 检测到绑定成功（列表数量增加）
      if (mounted && _cameras.length > countBeforeLoad) {
        _stopPolling();
        
        // 如果二维码页面打开，关闭它
        if (_isQRCodePageOpen) {
          _isQRCodePageOpen = false;
          Navigator.pop(context);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设备绑定成功！'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _cameras.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  _buildEmptyState(),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _cameras.length,
                itemBuilder: (context, index) {
                  return _buildCameraCard(_cameras[index]);
                },
              );

    return Scaffold(
      body: Column(
        children: [
          if (_isBannerAdReady && _bannerAd != null)
            SafeArea(
              bottom: false,
              child: Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_currentUserEmail == null) return;
                await _loadBindings(showLoading: false);
              },
              child: content,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCamera,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
            '暂无摄像头设备',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮添加设备',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraCard(CameraDevice camera) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Top: Status, Name, Location
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: camera.isOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      // 左侧：名称和位置
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                camera.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (camera.location.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '(${camera.location})',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // 右侧：状态和时间
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            camera.isOnline ? '在线' : '离线',
                            style: TextStyle(
                              color: camera.isOnline ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatLastSeen(camera.lastSeen),
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Middle: Cover Image
          InkWell(
            onTap: () => _viewCamera(camera),
            child: Container(
              height: 200,
              width: double.infinity,
              color: Colors.grey[200],
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_docsDir != null)
                    Image.file(
                      File('${_docsDir!.path}/covers/cover_${camera.id}.jpg'),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/camera_placeholder.png',
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        );
                      },
                    )
                  else
                    Image.asset(
                      'assets/images/camera_placeholder.png',
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom: Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  onPressed: () {
                     Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PlaybackPage(camera: camera)),
                    );
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('回看'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraSettingsPage(camera: camera),
                      ),
                    );
                    if (mounted) {
                      _loadBindings(showLoading: false);
                    }
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('设置'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  void _addCamera() {
    if (_currentUserEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先登录'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 开始轮询绑定关系
    _startPolling();

    // 标记二维码页面已打开
    _isQRCodePageOpen = true;

    // 显示二维码生成页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRCodeGeneratorPage(email: _currentUserEmail!),
      ),
    ).then((_) {
      // 关闭二维码页面时停止轮询并重置标志
      _isQRCodePageOpen = false;
      _stopPolling();
    });
  }

  void _viewCamera(CameraDevice camera) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonitorViewerPage(
          cameraName: camera.name,
          cameraDeviceId: camera.id,
        ),
      ),
    );
    
    if (mounted && _docsDir != null) {
      final file = File('${_docsDir!.path}/covers/cover_${camera.id}.jpg');
      // 清除图片缓存以显示最新截图
      if (await file.exists()) {
        await FileImage(file).evict();
      }
      setState(() {});
    }
  }


}
