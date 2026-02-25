import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../l10n/app_localizations.dart';
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
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;
  bool _isProcessing = false; // 绑定处理中

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;
    controller.scannedDataStream.listen(_onScan);
  }

  Future<void> _onScan(Barcode barcode) async {
    if (_isProcessing) return;

    final code = barcode.code;
    if (code == null) return;

    final monitorEmail = code.trim();

    if (!monitorEmail.contains('@') || !monitorEmail.contains('.')) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.qrScanInvalidFormat),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    await _controller?.pauseCamera();

    // 直接处理绑定，监控端邮箱和相机端邮箱是同一个
    await _processBinding(monitorEmail);
  }

  Future<void> _processBinding(String email) async {
    try {
      final l = AppLocalizations.of(context);
      // 获取当前设备ID（相机端）
      final deviceId = await DeviceInfo.getOrCreateDeviceId('camera');
      // 获取当前设备可读名称作为默认相机名称
      final deviceName = await DeviceInfo.getReadableDeviceName();
      
      // 调用绑定接口
      // 监控端邮箱和相机端邮箱是同一个（同一个用户登录）
      final bindApi = BindApi();
      final request = AddBindingRequest(
        monitorEmail: email, // 扫描到的邮箱（监控端）
        cameraEmail: email, // 相机端邮箱（与监控端相同）
        cameraDeviceId: deviceId,
        cameraName: deviceName,
        cameraLocation: l.cameraDefaultLocationLivingRoom,
      );

      await bindApi.addBinding(request);

      // 绑定成功，保存相机端邮箱和身份
      await SessionManager.saveCameraUser(email);
      
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.cameraListBindSuccess),
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
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.qrScanBindFailedPrefix}$e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isProcessing = false;
        });
        // 重新开始扫描
        await _controller?.resumeCamera();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.qrScanTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          QRView(
            key: _qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Colors.white,
              borderRadius: 8,
              borderLength: 24,
              borderWidth: 8,
              cutOutSize: 260,
            ),
            onPermissionSet: (ctrl, p) {
              if (!p && mounted) {
                final l = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l.qrScanInvalidFormat),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      l.qrScanProcessing,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
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
                  child: Text(
                    l.qrScanHint,
                    style: const TextStyle(
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
