import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/iap_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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

  final IapService _iap = IapService.instance;

  final List<MembershipPlan> _plans = [
    MembershipPlan(
      id: 'basic',
      price: null,
      isRecommended: false,
      isCurrentPlan: true,
      productId: null,
      displayPrice: null,
    ),
    MembershipPlan(
      id: 'pro',
      price: 19.9,
      isRecommended: true,
      isCurrentPlan: false,
      productId: 'rephone_premium_monthly',
      displayPrice: null,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initIap();
  }

  Future<void> _initIap() async {
    try {
      await _iap.init();
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        final proIndex = _plans.indexWhere((p) => p.id == 'pro');
        if (proIndex != -1) {
          final proPlan = _plans[proIndex];
          final product = proPlan.productId == null
              ? null
              : _iap.getProduct(proPlan.productId!);
          if (product != null) {
            _plans[proIndex] = MembershipPlan(
              id: proPlan.id,
              price: proPlan.price,
              isRecommended: proPlan.isRecommended,
              isCurrentPlan: proPlan.isCurrentPlan,
              productId: proPlan.productId,
              displayPrice: product.price,
            );
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _error = 'failed';
      });
    }
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
            const SizedBox(height: 32),
            if (_loadingProducts)
              const Center(child: CircularProgressIndicator())
            else
              _buildPlansSection(),
            const SizedBox(height: 32),
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_isCurrentlyMember)
            ElevatedButton(
              onPressed: _showUpgradeDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.grey[800],
              ),
              child: Text(l.membershipButtonUpgrade),
            ),
        ],
      ),
    );
  }

  Widget _buildPlansSection() {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.membershipSectionTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _plans.length,
          itemBuilder: (context, index) {
            return _buildPlanCard(_plans[index]);
          },
        ),
      ],
    );
  }

  Widget _buildPlanCard(MembershipPlan plan) {
    final l = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: plan.isRecommended
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[300]!,
          width: plan.isRecommended ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          if (plan.isRecommended)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Text(
                  l.membershipBadgeRecommended,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan.id == 'basic' ? l.membershipPlanBasic : l.membershipPlanPro,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (plan.isCurrentPlan)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          l.membershipBadgeCurrent,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: plan.isFree
                            ? l.membershipPriceFree
                            : plan.displayPrice ?? '¥${plan.price!.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      TextSpan(
                        text: plan.isFree ? ' · ${l.membershipDurationForever}' : '/${l.membershipDurationMonth}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ..._buildFeatureWidgets(plan, l),
                const SizedBox(height: 16),
                if (!plan.isCurrentPlan)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _subscribeToPlan(plan),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: plan.isRecommended
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      child: Text(l.membershipActionSubscribe),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
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
              // TODO: 跳转到订阅页面
            },
            child: Text(l.membershipButtonUpgrade),
          ),
        ],
      ),
    );
  }

  void _subscribeToPlan(MembershipPlan plan) {
    final l = AppLocalizations.of(context);
    final planName = plan.id == 'basic' ? l.membershipPlanBasic : l.membershipPlanPro;

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
              final productId = plan.productId;
              final product = productId == null ? null : _iap.getProduct(productId);
              if (product == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.membershipDialogSubscribeContent)),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${l.membershipDialogProcessing} $planName')),
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

class MembershipPlan {
  final String id;
  final double? price;
  final bool isRecommended;
  final bool isCurrentPlan;
  final String? productId;
  final String? displayPrice;

  MembershipPlan({
    required this.id,
    required this.price,
    required this.isRecommended,
    required this.isCurrentPlan,
    this.productId,
    this.displayPrice,
  });

  bool get isFree => price == null || price == 0;
}

List<Widget> _buildFeatureWidgets(MembershipPlan plan, AppLocalizations l) {
  final featureKeys = plan.id == 'basic'
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
              Icon(
                Icons.check_circle,
                size: 16,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              Text(l.tr(key)),
            ],
          ),
        ),
      )
      .toList();
}
