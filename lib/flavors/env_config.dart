/// Flavor 环境配置：描述当前构建对应的市场、业务能力开关与基础配置。
///
/// 该结构中的字段由入口 [main.dart] 与 [main_china.dart] 决定，
/// 并通过 [AppEnv.inject] 注入到全局运行时。
///
/// 业务代码禁止直接读取 String.fromEnvironment('MARKET')，
/// 请统一通过 [AppEnv.config] 与 [AppEnv.features] 访问。
library;

/// 市场维度：global（海外） / china（国内）。
///
/// - [global]：保留 Firebase / Google Mobile Ads / Play Billing / StoreKit 等海外能力。
/// - [china]：剔除上述海外 SDK，能力走国内实现或空实现占位。
enum Market {
  /// 海外版本（Play Store / App Store 上架）。
  global,

  /// 国内版本（国内应用市场上架）。
  china,
}

/// 基础环境配置：应用名、后端域名、市场等不随能力变化的静态信息。
///
/// 新增环境字段建议优先放在这里；能力开关（是否启用某 SDK）放 [FeatureToggles]。
class EnvConfig {
  /// 当前市场（global / china）。
  final Market market;

  /// 面向用户展示的应用名称。
  final String appName;

  /// 认证/账号服务域名主机，例如 `rephone.top`。
  final String authHost;

  /// 认证/账号服务端口，例如 `8086`。
  final int authPort;

  /// 认证/账号服务是否使用 HTTPS。
  final bool authUseHttps;

  /// 构造环境配置。
  const EnvConfig({
    required this.market,
    required this.appName,
    required this.authHost,
    required this.authPort,
    required this.authUseHttps,
  });
}

/// 能力开关：描述当前版本启用哪些业务能力（广告、会员、推送、崩溃收集等）。
///
/// 所有开关应以「能力语义」命名，禁止出现 SDK 名称；
/// 例如 `enableInAppPurchase` 而非 `enableGoogleBilling`。
class FeatureToggles {
  /// 是否启用内购会员（海外 Play / App Store）。
  final bool enableInAppPurchase;

  /// 是否启用 Firebase 相关能力（FCM / Crashlytics / Analytics 等）。
  final bool enableFirebase;

  /// 是否启用 Google Mobile Ads 广告。
  final bool enableGoogleMobileAds;

  /// 是否启用国内 Pangle（穿山甲）广告。
  final bool enablePangleAds;

  /// 是否启用崩溃收集。
  final bool enableCrashReporting;

  /// 是否启用客户端推送初始化与 token 上报。
  final bool enableClientPush;

  /// 构造能力开关集合。
  const FeatureToggles({
    required this.enableInAppPurchase,
    required this.enableFirebase,
    required this.enableGoogleMobileAds,
    required this.enablePangleAds,
    required this.enableCrashReporting,
    required this.enableClientPush,
  });
}

/// 预置的 Global（海外）环境配置：Firebase / AdMob / IAP 默认打开。
EnvConfig globalEnvConfig() => const EnvConfig(
      market: Market.global,
      appName: 'RePhone Security',
      authHost: 'rephone.top',
      authPort: 8086,
      authUseHttps: true,
    );

/// 预置的 Global（海外）能力开关：默认启用海外 SDK 能力。
FeatureToggles globalFeatureToggles() => const FeatureToggles(
      enableInAppPurchase: true,
      enableFirebase: true,
      enableGoogleMobileAds: true,
      enablePangleAds: false,
      enableCrashReporting: true,
      enableClientPush: true,
    );

/// 预置的 China（国内）环境配置：默认剔除 Firebase/AdMob/IAP。
EnvConfig chinaEnvConfig() => const EnvConfig(
      market: Market.china,
      appName: 'RePhone Security CN',
      authHost: 'rephone.top',
      authPort: 8086,
      authUseHttps: true,
    );

/// 预置的 China（国内）能力开关：默认走 Pangle 或 noop。
FeatureToggles chinaFeatureToggles() => const FeatureToggles(
      enableInAppPurchase: false,
      enableFirebase: false,
      enableGoogleMobileAds: false,
      enablePangleAds: true,
      enableCrashReporting: true,
      enableClientPush: true,
    );
