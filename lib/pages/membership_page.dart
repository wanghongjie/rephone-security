import 'package:flutter/material.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  bool _isCurrentlyMember = false;
  DateTime? _membershipExpiry;

  final List<MembershipPlan> _plans = [
    MembershipPlan(
      name: '基础版',
      price: '免费',
      duration: '永久',
      features: [
        '1天图片云存储（仅图片）',
        '基础报警功能',
        '支持实时视频直播',
        '有广告',
      ],
      isRecommended: false,
      isCurrentPlan: true,
    ),
    MembershipPlan(
      name: '高级版',
      price: '¥19.9',
      duration: '月',
      features: [
        '3天云端视频回看',
        'AI智能检测',
        '去除广告',
        '支持实时视频直播',
      ],
      isRecommended: true,
      isCurrentPlan: false,
    ),
  ];

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
            _buildPlansSection(),
            const SizedBox(height: 32),
            _buildFAQSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMembershipStatus() {
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
                      _isCurrentlyMember ? '高级会员' : '基础用户',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isCurrentlyMember && _membershipExpiry != null)
                      Text(
                        '到期时间: ${_formatDate(_membershipExpiry!)}',
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
              child: const Text('立即升级'),
            ),
        ],
      ),
    );
  }

  Widget _buildPlansSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '会员特权与套餐',
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
                child: const Text(
                  '推荐',
                  style: TextStyle(
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
                      plan.name,
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
                        child: const Text(
                          '当前',
                          style: TextStyle(
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
                        text: plan.price,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      TextSpan(
                        text: plan.price != '免费' ? '/${plan.duration}' : '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...plan.features.map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Text(feature),
                        ],
                      ),
                    )),
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
                      child: Text(
                        plan.price == '免费' ? '降级到此套餐' : '立即订阅',
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

  Widget _buildFAQSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '常见问题',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('如何取消订阅？'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '您可以随时在应用商店的订阅管理中取消订阅，取消后将在当前计费周期结束时生效。',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: const Text('会员权益何时生效？'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '订阅成功后，会员权益将立即生效，您可以马上享受所有高级功能。',
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('升级会员'),
        content: const Text('升级到高级会员，享受更多特权功能！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后再说'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 跳转到订阅页面
            },
            child: const Text('立即升级'),
          ),
        ],
      ),
    );
  }

  void _subscribeToPlan(MembershipPlan plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('订阅${plan.name}'),
        content: Text('确定要订阅${plan.name}套餐吗？价格：${plan.price}/${plan.duration}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('正在处理${plan.name}订阅...')),
              );
              // TODO: 实现订阅逻辑
            },
            child: const Text('确认订阅'),
          ),
        ],
      ),
    );
  }
}
class MembershipPlan {
  final String name;
  final String price;
  final String duration;
  final List<String> features;
  final bool isRecommended;
  final bool isCurrentPlan;

  MembershipPlan({
    required this.name,
    required this.price,
    required this.duration,
    required this.features,
    required this.isRecommended,
    required this.isCurrentPlan,
  });
}
