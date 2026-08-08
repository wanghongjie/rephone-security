import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

import '../service_facades.dart';

/// 海外版崩溃能力实现：直接基于 Firebase Crashlytics。
///
/// 该文件仅由 [main.dart]（海外入口）import，
/// 保证国内入口的编译单元里不直接出现 `firebase_crashlytics` 引用。
class GlobalFirebaseCrashService implements CrashService {
  final FirebaseCrashlytics _crash;

  /// 构造：默认使用单例 [FirebaseCrashlytics.instance]。
  GlobalFirebaseCrashService() : _crash = FirebaseCrashlytics.instance;

  @override
  Future<void> setupFlutterErrorHandlers() async {
    FlutterError.onError = _crash.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _crash.recordError(error, stack, fatal: true);
      return true;
    };
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) =>
      _crash.recordFlutterFatalError(details);

  @override
  Future<void> recordError(Object error, StackTrace stack) =>
      _crash.recordError(error, stack, fatal: false);
}
