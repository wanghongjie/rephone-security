import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../service_facades.dart';

/// 内购空实现：国内版本暂未接入微信/支付宝/RMB 支付时使用，仅占位不报错。
///
/// 由于 [IapService] 门面仍暴露 `PurchaseDetails / ProductDetails`（
/// 保证 legacy [MembershipPage] 的购买验证逻辑不回退），本实现需要
/// 引入 `in_app_purchase` 类型依赖；未来改 DTO 后可彻底去掉。
///
/// 注：本文件不 import `in_app_purchase_android` / `in_app_purchase_storekit`
/// 等平台插件，也不依赖 `services/iap_service.dart` 单例，可安全被国内入口引用。
class NoopIapService implements IapService {
  final bool _enabled;
  final StreamController<List<PurchaseDetails>> _purchases =
      StreamController<List<PurchaseDetails>>.broadcast();

  /// 构造。[enabled] 默认 false，UI 层通过 [isEnabled] 决定是否展示按钮。
  NoopIapService({bool enabled = false}) : _enabled = enabled;

  @override
  bool get isEnabled => _enabled;

  @override
  bool? get iosCanMakePayments => null;

  @override
  List<ProductDetails> get products => const <ProductDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchasesStream => _purchases.stream;

  @override
  Future<void> init() async {}

  @override
  Future<List<Object>> loadProducts() async => const <Object>[];

  @override
  ProductDetails? getProduct(String id) => null;

  @override
  Future<void> purchase(String sku) async {
    debugPrint(
        '[NoopIapService] purchase($sku)：国内入口暂未接入第三方支付实现。');
  }

  @override
  Future<void> buy(
    ProductDetails product, {
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
  Future<void> completePurchase(PurchaseDetails purchase) async {
    debugPrint(
        '[NoopIapService] completePurchase(${purchase.productID})：noop 实现，无商店回调。');
  }
}
