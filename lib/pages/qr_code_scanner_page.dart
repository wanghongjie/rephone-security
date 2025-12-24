import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/bind_api.dart';
import '../services/session_manager.dart';
import '../utils/device_info.dart';
import 'camera_endpoint_page.dart';

class QRCodeScannerPage extends StatefulWidget {
  const QRCodeScannerPage({super.key});

  @override
  State<QRCodeScannerPage> createState() => _QRCodeScannerPageState();
}

class _QRCodeScannerPageState extends State<QRCodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    final monitorEmail = barcode.rawValue!.trim();
    
    // 简单的邮箱格式验证
    if (!monitorEmail.contains('@') || !monitorEmail.contains('.')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无效的二维码格式'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    // 停止扫描
    await _controller.stop();

    // 直接处理绑定，监控端邮箱和相机端邮箱是同一个
    await _processBinding(monitorEmail);
  }

  Future<void> _processBinding(String email) async {
    try {
      // 获取当前设备ID（相机端）
      final deviceId = await DeviceInfo.getOrCreateDeviceId('camera');
      
      // 调用绑定接口
      // 监控端邮箱和相机端邮箱是同一个（同一个用户登录）
      final bindApi = BindApi();
      final request = AddBindingRequest(
        monitorEmail: email, // 扫描到的邮箱（监控端）
        cameraEmail: email, // 相机端邮箱（与监控端相同）
        cameraDeviceId: deviceId,
        cameraName: '相机设备',
        cameraLocation: '未知位置',
      );

      await bindApi.addBinding(request);

      // 绑定成功，保存相机端邮箱和身份
      await SessionManager.saveCameraUser(email);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('绑定成功！'),
            backgroundColor: Colors.green,
          ),
        );
        
        // 跳转到相机端页面
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => CameraEndpointPage(
              onSwitchToMonitor: () {},
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('绑定失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isProcessing = false;
        });
        // 重新开始扫描
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '正在处理绑定...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isProcessing)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '将二维码对准扫描框',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

