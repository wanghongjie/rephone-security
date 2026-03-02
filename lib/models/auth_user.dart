class AuthUser {
  final int id;
  final String email;
  final int vipLevel;
  final DateTime? expireAt;
  final String? token;

  AuthUser({
    required this.id,
    required this.email,
    required this.vipLevel,
    this.expireAt,
    this.token,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email'] as String? ?? '',
      vipLevel: (json['vip_level'] as num?)?.toInt() ?? 0,
      expireAt: json['expire_at'] != null ? DateTime.tryParse(json['expire_at']) : null,
      token: json['token'] as String?,
    );
  }

  AuthUser copyWith({
    int? id,
    String? email,
    int? vipLevel,
    DateTime? expireAt,
    String? token,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      vipLevel: vipLevel ?? this.vipLevel,
      expireAt: expireAt ?? this.expireAt,
      token: token ?? this.token,
    );
  }
}
