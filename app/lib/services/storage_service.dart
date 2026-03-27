import "package:shared_preferences/shared_preferences.dart";

class StorageService {
  static const _accessKey = "access_token";
  static const _refreshKey = "refresh_token";
  static const _usernameKey = "username";
  static const _roleKey = "role";

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String username,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, accessToken);
    await prefs.setString(_refreshKey, refreshToken);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_roleKey, role);
  }

  Future<Map<String, String?>> readSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "access": prefs.getString(_accessKey),
      "refresh": prefs.getString(_refreshKey),
      "username": prefs.getString(_usernameKey),
      "role": prefs.getString(_roleKey),
    };
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_roleKey);
  }
}
