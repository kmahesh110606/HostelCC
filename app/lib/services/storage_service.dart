import "package:shared_preferences/shared_preferences.dart";

class StorageService {
  static const _accessKey = "access_token";
  static const _refreshKey = "refresh_token";
  static const _usernameKey = "username";
  static const _roleKey = "role";
  static const _emailKey = "email";
  static const _themeModeKey = "theme_mode";
  static const _profileCacheKey = "profile_cache";
  static const _dashboardCacheKey = "dashboard_cache";

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String username,
    required String role,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, accessToken);
    await prefs.setString(_refreshKey, refreshToken);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_roleKey, role);
    await prefs.setString(_emailKey, email);
  }

  Future<Map<String, String?>> readSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "access": prefs.getString(_accessKey),
      "refresh": prefs.getString(_refreshKey),
      "username": prefs.getString(_usernameKey),
      "role": prefs.getString(_roleKey),
      "email": prefs.getString(_emailKey),
    };
  }

  Future<void> saveThemeMode(String themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, themeMode);
  }

  Future<String?> readThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey);
  }

  Future<void> saveCachedProfile(String profileJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileCacheKey, profileJson);
  }

  Future<String?> readCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profileCacheKey);
  }

  Future<void> saveCachedDashboard(String dashboardJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dashboardCacheKey, dashboardJson);
  }

  Future<String?> readCachedDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dashboardCacheKey);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_profileCacheKey);
    await prefs.remove(_dashboardCacheKey);
  }
}
