import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于我们'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RePhone Security',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '家庭看护与安防监控应用（后续将接入 H5 服务条款与隐私协议页面）。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('服务条款'),
            subtitle: const Text('占位内容，后续替换为 H5'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: const [
              Text(
                '这里是服务条款的占位内容。\n\n'
                '后续会替换为线上 H5 页面并支持版本更新。\n\n'
                '当前版本仅用于展示结构与入口。',
                style: TextStyle(height: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('隐私协议'),
            subtitle: const Text('占位内容，后续替换为 H5'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: const [
              Text(
                '这里是隐私协议的占位内容。\n\n'
                '后续会替换为线上 H5 页面，并明确说明数据收集、使用与存储策略。\n\n'
                '当前版本仅用于展示结构与入口。',
                style: TextStyle(height: 1.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


