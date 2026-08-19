import 'package:flutter/material.dart';

import 'iap_models.dart';

/// 横幅广告位标识（placement）：语义化的页面/场景名称。
///
/// - 海外 [GlobalAdMobService] 内部会把 placement 映射为具体的 AdMob Ad Unit ID
///   （Android/iOS、debug/release 各一条）
/// - 国内 [ChinaPangleAdService] 内部把 placement 映射为 Pangle 穿山甲的 codeId
/// - 业务页面只需要传入本文件定义的常量即可，无需感知 SDK 位 ID。
///
/// 说明：用 String 常量而不是 enum，方便后续新增 placement 时不强制升级抽象层；
/// 推荐值都是 `'profile'` / `'camera_list'` / `'camera_endpoint'` 这种页面名。
class AdPlacement {
  AdPlacement._();

  /// 个人中心页（ProfilePage）底部横幅。
  static const String profile = 'profile';

  /// 摄像头列表页（CameraListPage）底部横幅。
  static const String cameraList = 'camera_list';

  /// 摄像头详情/观看页（CameraEndpointPage）底部横幅。
  static const String cameraEndpoint = 'camera_endpoint';
}

/// 崩溃能力门面：用于记录 Dart / 异步异常。
///
/// 海外实现一般对接 Firebase Crashlytics；
/// 国内实现可以对接 Bugly 或先使用空实现占位。
abstract class CrashService {
  /// 启动阶段设置未捕获 Flutter 异常处理。
  Future<void> setupFlutterErrorHandlers();

  /// 记录 Dart 层致命异常（一般对应 Crashlytics recordFlutterFatalError）。
  Future<void> recordFlutterFatalError(FlutterErrorDetails details);

  /// 记录 Dart 层非致命异步异常（一般传给 Isolate 或 Zone 的 onError）。
  Future<void> recordError(Object error, StackTrace stack);
}

/// 推送能力门面：负责初始化、Token 监听、权限请求与上报。
///
/// 海外实现一般对接 FCM；国内实现可对接 HMS、小米、OPPO、vivo 等推送，
/// 或先用空实现占位。
abstract class PushService {
  /// 初始化推送通道：例如 FCM 背景 handler、iOS APNs 配置、国内 push SDK init。
  Future<void> init();

  /// 向服务端上报一次当前已登录的监控端用户推送 token（如果有）。
  Future<void> reportTokenForLoggedInMonitor({String? forceToken});

  /// 请求运行时通知权限（Android 13+ / iOS 需主动调用）。
  Future<bool> requestNotificationPermission();

  /// 当用户登录后且角色切到 monitor（有摄像头权限与前台服务）时再启用推送能力，
  /// 例如注册 FCM token 监听，避免游客态触发。
  Future<void> registerMonitorPushIfNeeded();
}

/// 内购能力门面：商品拉取、购买、恢复、订阅状态刷新。
///
/// 海外实现一般对接 `in_app_purchase`（Play Billing / StoreKit）；
/// 国内实现可对接微信/支付宝/RMB 支付，或先使用空实现占位。
///
/// 隔离约定：本门面**只暴露 [iap_models.dart] 中的 DTO 类型**
/// （[IapProduct] / [IapPurchase] / [IapPurchaseStatus] 等），
/// 业务代码不得 import `in_app_purchase` / `in_app_purchase_android` 等 SDK 包；
/// 具体 SDK 类型仅在 `features/iap_service_global.dart` 内部转换，
/// 从而在 Dart 层完成国内包 / 海外包的彻底隔离。
abstract class IapService {
  /// 初始化：例如监听购买流、建立与后端的订阅验证通道。
  ///
  /// [forceRefresh] 为 true 时强制重新拉取商品（用于会员页重试 / 反复进入）。
  Future<void> init({bool forceRefresh = false});

  /// 判断当前市场是否启用内购（主要用于 UI 展示）。
  bool get isEnabled;

  /// iOS 侧是否允许支付（例如家长控制关闭时为 false）。
  bool? get iosCanMakePayments;

  /// 商店商品列表（Play Billing / StoreKit 查询结果，已转为 DTO）。
  List<IapProduct> get products;

  /// 商店的购买状态流（purchased / restored / pending / error，已转为 DTO）。
  Stream<List<IapPurchase>> get purchasesStream;

  /// 加载商品（会员 SKU、新单 SKU 等）。
  Future<List<IapProduct>> loadProducts();

  /// 通过商品 ID 取已缓存的商店商品明细。
  IapProduct? getProduct(String id);

  /// 触发一次购买（由 UI 传入 SKU 标识）。
  Future<void> purchase(String sku);

