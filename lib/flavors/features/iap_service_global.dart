import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../../services/iap_service.dart' as legacy;
import '../service_facades.dart';

const String _kIapTag = 'IAP';

/// 海外版内购实现：直接复用现有 [legacy.IapService]（Play Billing + StoreKit）。
///
/// 业务层通过 [IapService] 门面调用；未来如替换自研 Billing/StoreKit 封装，
/// 只需新增另一实现、替换入口注入，不会影响页面。
///
/// 注：本文件只应被 `main.dart`（海外入口）import；
/// 国内入口 `main_china.dart` 不得引用本文件，从而不会带上 Play Billing / StoreKit
/// 的平台插件与 legacy [IapService] 单例。
class GlobalStoreIapService implements IapService {
  final legacy.IapService _delegate = legacy.IapService.instance;
  final bool _enabled;

  /// 构造：默认启用；可在国内/无 Store 环境显式传 false。
  GlobalStoreIapService({bool enabled = true}) : _enabled = enabled;

  @override
  bool get isEnabled => _enabled && _delegate.isAvailable;

  @override
  bool? get iosCanMakePayments => _delegate.iosCanMakePayments;

  @override
  List<ProductDetails> get products => _delegate.products;

  @override
  Stream<List<PurchaseDetails>> get purchasesStream =>
      _delegate.purchasesStream;

  @override
  Future<void> init() async {
    if (!_enabled) return;
    try {
      await _delegate.init();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[GlobalStoreIapService.init] failed: $e\n$st');
      }
      // 不抛错，避免入口启动阶段被卡住；IAP 页自行通过 products 判空。
    }
  }

  @override
  Future<List<Object>> loadProducts() async {
    if (!_enabled) return const <Object>[];
    await _delegate.init();
    return _delegate.products;
  }

  @override
  ProductDetails? getProduct(String id) => _delegate.getProduct(id);

  @override
  Future<void> purchase(String sku) async {
    if (!_enabled) {
      throw StateError(
        '[GlobalStoreIapService] purchase: IAP not enabled for this market.',
      );
    }
    final product = _delegate.getProduct(sku);
    if (product == null) {
      throw StateError('[GlobalStoreIapService] product not found: sku=$sku');
    }
    await buy(product);
  }

  @override
  Future<void> buy(
    ProductDetails product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  }) {
    return _delegate.buy(
      product,
      offerToken: offerToken,
      skipAndroidSubscriptionReplacement: skipAndroidSubscriptionReplacement,
    );
  }

  @override
  Future<void> restorePurchases() => restore();

  @override
  Future<void> restore() => _delegate.restore();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _delegate.completePurchase(purchase);
}
