import 'env_config.dart';
import 'service_facades.dart';

/// Flavor 注入点：业务代码统一通过 AppEnv 获取「配置 + 能力 + 开关」。
///
/// 设计原则：
/// - 入口文件（[main.dart] / [main_china.dart]）在 runApp 前调用 [AppEnv.inject] 一次。
/// - 业务代码禁止直接 import firebase_* / in_app_purchase* / google_mobile_ads，
///   统一使用 [crash] / [push] / [iap] / [ads] 门面。
/// - 若需要区分市场，优先读取 [features] 的能力语义字段，而不是判断 [config.market]。
///
/// 该类不承担具体实现，具体 SDK 调用位于 `lib/flavors/features/*_global.dart` 与
/// `lib/flavors/features/*_noop.dart` 等文件中（Phase2 引入）。
class AppEnv {
  AppEnv._();

  static late final EnvConfig _config;
  static late final FeatureToggles _features;
  static late final CrashService _crash;
  static late final PushService _push;
  static late final IapService _iap;
  static late final AdService _ads;
  static bool _injected = false;

  /// 基础环境配置（市场、App 名称、后端域名等）。
  static EnvConfig get config => _ensure(_config, 'config');

  /// 能力开关（会员/广告/崩溃/推送等语义字段）。
  static FeatureToggles get features => _ensure(_features, 'features');

  /// 崩溃能力门面。
  static CrashService get crash => _ensure(_crash, 'crash');

  /// 推送能力门面。
  static PushService get push => _ensure(_push, 'push');

  /// 内购能力门面。
  static IapService get iap => _ensure(_iap, 'iap');

  /// 广告能力门面。
  static AdService get ads => _ensure(_ads, 'ads');

  /// 是否已完成注入。
  static bool get injected => _injected;

  /// 入口文件唯一调用点：在 `runApp` 之前注入一次全局配置与能力实现。
  ///
  /// - [config]：基础环境配置（市场 / 域名 / App 名称等）
  /// - [features]：能力开关（语义化，不出现 SDK 名称）
  /// - [crash]：崩溃实现
  /// - [push]：推送实现
  /// - [iap]：内购实现
  /// - [ads]：广告实现
  static void inject({
    required EnvConfig config,
    required FeatureToggles features,
    required CrashService crash,
    required PushService push,
    required IapService iap,
    required AdService ads,
  }) {
    if (_injected) {
      throw StateError('[AppEnv] inject 只允许调用一次。请检查入口文件是否重复注入。');
    }
    _config = config;
    _features = features;
    _crash = crash;
    _push = push;
    _iap = iap;
    _ads = ads;
    _injected = true;
  }

  static T _ensure<T>(T value, String name) {
    if (!_injected) {
      throw StateError('[AppEnv] 尚未注入：请在 runApp 前调用 AppEnv.inject(...)。'
          ' 请检查入口文件 (main.dart / main_china.dart) 是否遗漏。');
    }
    return value;
  }
}
