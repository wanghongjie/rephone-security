import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

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

  List<ProductDetails> products = [];

  bool get isAvailable => _available;

  Future<void> init() async {
    if (_initialized) {
      LogUtils.d(_kIapTag, 'init: already initialized, skip');
      return;
    }

    LogUtils.d(_kIapTag, 'init: checking IAP availability...');
    _available = await _iap.isAvailable();
    LogUtils.d(_kIapTag, 'init: isAvailable=$_available');

    if (!_available) {
      LogUtils.d(_kIapTag, 'init: IAP not available, abort');
      _initialized = true;
      return;
    }

    await _queryProducts();

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
      },
      onError: (Object e, StackTrace? st) {
        LogUtils.e(_kIapTag, 'purchaseStream: error', e, st);
      },
    );

    _initialized = true;
    LogUtils.d(_kIapTag, 'init: done, products count=${products.length}');
  }

  Stream<List<PurchaseDetails>> get purchasesStream =>
      _purchasesController.stream;

  Future<void> _queryProducts() async {
    LogUtils.d(_kIapTag, 'queryProducts: requesting $_productIds');
    final response = await _iap.queryProductDetails(_productIds);
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
    if (offerToken != null && product is GooglePlayProductDetails) {
      param = GooglePlayPurchaseParam(
        productDetails: product,
        changeSubscriptionParam: null,
        offerToken: offerToken,
      );
    } else {
      param = PurchaseParam(productDetails: product);
    }
    await _iap.buyNonConsumable(purchaseParam: param);
    LogUtils.d(_kIapTag, 'buy: buyNonConsumable called');
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
