import "package:fluentui_system_icons/fluentui_system_icons.dart";
import "package:flutter/material.dart";

import "../../models/user_session.dart";
import "../../services/auth_service.dart";
import "../../widgets/fluent_widgets.dart";

class SignupDetailsScreen extends StatefulWidget {
  const SignupDetailsScreen({
    required this.authService,
    required this.email,
    required this.otpCode,
    super.key,
  });

  final AuthService authService;
  final String email;
  final String otpCode;

  @override
  State<SignupDetailsScreen> createState() => _SignupDetailsScreenState();
}

class _SignupDetailsScreenState extends State<SignupDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final _registrationNoController = TextEditingController();
  final _roomNoController = TextEditingController();
  final _jobTitleController = TextEditingController();

  bool _loading = false;
  String? _error;

  List<Map<String, String>> _blockChoices = <Map<String, String>>[];
  List<Map<String, String>> _staffRoles = <Map<String, String>>[];
  List<Map<String, String>> _departmentChoices = <Map<String, String>>[];
  List<String> _messNames = <String>[];
  List<String> _countryCodes = <String>["+91"];

  String _countryCode = "+91";
  String _messType = "VEG";
  String _block = "";
  String _role = "WARDEN";
  String _department = "";
  String _assignedMessName = "";

  bool get _isStudent =>
      widget.email.toLowerCase().endsWith("@vitstudent.ac.in");

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _registrationNoController.dispose();
    _roomNoController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.authService.signupOptions();
      final data =
          (response["data"] ?? <String, dynamic>{}) as Map<String, dynamic>;

      final countryCodes =
          ((data["country_codes"] ?? <dynamic>[]) as List<dynamic>)
              .map((e) => e.toString())
              .toList();
      final blocks = ((data["block_choices"] ?? <dynamic>[]) as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .map((e) =>
              {"value": e["value"].toString(), "label": e["label"].toString()})
          .toList();
      final staffRoles = ((data["staff_roles"] ?? <dynamic>[]) as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .map((e) =>
              {"value": e["value"].toString(), "label": e["label"].toString()})
          .toList();
      final departments = ((data["department_choices"] ?? <dynamic>[])
              as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .map((e) =>
              {"value": e["value"].toString(), "label": e["label"].toString()})
          .toList();
      final messNames = ((data["mess_names"] ?? <dynamic>[]) as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      if (!mounted) return;
      setState(() {
        _countryCodes = countryCodes.isNotEmpty ? countryCodes : ["+91"];
        _countryCode = _countryCodes.first;

        _blockChoices = blocks;
        _block = _blockChoices.isNotEmpty ? _blockChoices.first["value"]! : "";

        _staffRoles = staffRoles;
        _role = _staffRoles.isNotEmpty ? _staffRoles.first["value"]! : "WARDEN";

        _departmentChoices = departments;
        _department = _departmentChoices.isNotEmpty
            ? _departmentChoices.first["value"]!
            : "";

        _messNames = messNames;
        _assignedMessName = _messNames.isNotEmpty ? _messNames.first : "";
      });
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      "email": widget.email,
      "otp_code": widget.otpCode,
      "name": _nameController.text.trim(),
      "phone_country_code": _countryCode,
      "phone_number": _phoneController.text.trim(),
      "password": _passwordController.text,
      "confirm_password": _confirmController.text,
    };

    if (_isStudent) {
      payload.addAll({
        "registration_no": _registrationNoController.text.trim(),
        "block": _block,
        "room_no": _roomNoController.text.trim().toUpperCase(),
        "mess_type": _messType,
      });
    } else {
      payload.addAll({
        "role": _role,
        "job_title": _jobTitleController.text.trim(),
        "department": _department,
        "assigned_mess_name": _role == "MESS_MANAGER" ? _assignedMessName : "",
      });
    }

    try {
      final session = await widget.authService.completeSignup(payload);
      if (!mounted) return;
      Navigator.of(context).pop<UserSession>(session);
    } catch (e) {
      if (!mounted) return;
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
      appBar: AppBar(title: const Text("Complete Sign Up")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                      title: "Account Details",
                      subtitle: "Complete your profile to finish sign up",
                    ),
                    Row(
                      children: [
                        const Icon(FluentIcons.mail_24_regular),
                        const SizedBox(width: 8),
                        Expanded(child: Text(widget.email)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FluentTextField(
                      controller: _nameController,
                      labelText: "Full Name",
                      hintText: "Enter your full name",
                      prefixIcon: FluentIcons.person_24_regular,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? "Full name is required"
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _countryCode,
                            decoration: const InputDecoration(
                              labelText: "Code",
                              border: OutlineInputBorder(),
                            ),
                            items: _countryCodes
                                .map((code) => DropdownMenuItem(
                                    value: code, child: Text(code)))
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _countryCode = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: FluentTextField(
                            controller: _phoneController,
                            labelText: "Phone Number",
                            keyboardType: TextInputType.phone,
                            prefixIcon: FluentIcons.phone_24_regular,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? "Phone number is required"
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isStudent) ...[
                      const SectionHeader(
                        title: "Student Details",
                        subtitle: "Match your hostel registration data",
                      ),
                      FluentTextField(
                        controller: _registrationNoController,
                        labelText: "Registration Number",
                        hintText: "24BAI1400",
                        prefixIcon: Icons.badge_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? "Registration number is required"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _block.isNotEmpty ? _block : null,
                        decoration: const InputDecoration(
                          labelText: "Block",
                          border: OutlineInputBorder(),
                        ),
                        items: _blockChoices
                            .map((e) => DropdownMenuItem(
                                value: e["value"], child: Text(e["label"]!)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _block = value;
                          });
                        },
                        validator: (v) => (v == null || v.isEmpty)
                            ? "Block is required"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      FluentTextField(
                        controller: _roomNoController,
                        labelText: "Room Number",
                        hintText: "413",
                        prefixIcon: Icons.meeting_room_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? "Room number is required"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _messType,
                        decoration: const InputDecoration(
                          labelText: "Mess Type",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: "VEG", child: Text("Vegetarian")),
                          DropdownMenuItem(
                              value: "NON_VEG", child: Text("Non-Vegetarian")),
                          DropdownMenuItem(
                              value: "SPECIAL", child: Text("Special Diet")),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _messType = value;
                          });
                        },
                      ),
                    ] else ...[
                      const SectionHeader(
                        title: "Staff Details",
                        subtitle: "Choose your role and department",
                      ),
                      DropdownButtonFormField<String>(
                        value: _role,
                        decoration: const InputDecoration(
                          labelText: "Role",
                          border: OutlineInputBorder(),
                        ),
                        items: _staffRoles
                            .map((e) => DropdownMenuItem(
                                value: e["value"], child: Text(e["label"]!)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _role = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _department.isNotEmpty ? _department : null,
                        decoration: const InputDecoration(
                          labelText: "Department",
                          border: OutlineInputBorder(),
                        ),
                        items: _departmentChoices
                            .map((e) => DropdownMenuItem(
                                value: e["value"], child: Text(e["label"]!)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _department = value;
                          });
                        },
                        validator: (v) => (v == null || v.isEmpty)
                            ? "Department is required"
                            : null,
                      ),
                      const SizedBox(height: 10),
                      FluentTextField(
                        controller: _jobTitleController,
                        labelText: "Job Title",
                        hintText: "Maintenance Head",
                        prefixIcon: FluentIcons.briefcase_24_regular,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? "Job title is required"
                            : null,
                      ),
                      if (_role == "MESS_MANAGER") ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _assignedMessName.isNotEmpty
                              ? _assignedMessName
                              : null,
                          decoration: const InputDecoration(
                            labelText: "Assigned Mess",
                            border: OutlineInputBorder(),
                          ),
                          items: _messNames
                              .map((name) => DropdownMenuItem(
                                  value: name, child: Text(name)))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _assignedMessName = value;
                            });
                          },
                          validator: (v) => (v == null || v.isEmpty)
                              ? "Assigned mess is required"
                              : null,
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    const SectionHeader(
                      title: "Set Password",
                      subtitle: "Use at least 8 characters",
                    ),
                    FluentTextField(
                      controller: _passwordController,
                      labelText: "Password",
                      obscureText: true,
                      prefixIcon: FluentIcons.key_24_regular,
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return "Password is required";
                        if (v.length < 8)
                          return "Password must be at least 8 characters";
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    FluentTextField(
                      controller: _confirmController,
                      labelText: "Confirm Password",
                      obscureText: true,
                      prefixIcon: FluentIcons.key_24_regular,
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return "Confirm password is required";
                        if (v != _passwordController.text)
                          return "Passwords do not match";
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: const Icon(FluentIcons.checkmark_circle_24_regular),
                      label: const Text("Create Account"),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
