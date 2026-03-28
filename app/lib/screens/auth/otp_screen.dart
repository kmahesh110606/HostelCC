import "package:flutter/material.dart";

import "../../services/auth_service.dart";
import "../../widgets/fluent_widgets.dart";
import "create_password_screen.dart";
import "signup_details_screen.dart";

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    required this.authService,
    required this.email,
    this.isSignup = false,
    super.key,
  });

  final AuthService authService;
  final String email;
  final bool isSignup;

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
      if (widget.isSignup) {
        await widget.authService.requestSignupOtp(widget.email);
      } else {
        await widget.authService.requestOtp(widget.email);
      }
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
        widget.email,
        _otpController.text.trim(),
      );
      final data = response["data"] as Map<String, dynamic>;
      final valid = data["valid"] == true;
      final mustChange = data["must_change_password"] == true;

      if (!valid) {
        setState(() {
          _message = "Invalid OTP.";
        });
      } else if (widget.isSignup) {
        if (!mounted) return;
        final session = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SignupDetailsScreen(
              authService: widget.authService,
              email: widget.email,
              otpCode: _otpController.text.trim(),
            ),
          ),
        );
        if (!mounted) return;
        if (session != null) {
          Navigator.of(context).pop(session);
        }
      } else if (mustChange) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreatePasswordScreen(
              authService: widget.authService,
              email: widget.email,
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
              "Email: ${widget.email}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text("Use OTP from email. Dev mode OTP: 110606"),
            FluentTextField(
              controller: _otpController,
              labelText: "OTP",
              hintText: "Enter 6-digit OTP",
              keyboardType: TextInputType.number,
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
