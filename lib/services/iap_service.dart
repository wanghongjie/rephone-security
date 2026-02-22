import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class IapService {
  IapService._internal();

  static final IapService instance = IapService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  final Set<String> _productIds = {
    'rephone_premium_monthly',
    'rephone_premium_yearly',
  };

  final StreamController<List<PurchaseDetails>> _purchasesController =
      StreamController<List<PurchaseDetails>>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _available = false;
  bool _initialized = false;

  List<ProductDetails> products = [];

  bool get isAvailable => _available;

  Future<void> init() async {
    if (_initialized) return;

    _available = await _iap.isAvailable();
    if (!_available) {
      _initialized = true;
      return;
    }

    await _queryProducts();

    _subscription = _iap.purchaseStream.listen(
      (purchaseDetailsList) {
        _purchasesController.add(purchaseDetailsList);
      },
      onDone: () {
        _subscription?.cancel();
      },
      onError: (_) {},
    );

    _initialized = true;
  }

  Stream<List<PurchaseDetails>> get purchasesStream =>
      _purchasesController.stream;

  Future<void> _queryProducts() async {
    final response = await _iap.queryProductDetails(_productIds);
    products = response.productDetails.toList();
  }

  ProductDetails? getProduct(String id) {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _purchasesController.close();
  }
}
