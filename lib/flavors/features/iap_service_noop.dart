import 'dart:async';

import 'package:flutter/material.dart';

import '../iap_models.dart';
import '../service_facades.dart';

/// 内购空实现：国内版本暂未接入微信/支付宝/RMB 支付时使用，仅占位不报错。
///
/// 本实现只使用 [iap_models.dart] 的 DTO 类型，不 import
/// `in_app_purchase` / `in_app_purchase_android` / `in_app_purchase_storekit`
/// 等任何支付 SDK，可安全被国内入口引用，不会把商店 SDK 链接进国内包。
class NoopIapService implements IapService {
  final bool _enabled;
  final StreamController<List<IapPurchase>> _purchases =
      StreamController<List<IapPurchase>>.broadcast();

  /// 构造。[enabled] 默认 false，UI 层通过 [isEnabled] 决定是否展示按钮。
  NoopIapService({bool enabled = false}) : _enabled = enabled;

  @override
  bool get isEnabled => _enabled;

  @override
  bool? get iosCanMakePayments => null;

  @override
  List<IapProduct> get products => const <IapProduct>[];

  @override
  Stream<List<IapPurchase>> get purchasesStream => _purchases.stream;

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<List<IapProduct>> loadProducts() async => const <IapProduct>[];

  @override
  IapProduct? getProduct(String id) => null;

  @override
  Future<void> purchase(String sku) async {
    debugPrint(
        '[NoopIapService] purchase($sku)：国内入口暂未接入第三方支付实现。');
  }

  @override
  Future<void> buy(
    IapProduct product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  }) async {
    debugPrint(
        '[NoopIapService] buy(${product.id})：国内入口暂未接入第三方支付实现。');
  }

  @override
  Future<void> restorePurchases() async {
    debugPrint('[NoopIapService] restorePurchases：国内入口暂未接入，跳过。');
  }

  @override
  Future<void> restore() => restorePurchases();

  @override
  Future<void> completePurchase(IapPurchase purchase) async {
    debugPrint(
        '[NoopIapService] completePurchase(${purchase.productID})：noop 实现，无商店回调。');
  }

  @override
  bool get isThirdPartyPaymentEnabled => false;

  @override
  Future<Map<String, dynamic>?> createServerOrder({
    required String sku,
    required String plan,
    required String email,
  }) async {
    debugPrint('[NoopIapService] createServerOrder($sku, $plan)：国内入口暂未接入第三方支付实现。');
    return null;
  }

  @override
  Future<bool> queryServerOrderStatus(String orderId, {String? email}) async {
    debugPrint('[NoopIapService] queryServerOrderStatus($orderId)：noop 实现。');
    return false;
  }

  @override
  Future<bool> notifyServerOrderPaid(String orderId, {String? email, String? transactionId}) async {
    debugPrint('[NoopIapService] notifyServerOrderPaid($orderId)：noop 实现。');
    return false;
  }
}
