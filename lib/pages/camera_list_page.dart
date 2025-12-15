import 'package:flutter/material.dart';
import 'monitor_viewer_page.dart';

class CameraListPage extends StatefulWidget {
  const CameraListPage({super.key});

  @override
  State<CameraListPage> createState() => _CameraListPageState();
}

class _CameraListPageState extends State<CameraListPage> {
  final List<CameraDevice> _cameras = [
    CameraDevice(
      id: '1',
      name: '客厅摄像头',
      location: '客厅',
      isOnline: true,
      lastSeen: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    CameraDevice(
      id: '2',
      name: '卧室摄像头',
      location: '主卧室',
      isOnline: true,
      lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    CameraDevice(
      id: '3',
      name: '门口摄像头',
      location: '大门入口',
      isOnline: false,
      lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _cameras.isEmpty
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加摄像头'),
        content: const Text('扫描设备二维码或输入设备ID'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 实现添加摄像头逻辑
            },
            child: const Text('扫描二维码'),
          ),
        ],
      ),
    );
  }

  void _viewCamera(CameraDevice camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonitorViewerPage(cameraName: camera.name),
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
            onPressed: () {
              setState(() {
                _cameras.remove(camera);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除 ${camera.name}')),
              );
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

  CameraDevice({
    required this.id,
    required this.name,
    required this.location,
    required this.isOnline,
    required this.lastSeen,
  });
}
