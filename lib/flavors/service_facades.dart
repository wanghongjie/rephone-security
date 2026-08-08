import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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
/// 注：该抽象类型仍暴露 `PurchaseDetails` / `ProductDetails`，
/// 保证 legacy MembershipPage 的完整购买流程不回退；
/// 后续若要替换为非 Store/非 Billing 支付，可再升级为 DTO 类型。
abstract class IapService {
  /// 初始化：例如监听购买流、建立与后端的订阅验证通道。
  Future<void> init();

  /// 判断当前市场是否启用内购（主要用于 UI 展示）。
  bool get isEnabled;

  /// iOS 侧是否允许支付（例如家长控制关闭时为 false）。
  bool? get iosCanMakePayments;

  /// 原始的商店商品列表（Play Billing / StoreKit 查询结果）。
  List<ProductDetails> get products;

  /// 商店的购买状态流（purchased / restored / pending / error）。
  Stream<List<PurchaseDetails>> get purchasesStream;

  /// 加载商品（会员 SKU、新单 SKU 等）。
  Future<List<Object>> loadProducts();

  /// 通过商品 ID 取已缓存的商店商品明细。
  ProductDetails? getProduct(String id);

  /// 触发一次购买（由 UI 传入 SKU 标识）。
  Future<void> purchase(String sku);

  /// 按 `in_app_purchase` 的 ProductDetails 直接发起购买（含 Android 升降级/ base plans）。
  Future<void> buy(
    ProductDetails product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  });

  /// 恢复历史购买（iOS 需要在 UI 上提供入口）。
  Future<void> restorePurchases();

  /// 兼容 legacy：调用 `in_app_purchase` restorePurchases。
  Future<void> restore();

  /// 调用商店完成交易（Play / StoreKit 必须确认，否则会被自动退款）。
  Future<void> completePurchase(PurchaseDetails purchase);
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
