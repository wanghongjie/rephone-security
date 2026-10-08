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

  /// 微信开放平台「移动应用」AppID（`wx` 开头）。
  ///
  /// 由构建参数 `--dart-define=WECHAT_APP_ID=wx...` 注入，避免硬编码进源码。
  /// 仅**国内版 Android** 需要；海外版与 iOS 均为空串。
  ///
  /// 注意：iOS 不区分国内/海外，统一走 Apple 内购（App Store），
  /// 因此 iOS 端不注册微信 SDK、也不需要 Universal Link。
  final String wechatAppId;

  /// 构造环境配置。
  const EnvConfig({
    required this.market,
    required this.appName,
    required this.authHost,
    required this.authPort,
    required this.authUseHttps,
    this.wechatAppId = '',
  });
}

/// 能力开关：描述当前版本启用哪些业务能力（广告、会员、推送、崩溃收集等）。
///
/// 所有开关应以「能力语义」命名，禁止出现 SDK 名称；
/// 例如 `enableInAppPurchase` 而非 `enableGoogleBilling`。
class FeatureToggles {
  /// 是否启用内购会员（海外 Play / App Store）。
  final bool enableInAppPurchase;

  /// 是否启用国内第三方支付（微信支付 / 支付宝等）。
  /// 国内版本为 true 时，`MembershipPage` 走「服务端创建订单」链路，
  /// 不调用 Play Billing / StoreKit。
  final bool enableWechatPay;

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
    required this.enableWechatPay,
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
      // 海外版不需要微信参数，且构建脚本会剔除 fluwx 依赖
      wechatAppId: '',
    );

/// 预置的 Global（海外）能力开关：默认启用海外 SDK 能力。
FeatureToggles globalFeatureToggles() => const FeatureToggles(
      enableInAppPurchase: true,
      enableWechatPay: false,
      enableFirebase: true,
      enableGoogleMobileAds: true,
      enablePangleAds: false,
      enableCrashReporting: true,
      enableClientPush: true,
    );

/// 预置的 China（国内）环境配置：默认剔除 Firebase/AdMob/IAP。
EnvConfig chinaEnvConfig() => const EnvConfig(
      market: Market.china,
      appName: 'RePhone Security',
      authHost: 'rephone.top',
      authPort: 8086,
      authUseHttps: true,
      // 由构建参数注入：--dart-define=WECHAT_APP_ID=wx...
      // String.fromEnvironment 是编译期常量，因此这里仍可保持 const。
      wechatAppId: String.fromEnvironment('WECHAT_APP_ID'),
    );

/// 预置的 China（国内）能力开关：默认走 Pangle + 微信支付。
///
/// 仅 Android 使用：iOS 不区分国内/海外，统一构建 global 入口走 Apple 内购，
/// 因此 iOS 永远不会读到这组开关。
FeatureToggles chinaFeatureToggles() => const FeatureToggles(
      enableInAppPurchase: false,
      // 国内 Android 会员：走服务端下单 + 微信 SDK 调起链路（ChinaWechatIapService）。
      // 打开后 MembershipPage 才会在 MainPage 中挂载。
      // 灰度/紧急下线时把它改回 false 即可隐藏会员入口，无需删代码。
      enableWechatPay: true,
      enableFirebase: false,
      enableGoogleMobileAds: false,
      enablePangleAds: true,
      enableCrashReporting: true,
      enableClientPush: true,
    );
