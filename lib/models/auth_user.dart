class AuthUser {
  final int id;
  final String email;
  final int vipLevel;

  AuthUser({
    required this.id,
    required this.email,
    required this.vipLevel,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email'] as String? ?? '',
      vipLevel: (json['vip_level'] as num?)?.toInt() ?? 0,
    );
  }
}
