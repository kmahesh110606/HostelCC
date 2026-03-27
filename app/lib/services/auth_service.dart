import "../models/user_session.dart";
import "api_client.dart";

class AuthService {
  AuthService({required this.apiClient});

  final ApiClient apiClient;

  Future<void> requestOtp(String username) async {
    await apiClient.post("/api/auth/request-otp", {"username": username});
  }

  Future<Map<String, dynamic>> verifyOtp(String username, String otpCode) {
    return apiClient.post("/api/auth/verify-otp", {
      "username": username,
      "otp_code": otpCode,
    });
  }

  Future<void> createFirstPassword({
    required String username,
    required String otpCode,
    required String newPassword,
  }) async {
    await apiClient.post("/api/auth/first-time-password", {
      "username": username,
      "otp_code": otpCode,
      "new_password": newPassword,
    });
  }

  Future<UserSession> login(String username, String password) async {
    final json = await apiClient.post("/api/auth/login", {
      "username": username,
      "password": password,
    });

    final data = (json["data"] ?? <String, dynamic>{}) as Map<String, dynamic>;
    return UserSession.fromJson(data, username);
  }
}
