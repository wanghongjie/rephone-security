import 'package:flutter/material.dart';

import 'env_config.dart';
import 'iap_models.dart';
import 'service_facades.dart';

/// 通用的占位实现：Phase1 过渡阶段，能力门面先用占位实现注入，保证两条入口都能跑通；
/// Phase2 将提供 global 具体实现与 noop 实现，分别对应 main.dart / main_china.dart。
///
/// 说明：本文件中 Placeholder* 类仅用于历史兼容；新项目不再建议从入口注入本类。

/// 崩溃收集占位实现：Phase1 仅写日志；Phase2 Global 实现将接入 FirebaseCrashlytics。
class PlaceholderCrashService implements CrashService {
  @override
  Future<void> setupFlutterErrorHandlers() async {}

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    FlutterError.presentError(details);
  }

  @override
  Future<void> recordError(Object error, StackTrace stack) async {
    debugPrint('[PlaceholderCrashService] recordError: $error\n$stack');
  }
}

/// 推送占位实现：Phase1 仅写日志；Phase2 Global 实现将复用现有 PushService 逻辑。
class PlaceholderPushService implements PushService {
  @override
  Future<void> init() async {}

  @override
  Future<void> reportTokenForLoggedInMonitor({String? forceToken}) async {
    debugPrint('[PlaceholderPushService] reportTokenForLoggedInMonitor (no-op)');
  }

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> registerMonitorPushIfNeeded() async {
    debugPrint('[PlaceholderPushService] registerMonitorPushIfNeeded (no-op)');
  }
}

/// 内购占位实现：Phase1 仅返回空/占位；Phase2 Global 实现将复用现有 IapService 逻辑。
class PlaceholderIapService implements IapService {
  final FeatureToggles _features;

  PlaceholderIapService(this._features);

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  bool get isEnabled => _features.enableInAppPurchase;

  @override
  bool? get iosCanMakePayments => null;

  @override
  List<IapProduct> get products => const <IapProduct>[];

  @override
  Stream<List<IapPurchase>> get purchasesStream =>
      const Stream<List<IapPurchase>>.empty();

  @override
  Future<List<IapProduct>> loadProducts() async => const <IapProduct>[];

  @override
  IapProduct? getProduct(String id) => null;

  @override
  Future<void> purchase(String sku) async {
    debugPrint('[PlaceholderIapService] purchase(sku=$sku) 未实现（Phase1 占位）');
  }

  @override
  Future<void> buy(
    IapProduct product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  }) async {
    debugPrint('[PlaceholderIapService] buy 未实现（Phase1 占位）');
  }

  @override
  Future<void> restorePurchases() async {
    debugPrint('[PlaceholderIapService] restorePurchases 未实现（Phase1 占位）');
  }

  @override
  Future<void> restore() async {
    debugPrint('[PlaceholderIapService] restore 未实现（Phase1 占位）');
  }

  @override
  Future<void> completePurchase(IapPurchase purchase) async {}

  @override
  bool get isThirdPartyPaymentEnabled => false;

  @override
  Future<Map<String, dynamic>?> createServerOrder({
    required String sku,
    required String plan,
    required String email,
  }) async {
    debugPrint('[PlaceholderIapService] createServerOrder($sku, $plan) 未实现（Phase1 占位）');
    return null;
  }

  @override
  Future<bool> queryServerOrderStatus(String orderId, {String? email}) async {
    debugPrint('[PlaceholderIapService] queryServerOrderStatus($orderId) 未实现（Phase1 占位）');
    return false;
  }

  @override
  Future<bool> notifyServerOrderPaid(String orderId, {String? email, String? transactionId}) async {
    debugPrint('[PlaceholderIapService] notifyServerOrderPaid($orderId) 未实现（Phase1 占位）');
    return false;
  }
}

/// 广告占位实现：Phase1 返回空 SizedBox；Phase2 将提供 AdMob / Pangle 具体实现。
class PlaceholderAdService implements AdService {
  final FeatureToggles _features;

  PlaceholderAdService(this._features);

  @override
  Future<void> init() async {}

  @override
  bool get bannerEnabled =>
      _features.enableGoogleMobileAds || _features.enablePangleAds;

  @override
  Widget buildBanner(BuildContext context, {String? placement}) {
    if (!bannerEnabled) return const SizedBox.shrink();
    return const SizedBox.shrink();
  }
}
