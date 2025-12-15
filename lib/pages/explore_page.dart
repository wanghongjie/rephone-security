import 'package:flutter/material.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final List<ExploreItem> _exploreItems = [
    ExploreItem(
      title: '智能检测',
      subtitle: '人脸识别、动作检测、异常报警',
      icon: Icons.psychology,
      color: Colors.purple,
    ),
    ExploreItem(
      title: '云端存储',
      subtitle: '7天免费云存储，30天高级存储',
      icon: Icons.cloud_upload,
      color: Colors.blue,
    ),
    ExploreItem(
      title: '多设备同步',
      subtitle: '手机、平板、电脑多端同步查看',
      icon: Icons.devices,
      color: Colors.green,
    ),
    ExploreItem(
      title: '夜视功能',
      subtitle: '红外夜视，24小时全天候监控',
      icon: Icons.nightlight,
      color: Colors.indigo,
    ),
    ExploreItem(
      title: '双向通话',
      subtitle: '实时语音对讲，远程沟通',
      icon: Icons.record_voice_over,
      color: Colors.orange,
    ),
    ExploreItem(
      title: '隐私保护',
      subtitle: '端到端加密，保护您的隐私',
      icon: Icons.security,
      color: Colors.red,
    ),
  ];

  final List<NewsItem> _newsItems = [
    NewsItem(
      title: '新版本更新：增强AI识别功能',
      content: '最新版本增加了更精准的人脸识别和宠物检测功能',
      time: DateTime.now().subtract(const Duration(hours: 2)),
      imageUrl: 'assets/images/news1.jpg',
    ),
    NewsItem(
      title: '安全提醒：如何设置强密码',
      content: '学习如何为您的设备设置安全可靠的密码',
      time: DateTime.now().subtract(const Duration(days: 1)),
      imageUrl: 'assets/images/news2.jpg',
    ),
    NewsItem(
      title: '用户故事：RePhone帮我找回丢失的宠物',
      content: '用户分享使用RePhone Security成功找回走失宠物的经历',
      time: DateTime.now().subtract(const Duration(days: 3)),
      imageUrl: 'assets/images/news3.jpg',
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
            _buildSearchBar(),
            const SizedBox(height: 24),
            _buildFeaturesSection(),
            const SizedBox(height: 32),
            _buildNewsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索功能、教程、帮助...',
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onSubmitted: (value) {
          // TODO: 实现搜索功能
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('搜索: $value')),
          );
        },
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '功能特色',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9, // 调整宽高比，给更多垂直空间
          ),
          itemCount: _exploreItems.length,
          itemBuilder: (context, index) {
            return _buildFeatureCard(_exploreItems[index]);
          },
        ),
      ],
    );
  }

  Widget _buildFeatureCard(ExploreItem item) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _onFeatureTap(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12), // 减少padding
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, // 添加这行，让Column占用最小空间
            children: [
              Container(
                padding: const EdgeInsets.all(8), // 减少icon容器的padding
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  size: 28, // 稍微减小图标大小
                  color: item.color,
                ),
              ),
              const SizedBox(height: 8), // 减少间距
              Text(
                item.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13, // 稍微减小字体
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2), // 减少间距
              Flexible( // 使用Flexible包装，避免溢出
                child: Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 11, // 减小副标题字体
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '最新资讯',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TextButton(
              onPressed: () {
                // TODO: 查看更多资讯
              },
              child: const Text('查看更多'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _newsItems.length,
          itemBuilder: (context, index) {
            return _buildNewsCard(_newsItems[index]);
          },
        ),
      ],
    );
  }

  Widget _buildNewsCard(NewsItem news) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.article,
            color: Colors.grey,
          ),
        ),
        title: Text(
          news.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              news.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(news.time),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        onTap: () => _onNewsTap(news),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  void _onFeatureTap(ExploreItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: Text(item.subtitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解更多'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _onNewsTap(NewsItem news) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('查看资讯: ${news.title}')),
    );
  }
}

class ExploreItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  ExploreItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class NewsItem {
  final String title;
  final String content;
  final DateTime time;
  final String imageUrl;

  NewsItem({
    required this.title,
    required this.content,
    required this.time,
    required this.imageUrl,
  });
}
