import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../utils/log_utils.dart';

const String _kIapTag = 'IAP';

class IapService {
  IapService._internal();

  static final IapService instance = IapService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  final Set<String> _productIds = {
    'rephone_premium_monthly',
    'rephone_premium_yearly',
    'rephone_pro', // New subscription model (Single Product + Base Plans)
  };

  final StreamController<List<PurchaseDetails>> _purchasesController =
      StreamController<List<PurchaseDetails>>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _available = false;
  bool _initialized = false;
  bool _isQueryingProducts = false;
  Future<void>? _queryProductsFuture;

  List<ProductDetails> products = [];

  bool get isAvailable => _available;

  Future<void> init({bool forceRefresh = false}) async {
    if (_initialized && !forceRefresh) {
      LogUtils.d(_kIapTag, 'init: already initialized, skip');
      return;
    }

    if (forceRefresh) {
      LogUtils.d(_kIapTag, 'init: force refreshing...');
    }

    // 尽早注册监听器，防止漏单（特别是 iOS）
    if (_subscription == null) {
      _subscription = _iap.purchaseStream.listen(
        (purchaseDetailsList) {
          LogUtils.d(_kIapTag, 'purchaseStream: ${purchaseDetailsList.length} update(s)');
          for (final p in purchaseDetailsList) {
            LogUtils.d(_kIapTag, '  productId=${p.productID} status=${p.status} pendingComplete=${p.pendingCompletePurchase}');
          }
          _purchasesController.add(purchaseDetailsList);
        },
        onDone: () {
          LogUtils.d(_kIapTag, 'purchaseStream: done');
          _subscription?.cancel();
          _subscription = null;
        },
        onError: (Object e, StackTrace? st) {
          LogUtils.e(_kIapTag, 'purchaseStream: error', e, st);
        },
      );
    }

    LogUtils.d(_kIapTag, 'init: checking IAP availability...');
    _available = await _iap.isAvailable();
    LogUtils.d(_kIapTag, 'init: isAvailable=$_available');

    if (!_available) {
      LogUtils.d(_kIapTag, 'init: IAP not available, abort');
      _initialized = true;
      return;
    }

    await _queryProducts(force: forceRefresh);

    _initialized = true;
    LogUtils.d(_kIapTag, 'init: done, products count=${products.length}');
  }

  Stream<List<PurchaseDetails>> get purchasesStream =>
      _purchasesController.stream;

  Future<void> _queryProducts({bool force = false}) async {
    // If a query is already running, await it so callers don't observe products=[].
    if (_isQueryingProducts) {
      LogUtils.d(_kIapTag, 'queryProducts: already in progress, await');
      await _queryProductsFuture;
      return;
    }

    // If we already have products and not forcing refresh, keep them.
    if (!force && products.isNotEmpty) {
      LogUtils.d(_kIapTag, 'queryProducts: cached products=${products.length}, skip');
      return;
    }

    _isQueryingProducts = true;
    final completer = Completer<void>();
    _queryProductsFuture = completer.future;
    try {
      LogUtils.d(_kIapTag, 'queryProducts: requesting $_productIds');
      final response = await _iap.queryProductDetails(_productIds);
      if (response.error != null) {
        LogUtils.e(
          _kIapTag,
          'queryProducts: store error code=${response.error!.code} message=${response.error!.message}',
        );
      }
      products = response.productDetails.toList();

      if (response.notFoundIDs.isNotEmpty) {
        LogUtils.d(_kIapTag, 'queryProducts: notFoundIDs=${response.notFoundIDs}');
      }
      if (products.isEmpty) {
        LogUtils.d(_kIapTag, 'queryProducts: no products (check Play Console / product IDs)');
      } else {
        for (final p in products) {
          LogUtils.d(_kIapTag, 'queryProducts: id=${p.id} price=${p.price} title=${p.title}');
        }
      }
    } catch (e, st) {
      LogUtils.e(_kIapTag, 'queryProducts: error', e, st);
    } finally {
      _isQueryingProducts = false;
      completer.complete();
    }
  }

