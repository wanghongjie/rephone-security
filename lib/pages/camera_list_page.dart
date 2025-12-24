import 'package:flutter/material.dart';
import 'dart:async';
import 'monitor_viewer_page.dart';
import '../services/bind_api.dart';
import '../services/session_manager.dart';
import 'qr_code_generator_page.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
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
            isOnline: false, // TODO: 从设备状态接口获取在线状态
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
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cameras.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cameras.length,
                  itemBuilder: (context, index) {
                    return _buildCameraCard(_cameras[index]);
                  },
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
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: camera.isOnline ? Colors.green : Colors.red,
          child: Icon(
            camera.isOnline ? Icons.videocam : Icons.videocam_off,
            color: Colors.white,
          ),
        ),
        title: Text(
          camera.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('位置: ${camera.location}'),
            const SizedBox(height: 2),
            Text(
              camera.isOnline
                  ? '在线 • ${_formatLastSeen(camera.lastSeen)}'
                  : '离线 • ${_formatLastSeen(camera.lastSeen)}',
              style: TextStyle(
                color: camera.isOnline ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Text('查看实时画面'),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: Text('设备设置'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除设备'),
            ),
          ],
          onSelected: (value) => _handleMenuAction(value, camera),
        ),
        onTap: () => _viewCamera(camera),
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

  void _viewCamera(CameraDevice camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonitorViewerPage(
          cameraName: camera.name,
          cameraDeviceId: camera.id,
        ),
      ),
    );
  }

  void _handleMenuAction(String action, CameraDevice camera) {
    switch (action) {
      case 'view':
        _viewCamera(camera);
        break;
      case 'settings':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${camera.name} 设置')),
        );
        break;
      case 'delete':
        _deleteCamera(camera);
        break;
    }
  }

  void _deleteCamera(CameraDevice camera) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设备'),
        content: Text('确定要删除 ${camera.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              // TODO: 调用删除绑定接口
              // await _bindApi.deleteBinding(camera.bindingId);
              
              setState(() {
                _cameras.remove(camera);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除 ${camera.name}')),
              );
              
              // 重新加载列表
              await _loadBindings(showLoading: false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class CameraDevice {
  final String id;
  final String name;
  final String location;
  final bool isOnline;
  final DateTime lastSeen;
  final int? bindingId; // 绑定关系ID

  CameraDevice({
    required this.id,
    required this.name,
    required this.location,
    required this.isOnline,
    required this.lastSeen,
    this.bindingId,
  });
}
