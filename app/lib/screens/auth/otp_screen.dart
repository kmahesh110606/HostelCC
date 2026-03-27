import "package:flutter/material.dart";

import "../../services/auth_service.dart";
import "create_password_screen.dart";

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    required this.authService,
    required this.username,
    super.key,
  });

  final AuthService authService;
  final String username;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _requestOtp();
  }

  Future<void> _requestOtp() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await widget.authService.requestOtp(widget.username);
      setState(() {
        _message = "OTP requested. Check email or use dev OTP.";
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

  Future<void> _verifyOtp() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final response = await widget.authService.verifyOtp(
        widget.username,
        _otpController.text.trim(),
      );
      final data = response["data"] as Map<String, dynamic>;
      final valid = data["valid"] == true;
      final mustChange = data["must_change_password"] == true;

      if (!valid) {
        setState(() {
          _message = "Invalid OTP.";
        });
      } else if (mustChange) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreatePasswordScreen(
              authService: widget.authService,
              username: widget.username,
              otpCode: _otpController.text.trim(),
            ),
          ),
        );
      } else {
        setState(() {
          _message = "OTP valid. You can login with your current password.";
        });
      }
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
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OTP Verification")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Username: ${widget.username}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text("Use OTP from email. Dev mode OTP: 110606"),
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "OTP",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _verifyOtp,
              child: const Text("Verify OTP"),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loading ? null : _requestOtp,
              child: const Text("Resend OTP"),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}
