import "package:flutter/material.dart";

import "../../models/user_session.dart";
import "../../services/auth_service.dart";
import "../../widgets/fluent_widgets.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authService,
    required this.onLogin,
    this.initialEmail,
    super.key,
  });

  final AuthService authService;
  final Future<void> Function(UserSession session) onLogin;
  final String? initialEmail;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.initialEmail ?? "").trim().isNotEmpty) {
      _emailController.text = widget.initialEmail!.trim();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = await widget.authService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      await widget.onLogin(session);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFFBBDEFB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Card(
            elevation: 6,
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "HostelCC",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0B3D91),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Sign in with your hostel email and password."
                        "\nCreate new accounts on the website only.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FluentTextField(
                        controller: _emailController,
                        labelText: "Email",
                        hintText: "Enter your email",
                        prefixIcon: Icons.email_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? "Email is required"
                            : (!v.contains("@") ? "Enter a valid email" : null),
                      ),
                      const SizedBox(height: 12),
                      FluentTextField(
                        controller: _passwordController,
                        labelText: "Password",
                        hintText: "Enter your password",
                        obscureText: true,
                        prefixIcon: Icons.lock_outline,
                        validator: (v) => (v == null || v.isEmpty)
                            ? "Password is required"
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loading ? null : _login,
                        icon: const Icon(Icons.login),
                        label: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text("Sign In"),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Need a new account? Use the website signup flow.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0B3D91),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
