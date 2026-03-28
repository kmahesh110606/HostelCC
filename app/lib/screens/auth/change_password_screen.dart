import "package:fluentui_system_icons/fluentui_system_icons.dart";
import "package:flutter/material.dart";

import "../../services/auth_service.dart";
import "../../widgets/fluent_widgets.dart";

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    required this.authService,
    required this.token,
    super.key,
  });

  final AuthService authService;
  final String token;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await widget.authService.changePassword(
        token: widget.token,
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Change Password")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: "Update Password",
                subtitle: "Use your current password and set a new one",
              ),
              FluentTextField(
                controller: _currentController,
                labelText: "Current Password",
                obscureText: true,
                prefixIcon: FluentIcons.lock_closed_24_regular,
                validator: (v) => (v == null || v.isEmpty) ? "Current password is required" : null,
              ),
              const SizedBox(height: 10),
              FluentTextField(
                controller: _newController,
                labelText: "New Password",
                obscureText: true,
                prefixIcon: FluentIcons.key_24_regular,
                validator: (v) {
                  if (v == null || v.isEmpty) return "New password is required";
                  if (v.length < 8) return "New password must be at least 8 characters";
                  return null;
                },
              ),
              const SizedBox(height: 10),
              FluentTextField(
                controller: _confirmController,
                labelText: "Confirm New Password",
                obscureText: true,
                prefixIcon: FluentIcons.key_24_regular,
                validator: (v) {
                  if (v == null || v.isEmpty) return "Confirm password is required";
                  if (v != _newController.text) return "Passwords do not match";
                  return null;
                },
              ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(_message!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: const Icon(FluentIcons.checkmark_24_regular),
                label: const Text("Update Password"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
