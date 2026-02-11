class DetectionEvent {
  final int? id;
  final int timestamp;
  final String imagePath;
  final String videoPath;

  DetectionEvent({
    this.id,
    required this.timestamp,
    required this.imagePath,
    required this.videoPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'image_path': imagePath,
      'video_path': videoPath,
    };
  }

  factory DetectionEvent.fromMap(Map<String, dynamic> map) {
    return DetectionEvent(
      id: map['id'],
      timestamp: map['timestamp'],
      imagePath: map['image_path'],
      videoPath: map['video_path'],
    );
  }
}
