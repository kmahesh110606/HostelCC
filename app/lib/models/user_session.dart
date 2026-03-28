class UserSession {
  const UserSession({
    required this.username,
    required this.email,
    required this.role,
    required this.accessToken,
    required this.refreshToken,
    required this.mustChangePassword,
  });

  final String username;
  final String email;
  final String role;
  final String accessToken;
  final String refreshToken;
  final bool mustChangePassword;

  factory UserSession.fromJson(Map<String, dynamic> json, String username) {
    return UserSession(
      username: username,
      email: (json["email"] ?? username).toString(),
      role: (json["role"] ?? "STUDENT").toString(),
      accessToken: (json["access"] ?? "").toString(),
      refreshToken: (json["refresh"] ?? "").toString(),
      mustChangePassword: json["must_change_password"] == true,
    );
  }
}
