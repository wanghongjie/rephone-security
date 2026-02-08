import 'package:flutter/material.dart';

/// 回看页面（占位实现：列表展示，后续接入真实回看能力）
class PlaybackPage extends StatelessWidget {
  const PlaybackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_PlaybackItem>[
      _PlaybackItem(
        cameraName: '客厅摄像头',
        timeText: '12分钟前',
        durationText: '03:24',
      ),
      _PlaybackItem(
        cameraName: '门口摄像头',
        timeText: '2小时前',
        durationText: '01:08',
      ),
      _PlaybackItem(
        cameraName: '儿童房摄像头',
        timeText: '1天前',
        durationText: '05:41',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('回看'),
      ),
      body: items.isEmpty
          ? const Center(child: Text('暂无回看视频'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.play_arrow),
                    ),
                    title: Text(
                      item.cameraName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${item.timeText} • ${item.durationText}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('回看功能后续完善')),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _PlaybackItem {
  _PlaybackItem({
    required this.cameraName,
    required this.timeText,
    required this.durationText,
  });

  final String cameraName;
  final String timeText;
  final String durationText;
}


