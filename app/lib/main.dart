import "package:flutter/material.dart";

import "models/user_session.dart";
import "screens/auth/login_screen.dart";
import "screens/dashboard/role_dashboard_screen.dart";
import "services/api_client.dart";
import "services/auth_service.dart";
import "services/dashboard_service.dart";
import "services/storage_service.dart";

void main() {
  runApp(const HostelCCApp());
}

class HostelCCApp extends StatefulWidget {
  const HostelCCApp({super.key});

  @override
  State<HostelCCApp> createState() => _HostelCCAppState();
}

class _HostelCCAppState extends State<HostelCCApp> {
  static const String apiBaseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "http://10.0.2.2:8080",
  );

  final StorageService _storage = StorageService();
  late final ApiClient _apiClient = ApiClient(baseUrl: apiBaseUrl);
  late final AuthService _authService = AuthService(apiClient: _apiClient);
  late final DashboardService _dashboardService = DashboardService(
    apiClient: _apiClient,
  );

  bool _loading = true;
  UserSession? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final data = await _storage.readSession();
    final access = data["access"];
    final refresh = data["refresh"];
    final username = data["username"];
    final role = data["role"];

    if (access != null && refresh != null && username != null && role != null) {
      _session = UserSession(
        username: username,
        role: role,
        accessToken: access,
        refreshToken: refresh,
        mustChangePassword: false,
      );
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _onLogin(UserSession session) async {
    await _storage.saveSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      username: session.username,
      role: session.role,
    );
    setState(() {
      _session = session;
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
    return MaterialApp(
      title: "HostelCC",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.light,
          primary: const Color(0xFF0D47A1),
          secondary: const Color(0xFF1976D2),
        ),
        scaffoldBackgroundColor: const Color(0xFFEAF3FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B3D91),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFF5FAFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_session == null
                ? LoginScreen(authService: _authService, onLogin: _onLogin)
                : RoleDashboardScreen(
                    session: _session!,
                    dashboardService: _dashboardService,
                    onLogout: _onLogout,
                  )),
    );
  }
}
