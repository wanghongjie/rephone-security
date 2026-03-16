import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../l10n/app_localizations.dart';
import '../services/iap_service.dart';
import '../services/payment_api.dart';
import '../services/session_manager.dart';
import '../utils/log_utils.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  bool _isCurrentlyMember = false;
  DateTime? _membershipExpiry;
  bool _loadingProducts = true;
  bool _isRestoring = false;
  String? _error;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  final IapService _iap = IapService.instance;

  /// 基础版(免费) + 月付 + 年付；年付推荐
  late List<MembershipPlan> _plans;
  String _selectedPremiumPlanId = 'yearly';

  @override
  void initState() {
    super.initState();
    _plans = _defaultPlans();
    _initIap();
    _listenPurchases();
    // 启动时检查一次
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final user = await SessionManager.getUser();
    if (user != null) {
      if (!mounted) return;
      setState(() {
        _isCurrentlyMember = user.vipLevel > 0;
        _membershipExpiry = user.expireAt;
      });

      // 触发服务端“按需校验”
      // 只需要发起一次请求，服务端会根据策略决定是否查 Google
      // 这里可以静默执行，不需要 loading 遮罩
      try {
        final result = await PaymentApi().refreshSubscription(email: user.email);
        if (result != null) {
          final vipLevel = result['vip_level'] as int? ?? 0;
          final expireAtStr = result['expire_at'] as String?;
          final newUser = user.copyWith(
            vipLevel: vipLevel,
            expireAt: expireAtStr != null ? DateTime.tryParse(expireAtStr) : null,
          );
          await SessionManager.saveUser(newUser);

          if (!mounted) return;
          setState(() {
            _isCurrentlyMember = vipLevel > 0;
            _membershipExpiry = newUser.expireAt;
          });
          
          LogUtils.d('MembershipPage', 'Status refreshed: vip=$vipLevel');
        }
      } catch (e) {
        debugPrint('Failed to refresh status: $e');
      }
    }
  }

  List<MembershipPlan> _defaultPlans() {
    return [
      MembershipPlan(
        id: 'basic',
        planType: MembershipPlanType.basic,
        price: null,
        isRecommended: false,
        isCurrentPlan: true,
        productId: null,
        displayPrice: null,
      ),
      MembershipPlan(
        id: 'monthly',
        planType: MembershipPlanType.monthly,
        price: null,
        isRecommended: false,
        isCurrentPlan: false,
        productId: 'rephone_premium_monthly',
        basePlanId: 'monthly', // New
        displayPrice: null,
      ),
      MembershipPlan(
        id: 'yearly',
        planType: MembershipPlanType.yearly,
        price: null,
        isRecommended: true,
        isCurrentPlan: false,
        productId: 'rephone_premium_yearly',
        basePlanId: 'yearly', // New
        displayPrice: null,
      ),
    ];
  }

  Future<void> _initIap({bool force = false}) async {
    try {
      await _iap.init(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        for (var i = 0; i < _plans.length; i++) {
          final plan = _plans[i];
          
          // Strategy 2: New Android (Base Plans under 'rephone_pro')
          // Only apply on Android when basePlanId is present
          if (Platform.isAndroid && plan.basePlanId != null) {
            final parentProduct = _iap.getProduct('rephone_pro');
            if (parentProduct != null && parentProduct is GooglePlayProductDetails) {
              // New Google Play Billing (base plans). Use priceAmountMicros to avoid
              // localization / thousands-separator issues in formattedPrice.
              final detailsWrapper = parentProduct.productDetails;
              final offers = detailsWrapper.subscriptionOfferDetails ?? [];

              for (final offer in offers) {
                if (offer.basePlanId == plan.basePlanId &&
                    offer.pricingPhases.isNotEmpty) {
                  final phase = offer.pricingPhases.first;
                  final micros = phase.priceAmountMicros;
                  final raw = micros != null ? micros / 1000000.0 : null;
                  final formatted = phase.formattedPrice;

                  _plans[i] = plan.copyWith(
                    price: raw ?? _parsePriceFromDisplay(formatted),
                    displayPrice: formatted,
                    productId: 'rephone_pro',
                    offerToken: offer.offerIdToken,
                  );
                  // Found valid Android plan, skip legacy strategy
                  continue;
                }
              }

              // If we found a match and updated the plan, we should check if we need to continue or break
              // Since we are iterating plans, we just continue to next plan iteration?
              // No, we need to skip the legacy strategy below for THIS plan if we found a match.
              // Let's check if productId changed to 'rephone_pro'
              if (_plans[i].productId == 'rephone_pro') {
                continue;
              }
            }
          }

          // Strategy 1: Legacy/iOS (Single Product per Plan)
          // Fallback for Android if Strategy 2 failed, or default for iOS
          if (plan.productId != null) {
            final product = _iap.getProduct(plan.productId!);
            if (product != null) {
              final numPrice = (product is ProductDetails)
                  ? (product.rawPrice)
                  : _parsePriceFromDisplay(product.price);
              _plans[i] = plan.copyWith(
                price: numPrice ?? _parsePriceFromDisplay(product.price),
                displayPrice: product.price,
              );
              continue;
            }
          }
        }
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _error = 'failed';
      });
      debugPrint('[MembershipPage] _initIap error: $e $st');
    }
  }

  void _listenPurchases() {
    _purchaseSubscription = _iap.purchasesStream.listen((list) async {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      for (final purchase in list) {
        switch (purchase.status) {
          case PurchaseStatus.pending:
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context).membershipDialogProcessing)),
              );
            }
            break;
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.membershipPurchaseVerifying)),
              );
            }

            final user = await SessionManager.getUser();
            if (user == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.membershipPleaseLogin)),
                );
              }
              return;
            }

            Map<String, dynamic>? result;
            if (Platform.isIOS) {
              result = await PaymentApi().verifyApplePurchase(
                transactionId: purchase.purchaseID ?? '',
                productId: purchase.productID,
                receiptData: purchase.verificationData.serverVerificationData,
                email: user.email,
              );
            } else {
              result = await PaymentApi().verifyGooglePurchase(
                orderId: purchase.purchaseID ?? '',
                productId: purchase.productID,
                purchaseToken: purchase.verificationData.serverVerificationData,
                email: user.email,
              );
            }

            if (result != null) {
              if (result['subscription_expired'] == true) {
                await _iap.completePurchase(purchase);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.membershipSubscriptionExpired)),
                  );
                }
                if (mounted) _checkStatus();
                break;
              }
              await _iap.completePurchase(purchase);
              final vipLevel = result['vip_level'] as int? ?? 0;
              final expireAtStr = result['expire_at'] as String?;
              final newUser = user.copyWith(
                vipLevel: vipLevel,
                expireAt: expireAtStr != null ? DateTime.tryParse(expireAtStr) : null,
              );
              await SessionManager.saveUser(newUser);

              if (!mounted) return;
              setState(() {
                _isCurrentlyMember = vipLevel > 0;
                _membershipExpiry = newUser.expireAt;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${l.membershipStatusPremium} ✓')),
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.membershipPurchaseVerifyFailed)),
                );
              }
            }
            break;
          case PurchaseStatus.error:
            if (mounted) {
              final msg = purchase.error?.message ?? l.membershipPurchaseFailed;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            }
            break;
          case PurchaseStatus.canceled:
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMembershipStatus(),
            const SizedBox(height: 28),
            if (_loadingProducts)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              )
            else
              _buildPlansSection(),
            const SizedBox(height: 28),
            _buildFAQSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMembershipStatus() {
    final l = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isCurrentlyMember
              ? [Colors.purple, Colors.deepPurple]
              : [Colors.grey[400]!, Colors.grey[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isCurrentlyMember ? Icons.workspace_premium : Icons.person,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCurrentlyMember ? l.membershipStatusPremium : l.membershipStatusBasic,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isCurrentlyMember && _membershipExpiry != null)
                      Text(
                        '${l.membershipExpiryPrefix}${_formatDate(_membershipExpiry!)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isCurrentlyMember) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l.membershipUpgradeHint,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlansSection() {
    final l = AppLocalizations.of(context);

    final monthlyPlan = _plans.firstWhere((p) => p.planType == MembershipPlanType.monthly);
    final yearlyPlan = _plans.firstWhere((p) => p.planType == MembershipPlanType.yearly);

    final pricesMissing = !_loadingProducts &&
        (monthlyPlan.displayPrice == null || yearlyPlan.displayPrice == null);

    if (pricesMissing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Text(
              l.membershipLoadProductsFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loadingProducts = true;
                  _error = null;
                });
                _initIap(force: true);
              },
              icon: const Icon(Icons.refresh),
              label: Text(l.commonRetry),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.membershipSectionTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          l.membershipDialogUpgradeContent,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(height: 16),
        _buildCombinedPremiumCard(monthlyPlan, yearlyPlan),
      ],
    );
  }

  Widget _buildCombinedPremiumCard(MembershipPlan monthly, MembershipPlan yearly) {
    final l = AppLocalizations.of(context);
    final isYearlySelected = _selectedPremiumPlanId == yearly.id;
    final selectedPlan = isYearlySelected ? yearly : monthly;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.star, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l.membershipPlanPro,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ..._buildFeatureWidgets(yearly, l),
                const Divider(height: 32),
                _buildPlanOption(context, monthly, l),
                const SizedBox(height: 12),
                _buildPlanOption(context, yearly, l, discountLabel: _yearlyDiscountLabel(monthly, yearly, l)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _subscribeToPlan(selectedPlan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      '${l.membershipActionSubscribe} ${selectedPlan.displayPrice ?? ""}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _isRestoring ? null : _restorePurchases,
                    icon: _isRestoring
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore, size: 20),
                    label: Text(l.membershipRestore),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 根据月付/年付价格计算年付折扣文案：折扣后单价 + 省 XX%
  String? _yearlyDiscountLabel(MembershipPlan monthly, MembershipPlan yearly, AppLocalizations l) {
    final monthlyPrice = monthly.price;
    final yearlyPrice = yearly.price;
    if (monthlyPrice == null || yearlyPrice == null || monthlyPrice <= 0) return null;
    final equivalentPerMonth = yearlyPrice / 12;
    final savePercent = (1 - yearlyPrice / (monthlyPrice * 12)) * 100;
    if (savePercent <= 0) return null;
    final percentStr = savePercent >= 1 ? savePercent.round().toString() : savePercent.toStringAsFixed(0);
    final priceStr = equivalentPerMonth == equivalentPerMonth.roundToDouble()
        ? equivalentPerMonth.round().toString()
        : equivalentPerMonth.toStringAsFixed(2);

    // 尝试从月付/年付的 displayPrice 中提取货币前缀（如 "JP¥"、"$"）。
    String currencyPrefix = '';
    final displayForCurrency = monthly.displayPrice ?? yearly.displayPrice;
    if (displayForCurrency != null && displayForCurrency.isNotEmpty) {
      final firstDigitIndex = displayForCurrency.indexOf(RegExp(r'\d'));
      if (firstDigitIndex > 0) {
        currencyPrefix = displayForCurrency.substring(0, firstDigitIndex).trim();
      }
    }
    final priceWithCurrency =
        currencyPrefix.isNotEmpty ? '$currencyPrefix$priceStr' : priceStr;

    final pricePart =
        l.membershipPlanPricePerMonth.replaceAll('{price}', priceWithCurrency);
    final savePart = l.membershipYearlySavePercent.replaceAll('{percent}', percentStr);
    return '$pricePart · $savePart';
  }

  Widget _buildPlanOption(BuildContext context, MembershipPlan plan, AppLocalizations l, {String? discountLabel}) {
    final isSelected = _selectedPremiumPlanId == plan.id;
    final isYearly = plan.planType == MembershipPlanType.yearly;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPremiumPlanId = plan.id;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
              : null,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: plan.id,
              groupValue: _selectedPremiumPlanId,
              onChanged: (v) {
                if (v != null) setState(() => _selectedPremiumPlanId = v);
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isYearly ? l.membershipPlanYearly : l.membershipPlanMonthly,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isYearly && discountLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        discountLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (isYearly)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l.membershipBadgeRecommended,
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              plan.displayPrice ?? '--',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQSection() {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.membershipFaqTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: Text(l.membershipFaqCancelTitle),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.membershipFaqCancelContent,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text(l.membershipFaqEffectTitle),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.membershipFaqEffectContent,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showUpgradeDialog() {
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.membershipDialogUpgradeTitle),
        content: Text(l.membershipDialogUpgradeContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.membershipDialogLater),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(l.membershipButtonUpgrade),
          ),
        ],
      ),
    );
  }

  Future<void> _restorePurchases() async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);
    final l = AppLocalizations.of(context);
    try {
      await _iap.restore();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.membershipRestoreSuccess)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.membershipRestoreNoPurchases)),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  void _subscribeToPlan(MembershipPlan plan) {
    final l = AppLocalizations.of(context);
    final productId = plan.productId;
    final product = productId == null ? null : _iap.getProduct(productId);

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.membershipDialogSubscribeContent)),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.membershipDialogSubscribeTitle),
        content: Text(l.membershipDialogSubscribeContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${l.membershipDialogProcessing} ${product.title}')),
              );
              await _iap.buy(product, offerToken: plan.offerToken);
            },
            child: Text(l.commonConfirm),
          ),
        ],
      ),
    );
  }
}

