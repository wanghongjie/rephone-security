import 'package:flutter/material.dart';

import '../service_facades.dart';

/// 国内/通用的「崩溃能力空实现」：只把异常打印到 FlutterError / debugPrint，不上传。
///
/// 后续如需接入 Bugly / Sentry 等国内崩溃平台，可新建独立实现类，
/// 并在 [main_china.dart] 的 AppEnv.inject 替换此处注入。
class NoopCrashService implements CrashService {
  @override
  Future<void> setupFlutterErrorHandlers() async {}

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    FlutterError.presentError(details);
  }

  @override
  Future<void> recordError(Object error, StackTrace stack) async {
    debugPrint('[NoopCrashService] error=$error\n$stack');
  }
}
