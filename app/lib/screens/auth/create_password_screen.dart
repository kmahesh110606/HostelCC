import "package:flutter/material.dart";

import "../../services/auth_service.dart";
import "../../widgets/fluent_widgets.dart";

class CreatePasswordScreen extends StatefulWidget {
  const CreatePasswordScreen({
    required this.authService,
    required this.email,
    required this.otpCode,
    super.key,
  });

  final AuthService authService;
  final String email;
  final String otpCode;

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _message;

  Future<void> _submit() async {
    final p1 = _passwordController.text;
    final p2 = _confirmController.text;
    if (p1.length < 8) {
      setState(() {
        _message = "Password must be at least 8 characters.";
      });
      return;
    }
    if (p1 != p2) {
      setState(() {
        _message = "Passwords do not match.";
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await widget.authService.createFirstPassword(
        username: widget.email,
        otpCode: widget.otpCode,
        newPassword: p1,
      );
      if (!mounted) return;
      setState(() {
        _message = "Password created. Return to login.";
      });
    } catch (e) {
      setState(() {
        _message = e.toString();
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
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create First Password")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FluentTextField(
              controller: _passwordController,
              labelText: "New Password",
              hintText: "Enter new password (min 8 characters)",
              obscureText: true,
            ),
            const SizedBox(height: 12),
            FluentTextField(
              controller: _confirmController,
              labelText: "Confirm Password",
              hintText: "Re-enter password",
              obscureText: true,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: const Text("Create Password"),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}