enum MembershipPlanType { basic, monthly, yearly }

class MembershipPlan {
  final String id;
  final MembershipPlanType planType;
  final double? price;
  final bool isRecommended;
  final bool isCurrentPlan;
  final String? productId;
  final String? basePlanId; // New: for Google Play Billing 5+
  final String? offerToken; // New: for Google Play Billing 5+
  final String? displayPrice;

  MembershipPlan({
    required this.id,
    required this.planType,
    required this.price,
    required this.isRecommended,
    required this.isCurrentPlan,
    this.productId,
    this.basePlanId,
    this.offerToken,
    this.displayPrice,
  });

  bool get isFree => price == null || price == 0;

  MembershipPlan copyWith({
    double? price,
    String? displayPrice,
    bool? isCurrentPlan,
    String? productId,
    String? offerToken,
  }) {
    return MembershipPlan(
      id: id,
      planType: planType,
      price: price ?? this.price,
      isRecommended: isRecommended,
      isCurrentPlan: isCurrentPlan ?? this.isCurrentPlan,
      productId: productId ?? this.productId,
      basePlanId: basePlanId,
      offerToken: offerToken ?? this.offerToken,
      displayPrice: displayPrice ?? this.displayPrice,
    );
  }
}

/// 从 IAP 价格字符串解析数值（去掉货币符号等）
double? _parsePriceFromDisplay(String? displayPrice) {
  if (displayPrice == null || displayPrice.isEmpty) return null;
  final cleaned = displayPrice.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
  return double.tryParse(cleaned);
}

List<Widget> _buildFeatureWidgets(MembershipPlan plan, AppLocalizations l) {
  final featureKeys = plan.planType == MembershipPlanType.basic
      ? [
          'membershipFeatureNoDeviceLimit',
          'membershipFeatureBasicCloudImages',
          'membershipFeatureLiveStreaming',
        ]
      : [
          'membershipFeatureNoDeviceLimit',
          'membershipFeatureProCloudPlayback',
          'membershipFeatureLiveStreaming',
          'membershipFeatureNoAds',
        ];

  return featureKeys
      .map(
        (key) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(l.tr(key))),
            ],
          ),
        ),
      )
      .toList();
}
