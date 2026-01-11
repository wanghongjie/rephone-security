class CameraDevice {
  final String id;
  final String name;
  final String location;
  final bool isOnline;
  final DateTime lastSeen;
  final int? bindingId; // 绑定关系ID

  CameraDevice({
    required this.id,
    required this.name,
    required this.location,
    required this.isOnline,
    required this.lastSeen,
    this.bindingId,
  });

  CameraDevice copyWith({
    String? id,
    String? name,
    String? location,
    bool? isOnline,
    DateTime? lastSeen,
    int? bindingId,
  }) {
    return CameraDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      bindingId: bindingId ?? this.bindingId,
    );
  }
}


