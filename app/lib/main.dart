import "package:flutter/material.dart";
import "package:flutter/foundation.dart";

import "models/user_session.dart";
import "screens/auth/login_screen.dart";
import "screens/dashboard/role_dashboard_screen.dart";
import "services/api_client.dart";
import "services/auth_service.dart";
import "services/dashboard_service.dart";
import "services/storage_service.dart";
import "theme/fluent_theme.dart";

void main() {
  runApp(const HostelCCApp());
}

class HostelCCApp extends StatefulWidget {
  const HostelCCApp({super.key});

  @override
  State<HostelCCApp> createState() => _HostelCCAppState();
}

class _HostelCCAppState extends State<HostelCCApp> {
  static const String _apiFromEnv = String.fromEnvironment("API_BASE_URL");
  static const String _defaultProdApiBaseUrl =
      "https://hostelcc-api.salmonwave-06a7b54c.centralindia.azurecontainerapps.io";

  static String _resolveApiBaseUrl() {
    if (_apiFromEnv.isNotEmpty) return _apiFromEnv;
    if (kIsWeb) return "http://localhost:8080";
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _defaultProdApiBaseUrl;
    }
    return "http://127.0.0.1:8080";
  }

  final StorageService _storage = StorageService();
  late final ApiClient _apiClient = ApiClient(baseUrl: _resolveApiBaseUrl());
  late final AuthService _authService = AuthService(apiClient: _apiClient);
  late final DashboardService _dashboardService = DashboardService(
    apiClient: _apiClient,
  );

  bool _loading = true;
  UserSession? _session;
  String _lastEmail = "";
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final data = await _storage.readSession();
    final savedTheme = await _storage.readThemeMode();
    final access = data["access"];
    final refresh = data["refresh"];
    final username = data["username"];
    final role = data["role"];
    final email = data["email"];

    _lastEmail = (email ?? "").toString();

    if (access != null && refresh != null && username != null && role != null) {
      _session = UserSession(
        username: username,
        email: _lastEmail.isNotEmpty ? _lastEmail : username,
        role: role,
        accessToken: access,
        refreshToken: refresh,
        mustChangePassword: false,
      );
    }

    _themeMode = _parseThemeMode(savedTheme);

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case "light":
        return ThemeMode.light;
      case "dark":
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeValue(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return "light";
      case ThemeMode.dark:
        return "dark";
      case ThemeMode.system:
        return "system";
    }
  }

  Future<void> _onThemeModeChanged(ThemeMode mode) async {
    await _storage.saveThemeMode(_themeModeValue(mode));
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
    });
  }

  Future<void> _onLogin(UserSession session) async {
    await _storage.saveSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      username: session.username,
      role: session.role,
      email: session.email,
    );
    setState(() {
      _session = session;
      _lastEmail = session.email;
    });
  }

  Future<void> _onLogout() async {
    await _storage.clearSession();
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return MaterialApp(
        title: "HostelCC",
        debugShowCheckedModeBanner: false,
        theme: HostelCCTheme.lightTheme(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "HostelCC web portal is handled by Django. Please open http://localhost:8080",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: "HostelCC",
      debugShowCheckedModeBanner: false,
      theme: HostelCCTheme.lightTheme(),
      darkTheme: HostelCCTheme.darkTheme(),
      themeMode: _themeMode,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_session == null
              ? LoginScreen(
                  authService: _authService,
                  onLogin: _onLogin,
                  initialEmail: _lastEmail,
                )
              : RoleDashboardScreen(
                  session: _session!,
                  authService: _authService,
                  dashboardService: _dashboardService,
                  storageService: _storage,
                  onLogout: _onLogout,
                  themeMode: _themeMode,
                  onThemeModeChanged: _onThemeModeChanged,
                )),
    );
  }
}
