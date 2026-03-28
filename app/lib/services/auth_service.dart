import "../models/user_session.dart";
import "api_client.dart";

class AuthService {
  AuthService({required this.apiClient});

  final ApiClient apiClient;

  Future<Map<String, dynamic>> signupOptions() {
    return apiClient.getMap("/api/auth/signup/options/");
  }

  Future<void> requestSignupOtp(String email) async {
    await apiClient.post("/api/auth/signup/request-otp/", {"email": email});
  }

  Future<UserSession> completeSignup(Map<String, dynamic> payload) async {
    final json = await apiClient.post("/api/auth/signup/complete/", payload);
    final data = (json["data"] ?? <String, dynamic>{}) as Map<String, dynamic>;
    return UserSession.fromJson(data, (data["username"] ?? "").toString());
  }

  Future<void> requestOtp(String username) async {
    await apiClient.post("/api/auth/request-otp/", {"username": username});
  }

  Future<Map<String, dynamic>> verifyOtp(String username, String otpCode) {
    return apiClient.post("/api/auth/verify-otp/", {
      "username": username,
      "otp_code": otpCode,
    });
  }

  Future<void> createFirstPassword({
    required String username,
    required String otpCode,
    required String newPassword,
  }) async {
    await apiClient.post("/api/auth/first-time-password/", {
      "username": username,
      "otp_code": otpCode,
      "new_password": newPassword,
    });
  }

  Future<UserSession> login(String email, String password) async {
    final identifier = email.trim();
    final json = await apiClient.post("/api/auth/login/", {
      "email": identifier,
      "password": password,
    });

    final data = (json["data"] ?? <String, dynamic>{}) as Map<String, dynamic>;
    return UserSession.fromJson(data, identifier);
  }

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    await apiClient.post(
      "/api/auth/change-password/",
      {
        "current_password": currentPassword,
        "new_password": newPassword,
      },
      token: token,
    );
  }
}