  ProductDetails? getProduct(String id) {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> buy(ProductDetails product, {String? offerToken}) async {
    LogUtils.d(_kIapTag, 'buy: productId=${product.id} price=${product.price} offerToken=$offerToken');
    late PurchaseParam param;
    
    if (Platform.isAndroid) {
      // Android new model: base plans live under `rephone_pro`.
      // For plan switching we must pass the correct `oldPurchaseDetails` to
      // `ChangeSubscriptionParam`, otherwise Google Play may return
      // responseCode=5 (DEVELOPER_ERROR).
      if (product is GooglePlayProductDetails && product.id == 'rephone_pro') {
        GooglePlayPurchaseDetails? oldSub;
        var bestPurchaseTime = -1;
        try {
          final addition =
              _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
          final past = await addition.queryPastPurchases();
          for (final p in past.pastPurchases) {
            if (p.productID != 'rephone_pro') continue;
            if (p is! GooglePlayPurchaseDetails) continue;

            // Prefer auto-renewing + newest purchaseTime.
            final purchaseTime = p.billingClientPurchase.purchaseTime;
            final isAuto = p.billingClientPurchase.isAutoRenewing;
            final isBetter =
                (isAuto && oldSub == null) ||
                (isAuto && oldSub != null && !oldSub.billingClientPurchase.isAutoRenewing) ||
                (purchaseTime > bestPurchaseTime);

            if (isBetter) {
              oldSub = p;
              bestPurchaseTime = purchaseTime;
            }
          }
        } catch (e, st) {
          LogUtils.e(_kIapTag, 'buy: queryPastPurchases failed', e, st);
        }

        if (oldSub != null) {
          LogUtils.d(
            _kIapTag,
            'buy: oldSub selected purchaseTime=${oldSub.billingClientPurchase.purchaseTime} '
            'autoRenew=${oldSub.billingClientPurchase.isAutoRenewing} '
            'purchaseID=${oldSub.purchaseID}',
          );
        } else {
          LogUtils.d(_kIapTag, 'buy: oldSub not found, will buy without changeSubscriptionParam');
        }

        param = GooglePlayPurchaseParam(
          productDetails: product,
          changeSubscriptionParam: oldSub == null
              ? null
              : ChangeSubscriptionParam(
                  oldPurchaseDetails: oldSub,
                  replacementMode: ReplacementMode.withTimeProration,
                ),
          offerToken: offerToken,
        );
      } else {
        param = PurchaseParam(productDetails: product);
      }
    } else {
       // iOS: 默认参数即可
       param = PurchaseParam(productDetails: product);
    }

    try {
      await _iap.buyNonConsumable(purchaseParam: param);
      LogUtils.d(_kIapTag, 'buy: buyNonConsumable called');
    } on PlatformException catch (e, st) {
      // 处理 iOS 上的重复下单错误，触发一次恢复来让 pending 订单回调并被 complete
      if (Platform.isIOS && e.code == 'storekit_duplicate_product_object') {
        LogUtils.w(_kIapTag, 'buy: duplicate product, trying restorePurchases()');
        LogUtils.e(_kIapTag, 'buy: duplicate product details', e, st);
        try {
          await _iap.restorePurchases();
        } catch (inner, innerSt) {
          LogUtils.e(_kIapTag, 'buy: restorePurchases failed after duplicate', inner, innerSt);
        }
        // 吞掉该异常，交由上层 UI 通过 purchaseStream 提示用户
        return;
      }
      LogUtils.e(_kIapTag, 'buy: PlatformException', e, st);
      rethrow;
    } catch (e, st) {
      LogUtils.e(_kIapTag, 'buy: unexpected error', e, st);
      rethrow;
    }
  }

  /// iOS 专用：显示兑换码输入框
  Future<void> presentCodeRedemptionSheet() async {
    if (Platform.isIOS) {
      try {
        // 新版 in_app_purchase_storekit API：直接实例化 SKPaymentQueueWrapper
        await SKPaymentQueueWrapper().presentCodeRedemptionSheet();
      } catch (e) {
        LogUtils.e(_kIapTag, 'presentCodeRedemptionSheet error', e);
      }
    }
  }

  Future<void> restore() async {
    LogUtils.d(_kIapTag, 'restore: calling restorePurchases');
    await _iap.restorePurchases();
    LogUtils.d(_kIapTag, 'restore: done');
  }

  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      LogUtils.d(_kIapTag, 'completePurchase: productId=${purchase.productID}');
      await _iap.completePurchase(purchase);
      LogUtils.d(_kIapTag, 'completePurchase: done');
    } else {
      LogUtils.d(_kIapTag, 'completePurchase: skip (not pendingComplete) productId=${purchase.productID}');
    }
  }

  Future<void> dispose() async {
    LogUtils.d(_kIapTag, 'dispose');
    await _subscription?.cancel();
    await _purchasesController.close();
  }
}
