import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../l10n/app_localizations.dart';
import '../services/iap_service.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  bool _isCurrentlyMember = false;
  DateTime? _membershipExpiry;
  bool _loadingProducts = true;
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
        displayPrice: null,
      ),
      MembershipPlan(
        id: 'yearly',
        planType: MembershipPlanType.yearly,
        price: null,
        isRecommended: true,
        isCurrentPlan: false,
        productId: 'rephone_premium_yearly',
        displayPrice: null,
      ),
    ];
  }

  Future<void> _initIap() async {
    try {
      await _iap.init();
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        for (var i = 0; i < _plans.length; i++) {
          final plan = _plans[i];
          if (plan.productId != null) {
            final product = _iap.getProduct(plan.productId!);
            if (product != null) {
              _plans[i] = plan.copyWith(displayPrice: product.price);
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
            await _iap.completePurchase(purchase);
            if (!mounted) return;
            setState(() {
              _isCurrentlyMember = true;
              // 若服务端有到期时间可在此更新 _membershipExpiry
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${AppLocalizations.of(context).membershipStatusPremium} ✓')),
              );
            }
            break;
          case PurchaseStatus.error:
            if (mounted) {
              final msg = purchase.error?.message ?? 'Purchase failed';
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
            ElevatedButton(
              onPressed: () {
                // 滚动到套餐区域或直接展开
                _showUpgradeDialog();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.grey[800],
              ),
              child: Text(l.membershipButtonUpgrade),
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
              l.membershipDialogSubscribeContent,
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
                _initIap();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
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
                _buildPlanOption(monthly, l),
                const SizedBox(height: 12),
                _buildPlanOption(yearly, l),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanOption(MembershipPlan plan, AppLocalizations l) {
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
              await _iap.buy(product);
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
  final String? displayPrice;

  MembershipPlan({
    required this.id,
    required this.planType,
    required this.price,
    required this.isRecommended,
    required this.isCurrentPlan,
    this.productId,
    this.displayPrice,
  });

  bool get isFree => price == null || price == 0;

  MembershipPlan copyWith({
    String? displayPrice,
    bool? isCurrentPlan,
  }) {
    return MembershipPlan(
      id: id,
      planType: planType,
      price: price,
      isRecommended: isRecommended,
      isCurrentPlan: isCurrentPlan ?? this.isCurrentPlan,
      productId: productId,
      displayPrice: displayPrice ?? this.displayPrice,
    );
  }
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
