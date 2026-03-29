import "dart:async";
import "dart:convert";

import "package:fluentui_system_icons/fluentui_system_icons.dart";
import "package:flutter/material.dart";
import "package:mobile_scanner/mobile_scanner.dart";

import "../../models/user_session.dart";
import "../../services/dashboard_service.dart";

class LaundryQRScannerScreen extends StatefulWidget {
  const LaundryQRScannerScreen({
    required this.session,
    required this.dashboardService,
    super.key,
  });

  final UserSession session;
  final DashboardService dashboardService;

  @override
  State<LaundryQRScannerScreen> createState() => _LaundryQRScannerScreenState();
}

class _LaundryQRScannerScreenState extends State<LaundryQRScannerScreen>
    with WidgetsBindingObserver {
  late MobileScannerController _scannerController;
  final TextEditingController _regNoController = TextEditingController();
  final FocusNode _regNoFocusNode = FocusNode();

  bool _isScanning = true;
  bool _isProcessing = false;
  ScannedPayload? _scannedPayload;
  ScanResultScreen? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scannerController = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
      returnImage: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    _regNoController.dispose();
    _regNoFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _scannerController.start();
      case AppLifecycleState.inactive:
        _scannerController.stop();
    }
  }

  Future<void> _processScannedCode(String code) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final payload = _parseQrPayload(code);
      if (payload == null) {
        _showErrorResult("Invalid QR code format");
        return;
      }

      setState(() => _scannedPayload = payload);

      await _scannerController.stop();
      setState(() => _isScanning = false);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _searchByRegNo(String regNo) async {
    final trimmed = regNo.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter registration number")),
      );
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // Create a synthetic payload with just roll_no
      final payload = ScannedPayload(
        rollNo: trimmed,
        email: "",
        roomNo: "",
        blockName: "",
      );

      setState(() => _scannedPayload = payload);

      await _scannerController.stop();
      setState(() => _isScanning = false);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  ScannedPayload? _parseQrPayload(String qrText) {
    try {
      final decoded = jsonDecode(qrText) as Map<String, dynamic>;

      // Support multiple field name variations
      final rollNo = (decoded["roll_no"] ??
              decoded["reg_no"] ??
              decoded["regno"] ??
              decoded["registration_no"] ??
              "")
          .toString()
          .trim();

      final email =
          (decoded["email"] ?? decoded["mail"] ?? "").toString().trim();
      final roomNo =
          (decoded["room_no"] ?? decoded["room"] ?? "").toString().trim();
      final blockName =
          (decoded["block_name"] ?? decoded["block"] ?? "").toString().trim();

      if (rollNo.isEmpty) {
        return null;
      }

      return ScannedPayload(
        rollNo: rollNo,
        email: email,
        roomNo: roomNo,
        blockName: blockName,
      );
    } catch (_) {
      // Try pipe-separated format: roll_no|email|room_no|block_name
      try {
        final parts = qrText.split("|");
        if (parts.isNotEmpty) {
          return ScannedPayload(
            rollNo: parts[0].trim(),
            email: parts.length > 1 ? parts[1].trim() : "",
            roomNo: parts.length > 2 ? parts[2].trim() : "",
            blockName: parts.length > 3 ? parts[3].trim() : "",
          );
        }
      } catch (_) {
        return null;
      }
      return null;
    }
  }

  Future<void> _confirmSubmission() async {
    if (_scannedPayload == null || _isProcessing) return;

    setState(() => _isProcessing = true);
    const String eventType = "SUBMISSION";

    try {
      final result = await widget.dashboardService.scanLaundryQr(
        token: widget.session.accessToken,
        qrText: _buildQrText(_scannedPayload!),
        eventType: eventType,
      );

      await _showSuccessResult(
        result,
        eventType,
      );
    } catch (e) {
      await _showErrorResult(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _confirmCollection() async {
    if (_scannedPayload == null || _isProcessing) return;

    setState(() => _isProcessing = true);
    const String eventType = "COLLECTION";

    try {
      final result = await widget.dashboardService.scanLaundryQr(
        token: widget.session.accessToken,
        qrText: _buildQrText(_scannedPayload!),
        eventType: eventType,
      );

      await _showSuccessResult(
        result,
        eventType,
      );
    } catch (e) {
      await _showErrorResult(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  String _buildQrText(ScannedPayload payload) {
    return jsonEncode({
      "roll_no": payload.rollNo,
      if (payload.email.isNotEmpty) "email": payload.email,
      if (payload.roomNo.isNotEmpty) "room_no": payload.roomNo,
      if (payload.blockName.isNotEmpty) "block_name": payload.blockName,
    });
  }

  Future<void> _showSuccessResult(
    Map<String, dynamic> result,
    String eventType,
  ) async {
    _lastResult = ScanResultScreen(
      isSuccess: true,
      studentName: result["student_name"] ?? "",
      studentRollNo: result["student_roll_no"] ?? "",
      roomNo: result["room_no"] ?? "",
      blockName: result["block_name"] ?? "",
      eventType: eventType,
      message: result["message"] ?? "Success",
      onContinue: _resetScanner,
    );

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _lastResult!,
        fullscreenDialog: true,
      ),
    );

    await _ensureScannerActive();
  }

  Future<void> _showErrorResult(String error) async {
    _lastResult = ScanResultScreen(
      isSuccess: false,
      error: error,
      onContinue: _resetScanner,
    );

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _lastResult!,
        fullscreenDialog: true,
      ),
    );

    await _ensureScannerActive();
  }

  Future<void> _ensureScannerActive() async {
    if (!mounted) {
      return;
    }

    try {
      await _scannerController.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanning = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _resetScanner() async {
    if (mounted) {
      setState(() {
        _scannedPayload = null;
        _regNoController.clear();
        _lastResult = null;
      });

      await _ensureScannerActive();

      if (_regNoFocusNode.canRequestFocus) {
        _regNoFocusNode.requestFocus();
      }
    }
  }

  Future<void> _cancelPayloadView() async {
    setState(() {
      _scannedPayload = null;
    });
    await _ensureScannerActive();
  }

  @override
  Widget build(BuildContext context) {
    if (_scannedPayload != null) {
      return _buildPayloadConfirmScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Laundry QR Scanner"),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_isScanning)
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          _processScannedCode(barcode.rawValue!);
                        }
                      }
                    },
                  )
                else
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Scanner Inactive",
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _ensureScannerActive,
                            icon: const Icon(Icons.videocam),
                            label: const Text("Resume Camera"),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: 20,
                  right: 20,
                  child: FloatingActionButton(
                    mini: true,
                    onPressed: () {
                      _scannerController.toggleTorch();
                    },
                    child: const Icon(FluentIcons.weather_sunny_24_regular),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Column(
              children: [
                TextField(
                  controller: _regNoController,
                  focusNode: _regNoFocusNode,
                  enabled: !_isProcessing,
                  decoration: InputDecoration(
                    labelText: "Or enter registration number",
                    prefixIcon: const Icon(FluentIcons.search_24_regular),
                    suffixIcon: _regNoController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: () {
                              _regNoController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _searchByRegNo,
                ),
                const SizedBox(height: 12),
                if (_regNoController.text.isNotEmpty && !_isProcessing)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _searchByRegNo(_regNoController.text),
                      child: const Text("Search Student"),
                    ),
                  )
                else if (_isProcessing)
                  const SizedBox(
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadConfirmScreen() {
    final payload = _scannedPayload!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Confirm Student"),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            FluentIcons.person_24_regular,
                            size: 28,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Registration Number",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  payload.rollNo,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (payload.email.isNotEmpty)
                        Row(
                          children: [
                            const Icon(
                              FluentIcons.mail_24_regular,
                              size: 24,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Email",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    payload.email,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (payload.email.isNotEmpty) const SizedBox(height: 12),
                      if (payload.roomNo.isNotEmpty)
                        Row(
                          children: [
                            const Icon(
                              FluentIcons.home_24_regular,
                              size: 24,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Room Number",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    payload.roomNo,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (payload.roomNo.isNotEmpty) const SizedBox(height: 12),
                      if (payload.blockName.isNotEmpty)
                        Row(
                          children: [
                            const Icon(
                              FluentIcons.building_24_regular,
                              size: 24,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Block",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    payload.blockName,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Choose Action",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _confirmSubmission,
                      icon: const Icon(FluentIcons.send_24_regular),
                      label: const Text("Submission"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange,
                        disabledBackgroundColor: Colors.orange.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _confirmCollection,
                      icon: const Icon(FluentIcons.arrow_sync_24_regular),
                      label: const Text("Collection"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.green.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : () => _cancelPayloadView(),
                  child: const Text("Cancel"),
                ),
              ),
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannedPayload {
  const ScannedPayload({
    required this.rollNo,
    required this.email,
    required this.roomNo,
    required this.blockName,
  });

  final String rollNo;
  final String email;
  final String roomNo;
  final String blockName;
}

class ScanResultScreen extends StatefulWidget {
  const ScanResultScreen({
    required this.isSuccess,
    this.studentName = "",
    this.studentRollNo = "",
    this.roomNo = "",
    this.blockName = "",
    this.eventType = "",
    this.message = "",
    this.error = "",
    required this.onContinue,
    super.key,
  });

  final bool isSuccess;
  final String studentName;
  final String studentRollNo;
  final String roomNo;
  final String blockName;
  final String eventType;
  final String message;
  final String error;
  final Future<void> Function() onContinue;

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  late Timer _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _startAutoClose();
  }

  @override
  void dispose() {
    _autoCloseTimer.cancel();
    super.dispose();
  }

  void _startAutoClose() {
    _autoCloseTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _close();
      }
    });
  }

  Future<void> _close() async {
    Navigator.of(context).pop();
    await widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: widget.isSuccess
                ? [Colors.green.shade600, Colors.green.shade400]
                : [Colors.red.shade600, Colors.red.shade400],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isSuccess
                    ? FluentIcons.checkmark_circle_24_filled
                    : FluentIcons.error_circle_24_regular,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                widget.isSuccess ? "Confirmed!" : "Error",
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  widget.isSuccess
                      ? "${widget.eventType}: ${widget.studentRollNo}"
                      : widget.error,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (widget.isSuccess && widget.studentName.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (widget.isSuccess && widget.roomNo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  "Room: ${widget.roomNo}${widget.blockName.isNotEmpty ? " (${widget.blockName})" : ""}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Text(
                widget.isSuccess
                    ? "Ready for next student..."
                    : "Tap to continue",
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
