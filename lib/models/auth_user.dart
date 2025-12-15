class AuthUser {
  final int id;
  final String email;

  AuthUser({
    required this.id,
    required this.email,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email'] as String? ?? '',
    );
  }
}

