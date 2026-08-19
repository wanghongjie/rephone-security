import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../../services/iap_service.dart' as legacy;
import '../iap_models.dart';
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
  List<IapProduct> get products =>
      _delegate.products.map(_toIapProduct).toList();

  @override
  Stream<List<IapPurchase>> get purchasesStream =>
      _delegate.purchasesStream
          .map((list) => list.map(_toIapPurchase).toList());

  @override
  Future<void> init({bool forceRefresh = false}) async {
    if (!_enabled) return;
    try {
      await _delegate.init(forceRefresh: forceRefresh);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[GlobalStoreIapService.init] failed: $e\n$st');
      }
      // 不抛错，避免入口启动阶段被卡住；IAP 页自行通过 products 判空。
    }
  }

  @override
  Future<List<IapProduct>> loadProducts() async {
    if (!_enabled) return const <IapProduct>[];
    await _delegate.init();
    return _delegate.products.map(_toIapProduct).toList();
  }

  @override
  IapProduct? getProduct(String id) {
    final d = _delegate.getProduct(id);
    return d == null ? null : _toIapProduct(d);
  }

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
    await buy(_toIapProduct(product));
  }

  @override
  Future<void> buy(
    IapProduct product, {
    String? offerToken,
    bool skipAndroidSubscriptionReplacement = false,
  }) {
    final native = product.nativeHandle;
    final details = native is ProductDetails ? native : _delegate.getProduct(product.id);
    if (details == null) {
      throw StateError(
        '[GlobalStoreIapService] buy: native ProductDetails not found for ${product.id}',
      );
    }
    return _delegate.buy(
      details,
      offerToken: offerToken,
      skipAndroidSubscriptionReplacement: skipAndroidSubscriptionReplacement,
    );
  }

  @override
  Future<void> restorePurchases() => restore();

  @override
  Future<void> restore() => _delegate.restore();

  @override
  Future<void> completePurchase(IapPurchase purchase) {
    final native = purchase.nativeHandle;
    if (native is! PurchaseDetails) {
      throw StateError(
        '[GlobalStoreIapService] completePurchase: native PurchaseDetails not found for ${purchase.productID}',
      );
    }
    return _delegate.completePurchase(native);
  }

  @override
  bool get isThirdPartyPaymentEnabled => false;

  @override
  Future<Map<String, dynamic>?> createServerOrder({
    required String sku,
    required String plan,
    required String email,
  }) async {
    // 海外版使用 Play Billing / StoreKit，不走服务端下单模式。
    return null;
  }

  @override
  Future<bool> queryServerOrderStatus(String orderId, {String? email}) async {
    // 海外版无此链路
    return false;
  }

  @override
  Future<bool> notifyServerOrderPaid(String orderId, {String? email, String? transactionId}) async {
    // 海外版无此链路
    return false;
  }
}

// ———————————————————————— SDK → DTO 转换（仅本文件内部使用） ————————————————————————

/// 将 SDK 的 [ProductDetails] 转为业务层 DTO [IapProduct]。
IapProduct _toIapProduct(ProductDetails d) {
  return IapProduct(
    id: d.id,
    title: d.title,
    description: d.description,
    price: d.price,
    rawPrice: d.rawPrice,
    currencyCode: d.currencyCode,
    subscriptionOffers: _toIapOffers(d),
    nativeHandle: d,
  );
}

/// 提取订阅 base plan / offer 信息（仅 Google Play 有，Apple 返回空列表）。
List<IapSubscriptionOffer> _toIapOffers(ProductDetails d) {
  final offers = d is GooglePlayProductDetails
      ? d.productDetails.subscriptionOfferDetails
      : null;
  if (offers == null) return const <IapSubscriptionOffer>[];
  return offers
      .map((o) => IapSubscriptionOffer(
            basePlanId: o.basePlanId,
            offerIdToken: o.offerIdToken,
            pricingPhases: o.pricingPhases
                .map((p) => IapPricingPhase(
                      priceAmountMicros: p.priceAmountMicros,
                      formattedPrice: p.formattedPrice,
                      billingPeriod: p.billingPeriod,
                      billingCycleCount: p.billingCycleCount,
                      priceCurrencyCode: p.priceCurrencyCode,
                    ))
                .toList(),
          ))
      .toList();
}

/// 将 SDK 的 [PurchaseDetails] 转为业务层 DTO [IapPurchase]。
IapPurchase _toIapPurchase(PurchaseDetails p) {
  return IapPurchase(
    productID: p.productID,
    purchaseID: p.purchaseID,
    status: _toIapStatus(p.status),
    transactionDate: p.transactionDate,
    pendingCompletePurchase: p.pendingCompletePurchase,
    error: p.error == null
        ? null
        : IapPurchaseError(
            code: p.error!.code,
            message: p.error!.message,
            details: p.error!.details,
          ),
    verificationData: IapVerificationData(
      source: p.verificationData.source.toString(),
      serverVerificationData: p.verificationData.serverVerificationData,
      localVerificationData: p.verificationData.localVerificationData,
    ),
    nativeHandle: p,
  );
}

/// 将 SDK 的 [PurchaseStatus] 转为业务层 [IapPurchaseStatus]。
IapPurchaseStatus _toIapStatus(PurchaseStatus s) {
  switch (s) {
    case PurchaseStatus.purchased:
      return IapPurchaseStatus.purchased;
    case PurchaseStatus.error:
      return IapPurchaseStatus.error;
    case PurchaseStatus.pending:
      return IapPurchaseStatus.pending;
    case PurchaseStatus.restored:
      return IapPurchaseStatus.restored;
    case PurchaseStatus.canceled:
      return IapPurchaseStatus.canceled;
  }
}