  /// 按商品 DTO 直接发起购买（含 Android 升降级/ base plans）。
  Future<void> buy(
    IapProduct product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  });

  /// 恢复历史购买（iOS 需要在 UI 上提供入口）。
  Future<void> restorePurchases();

  /// 兼容 legacy：调用 `in_app_purchase` restorePurchases。
  Future<void> restore();

  /// 调用商店完成交易（Play / StoreKit 必须确认，否则会被自动退款）。
  Future<void> completePurchase(IapPurchase purchase);

  // —————————————————————————— 第三方支付（非商店 IAP，国内微信/支付宝等） ——————————————————————————

  /// 是否启用「服务端创建订单 → 客户端调 SDK → 异步回调确认」的第三方支付链路。
  ///
  /// - 海外 Google Play / App Store：返回 `false`，业务层走 [buy] / [purchasesStream] 老链路。
  /// - 国内微信/支付宝：返回 `true`，业务层必须调用 [createServerOrder] 发起购买，
  ///   不能使用 `purchase` / `buy`（会抛 UnsupportedError）。
  bool get isThirdPartyPaymentEnabled;

  /// 第三方支付：向服务端申请一笔订单（参数仅传 SKU + 套餐类型，**禁止客户端传金额**，防篡改）。
  ///
  /// 返回的 Map 中一般包含：
  /// ```
  /// {
  ///   'out_trade_no': '...',   // 内部订单号，用于后续 verify/query
  ///   'params': { ... },       // 调起第三方 SDK 所需参数（已由服务端签名）
  ///   'sdk_success': true,     // 仅部分实现会返回，调用方请勿依赖，仍需通过 [notifyServerOrderPaid] + [queryServerOrderStatus] 兜底确认
  /// }
  /// ```
  ///
  /// 内部约定：
  /// - 微信支付：`sku` 取值 `rephone_premium_monthly` / `rephone_premium_yearly`，
  ///   与服务端 `resolveWechatAmount` 一一对应；
  ///   `plan` 取值 `'monthly'` / `'yearly'`；
  ///   `email` 是已登录用户邮箱，用于绑定权益。
  Future<Map<String, dynamic>?> createServerOrder({
    required String sku,
    required String plan,
    required String email,
  });

  /// 第三方支付：SDK 回调返回「成功」后，立即调用服务端主动查单，加速权益发放。
  ///
  /// - 该调用**不可靠也不唯一**：SDK 回调可能丢包 / 用户切后台，因此仅作为「加速」；
  ///   业务必须再调用 [queryServerOrderStatus] 做最终一致性兜底。
  /// - `transactionId` 可选：如第三方 SDK 能拿到微信/支付宝的交易号可传，便于服务端去重。
  ///
  /// 返回 `true` 表示服务端已确认到账并发放权益（`paid=true` 或 `verified=true`）。
  Future<bool> notifyServerOrderPaid(
    String orderId, {
    String? email,
    String? transactionId,
  });

  /// 第三方支付：查询订单真实支付状态，作为「SDK 回调丢包 / notify 回调丢包」时的兜底。
  ///
  /// 实现约定：内部必须做「指数退避 + 超时上限」的重试（参考微信实现最多 ~30s / 8 次）；
  /// 返回 `true` 即代表服务端最终确认已支付。
  ///
  /// 典型场景：
  ///   - 用户成功支付但网络断开，SDK 没回调；
  ///   - 微信商户平台到了异步回调 5 分钟延迟上限还没推送到服务端；
  ///   - 客户端点击支付后立刻杀掉 App，但服务端 notify 已经成功写入 DB。
  Future<bool> queryServerOrderStatus(String orderId, {String? email});
}

/// 广告能力门面：Banner 广告加载与 Widget 输出。
///
/// 海外实现一般对接 Google Mobile Ads；
/// 国内实现一般对接 Pangle（穿山甲）或其他广告平台，
/// 也可以在空实现下直接返回空占位 Widget。
abstract class AdService {
  /// 广告 SDK 初始化（例如 MobileAds.instance.initialize）。
  Future<void> init();

  /// 是否允许展示横幅广告（VIP、无网络、无 SDK 等情况可返回 false）。
  bool get bannerEnabled;

  /// 返回一个可插入页面的横幅广告 Widget（例如 AdMob BannerAd / Pangle PlatformView）。
  ///
  /// - [placement]：语义化广告位标识，推荐使用 [AdPlacement] 中定义的常量
  ///   （`profile` / `camera_list` / `camera_endpoint`）。
  ///   实现层内部把 placement 映射为具体的 SDK 位 ID（Ad Unit / codeId）。
  Widget buildBanner(BuildContext context, {String placement});
}
