import "package:flutter/material.dart";

import "../../services/auth_service.dart";

class CreatePasswordScreen extends StatefulWidget {
  const CreatePasswordScreen({
    required this.authService,
    required this.username,
    required this.otpCode,
    super.key,
  });

  final AuthService authService;
  final String username;
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
        username: widget.username,
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
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "New Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Confirm Password",
                border: OutlineInputBorder(),
              ),
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
