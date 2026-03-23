import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/log_utils.dart';

/// 云台在**软件限位**上本次 move 已无法继续转动（固件根据角度是否变化判断；舵机无真实编码器）。
///
/// - [axis] `pan` | `tilt`
/// - [edge] `min` | `max`（pan: max=已到最左、min=已到最右；tilt: max=最上、min=最下，与固件一致）
class PtzLimitEvent {
  const PtzLimitEvent({required this.axis, required this.edge});

  final String axis;
  final String edge;
}

/// BLE 云台控制服务，连接 ESP32 并发送 PTZ 指令
class PtzService {
  static const String _kTag = 'PtzService';
  static const String _deviceName = 'RePhone-PTZ';
  static const String _serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _rxCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _txCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  final StreamController<PtzLimitEvent> _limitController =
      StreamController<PtzLimitEvent>.broadcast();
  bool _isConnecting = false;

  bool get isConnected => _device != null && _rxChar != null;

  /// 固件在到达软件限位时通过 BLE Notify 推送，可监听做 UI 提示或停止连点。
  Stream<PtzLimitEvent> get onLimitHit => _limitController.stream;

  /// Android 12+：BLUETOOTH_SCAN / CONNECT。Android 11 及以下：系统要求定位权限才能 BLE 扫描（FBP 会校验）。
  Future<bool> _ensureBlePermissions() async {
    if (!Platform.isAndroid) return true;
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk <= 30) {
      final loc = await Permission.locationWhenInUse.request();
      if (!loc.isGranted) {
        LogUtils.w(
          _kTag,
          'BLE scan on Android 11 and below needs Location permission (OS rule, not for GPS). Denied: $loc',
        );
        return false;
      }
      return true;
    }
    final scan = await Permission.bluetoothScan.request();
    final conn = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !conn.isGranted) {
      LogUtils.w(
        _kTag,
        'Bluetooth permission denied (scan=$scan, connect=$conn). Grant in Settings.',
      );
      return false;
    }
    return true;
  }

  /// FBP 刚 init 时 adapterState 可能短暂不准；Android 上可尝试系统打开蓝牙。
  Future<bool> _awaitAdapterOn() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    Future<BluetoothAdapterState> currentState() async {
      try {
        return await FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {
        return BluetoothAdapterState.unknown;
      }
    }

    for (var i = 0; i < 10; i++) {
      final s = await currentState();
      LogUtils.d(_kTag, 'adapterState poll $i: $s');
      if (s == BluetoothAdapterState.on) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    var s = await currentState();
    if (s == BluetoothAdapterState.on) return true;

    if (Platform.isAndroid &&
        (s == BluetoothAdapterState.off ||
            s == BluetoothAdapterState.turningOff)) {
      LogUtils.i(_kTag, 'Trying to enable Bluetooth (system dialog)...');
      try {
        await FlutterBluePlus.turnOn(timeout: 30);
      } catch (e) {
        LogUtils.w(_kTag, 'turnOn failed: $e');
      }
      try {
        await FlutterBluePlus.adapterState
            .firstWhere((x) => x == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 35));
        return true;
      } catch (_) {
        // fall through
      }
    }

    s = await currentState();
    if (s == BluetoothAdapterState.unauthorized) {
      LogUtils.w(
        _kTag,
        'Bluetooth unauthorized. Grant Bluetooth / Nearby devices in system settings.',
      );
      return false;
    }
    LogUtils.w(
      _kTag,
      'Bluetooth not ready (state=$s). Turn on Bluetooth in system settings.',
    );
    return false;
  }

  /// 扫描并连接云台设备
  Future<bool> connect() async {
    if (_isConnecting) return false;
    _isConnecting = true;
    try {
      if (isConnected) {
        LogUtils.i(_kTag, 'Already connected');
        return true;
      }

      if (!await _ensureBlePermissions()) {
        return false;
      }

      if (!await _awaitAdapterOn()) {
        return false;
      }

      LogUtils.i(_kTag, 'Scanning for $_deviceName...');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      BluetoothDevice? found;
      await for (final scanResult in FlutterBluePlus.scanResults) {
        for (final r in scanResult) {
          final name = r.device.advName ?? r.device.platformName ?? '';
          if (name == _deviceName || name.startsWith('RePhone')) {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
      }
      await FlutterBluePlus.stopScan();

      if (found == null) {
        LogUtils.w(_kTag, 'Device $_deviceName not found');
        return false;
      }

      LogUtils.i(_kTag, 'Connecting to ${found.platformName}...');
      await found.connect(timeout: const Duration(seconds: 15));

      final services = await found.discoverServices();
      BluetoothCharacteristic? rxChar;
      BluetoothCharacteristic? txChar;
      final svcUuid = _serviceUuid.toLowerCase().replaceAll('-', '');
      final rxUuid = _rxCharUuid.toLowerCase().replaceAll('-', '');
      final txUuid = _txCharUuid.toLowerCase().replaceAll('-', '');
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase().replaceAll('-', '') != svcUuid) {
          continue;
        }
        for (final char in svc.characteristics) {
          final cu = char.uuid.toString().toLowerCase().replaceAll('-', '');
          if (cu == rxUuid) rxChar = char;
          if (cu == txUuid) txChar = char;
        }
        break;
      }

      if (rxChar == null) {
        LogUtils.w(_kTag, 'PTZ characteristic not found');
        await found.disconnect();
        return false;
      }

      _device = found;
      _rxChar = rxChar;
      await _notifySub?.cancel();
      _notifySub = null;
      if (txChar != null) {
        try {
          await txChar.setNotifyValue(true);
          _notifySub = txChar.onValueReceived.listen(_onPtzNotify);
          LogUtils.d(_kTag, 'PTZ TX notify subscribed (limit events)');
        } catch (e) {
          LogUtils.w(_kTag, 'PTZ TX notify failed (old firmware?): $e');
        }
      } else {
        LogUtils.d(_kTag, 'No PTZ TX char — limit events unavailable');
      }

      await _connSub?.cancel();
      _connSub = found.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          LogUtils.i(_kTag, 'PTZ device disconnected');
          _notifySub?.cancel();
          _notifySub = null;
          _device = null;
          _rxChar = null;
        }
      });
      LogUtils.i(_kTag, 'PTZ connected');
      return true;
    } catch (e, st) {
      LogUtils.e(_kTag, 'Connect failed', e, st);
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  void _onPtzNotify(List<int> value) {
    if (value.isEmpty) return;
    try {
      final s = utf8.decode(value);
      final map = jsonDecode(s) as Map<String, dynamic>?;
      if (map == null) return;
      if (map['evt'] != 'limit') return;
      final axis = map['axis'] as String?;
      final edge = map['edge'] as String?;
      if (axis == null || edge == null) return;
      final ev = PtzLimitEvent(axis: axis, edge: edge);
      if (!_limitController.isClosed) {
        _limitController.add(ev);
      }
      LogUtils.d(_kTag, 'Limit hit: axis=$axis edge=$edge');
    } catch (e) {
      LogUtils.w(_kTag, 'PTZ notify parse error: $e');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    final dev = _device;
    _device = null;
    _rxChar = null;
    if (dev != null) {
      try {
        await dev.disconnect();
      } catch (e) {
        LogUtils.w(_kTag, 'Disconnect error: $e');
      }
    }
  }

  /// 发送移动指令
  Future<void> move(String direction, {int speed = 1}) async {
    if (!isConnected) return;
    final payload = jsonEncode({
      'cmd': 'move',
      'dir': direction,
      'speed': speed,
    });
    await _write(payload);
  }

  /// 停止
  Future<void> stop() async {
    if (!isConnected) return;
    await _write(jsonEncode({'cmd': 'stop'}));
  }

  Future<void> _write(String json) async {
    final char = _rxChar;
    if (char == null) return;
    try {
      final bytes = utf8.encode(json);
      await char.write(bytes, withoutResponse: true);
      LogUtils.d(_kTag, 'Sent: $json');
    } catch (e) {
      LogUtils.e(_kTag, 'Write failed: $e');
    }
  }

  /// 处理 DataChannel 收到的 PTZ 指令（从监控端转发）
  Future<void> handleCommand(String? cmd,
      {String? direction, int speed = 1}) async {
    if (cmd == null) return;
    if (cmd == 'stop') {
      await stop();
      return;
    }
    if (cmd == 'move' && direction != null) {
      await move(direction, speed: speed);
    }
  }
}
