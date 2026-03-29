import "dart:io";

import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";

import "../../services/dashboard_service.dart";
import "../../widgets/fluent_widgets.dart";

class NewComplaintScreen extends StatefulWidget {
  const NewComplaintScreen({
    required this.dashboardService,
    required this.accessToken,
    super.key,
  });

  final DashboardService dashboardService;
  final String accessToken;

  @override
  State<NewComplaintScreen> createState() => _NewComplaintScreenState();
}

class _NewComplaintScreenState extends State<NewComplaintScreen> {
  static const List<MapEntry<String, String>> _categories =
      <MapEntry<String, String>>[
    MapEntry<String, String>("CARPENTRY", "Carpentry"),
    MapEntry<String, String>("PLUMBING", "Plumbing"),
    MapEntry<String, String>("AC", "AC"),
    MapEntry<String, String>("DRINKING_WATER", "Drinking Water"),
    MapEntry<String, String>("UTILITY_WATER", "Utility Water"),
    MapEntry<String, String>("DISCIPLINE", "Discipline"),
    MapEntry<String, String>("CIVIL_INFRA", "Civil/Infra"),
    MapEntry<String, String>("ELECTRICAL", "Electrical"),
    MapEntry<String, String>("GYM", "Gym"),
    MapEntry<String, String>("CLEANING", "Cleaning"),
    MapEntry<String, String>("SECURITY", "Security"),
    MapEntry<String, String>("LAUNDRY", "Laundry"),
    MapEntry<String, String>("MESS_ISSUES", "Mess Issues"),
  ];

  final TextEditingController _complaintController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _selectedCategory = _categories.first.key;
  XFile? _selectedMedia;
  bool _submitting = false;

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submit() async {
    final complaintText = _complaintController.text.trim();
    if (complaintText.isEmpty) {
      _toast("Complaint text is required");
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.dashboardService.submitComplaint(
        token: widget.accessToken,
        category: _selectedCategory,
        text: complaintText,
        mediaFilePath: _selectedMedia?.path,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    if (_submitting) {
      return;
    }
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      setState(() {
        _selectedMedia = picked;
      });
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _pickVideo() async {
    if (_submitting) {
      return;
    }
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      setState(() {
        _selectedMedia = picked;
      });
    } catch (e) {
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Complaint"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Post to Community",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Choose the complaint category and describe the issue clearly.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: "Category",
                      border: OutlineInputBorder(),
                    ),
                    items: _categories
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedCategory = value;
                            });
                          },
                  ),
                  const SizedBox(height: 10),
                  FluentTextField(
                    controller: _complaintController,
                    labelText: "Complaint text",
                    hintText: "Explain what happened and where",
                    minLines: 5,
                    maxLines: 9,
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _submitting ? null : _pickImage,
                        child: const Text("Upload Image"),
                      ),
                      OutlinedButton(
                        onPressed: _submitting ? null : _pickVideo,
                        child: const Text("Upload Video"),
                      ),
                      if (_selectedMedia != null)
                        OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () {
                                  setState(() {
                                    _selectedMedia = null;
                                  });
                                },
                          child: const Text("Remove"),
                        ),
                    ],
                  ),
                  if (_selectedMedia != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Selected: ${_selectedMedia!.name}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_selectedMedia!.path.toLowerCase().endsWith(".png") ||
                        _selectedMedia!.path.toLowerCase().endsWith(".jpg") ||
                        _selectedMedia!.path.toLowerCase().endsWith(".jpeg") ||
                        _selectedMedia!.path.toLowerCase().endsWith(".webp") ||
                        _selectedMedia!.path.toLowerCase().endsWith(".gif")) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_selectedMedia!.path),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_submitting ? "Posting..." : "Post Complaint"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
