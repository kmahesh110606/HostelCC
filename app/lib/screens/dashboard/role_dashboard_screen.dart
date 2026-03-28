import "dart:convert";
import "dart:ui";

import "package:fluentui_system_icons/fluentui_system_icons.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:mobile_scanner/mobile_scanner.dart";

import "../../models/app_models.dart";
import "../../models/user_session.dart";
import "../../screens/auth/change_password_screen.dart";
import "../../services/auth_service.dart";
import "../../services/dashboard_service.dart";
import "../../services/storage_service.dart";
import "../../widgets/fluent_widgets.dart";

class RoleDashboardScreen extends StatefulWidget {
  const RoleDashboardScreen({
    required this.session,
    required this.authService,
    required this.dashboardService,
    required this.storageService,
    required this.onLogout,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final UserSession session;
  final AuthService authService;
  final DashboardService dashboardService;
  final StorageService storageService;
  final Future<void> Function() onLogout;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _LeastRatedDish {
  const _LeastRatedDish({
    required this.item,
    required this.averageRating,
    required this.totalVotes,
  });

  final String item;
  final double averageRating;
  final int totalVotes;
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  static const List<String> _weekDays = <String>[
    "MON",
    "TUE",
    "WED",
    "THU",
    "FRI",
    "SAT",
    "SUN",
  ];

  bool _loading = true;
  String? _error;
  int _selectedNavIndex = 0;
  int _selectedMenuDayIndex = 0;

  List<MessMenu> _menus = <MessMenu>[];
  List<MessFeedbackItem> _messFeedbacks = <MessFeedbackItem>[];
  List<MessPollOptionItem> _pollOptions = <MessPollOptionItem>[];
  List<MessChangeRequestItem> _messChangeRequests = <MessChangeRequestItem>[];
  List<ComplaintItem> _complaints = <ComplaintItem>[];
  List<LaundrySchedule> _schedules = <LaundrySchedule>[];
  List<CatererItem> _caterers = <CatererItem>[];
  List<AppNotificationItem> _notifications = <AppNotificationItem>[];

  UserProfileItem? _profile;
  String? _studentQrPayload;

  final _studentIdController = TextEditingController();
  final _complaintController = TextEditingController();
  final _complaintCategoryController = TextEditingController(text: "PLUMBING");

  final _feedbackCommentController = TextEditingController();
  final _feedbackReplyController = TextEditingController();
    final selectedCode = _weekDays[_selectedMenuDayIndex];
    final selectedMenu = _menuForDay(selectedCode);
    final feedbackItems = _menuItemsForSelection(_selectedFeedbackDay, _selectedFeedbackSlot);
    final leastRated = _leastRatedDishes();
    final pollIsActive = _pollOptions.isNotEmpty;
    final pendingRequests = _messChangeRequests.where((request) => request.status == "PENDING").toList();
    final month = DateFormat("yyyy-MM").format(DateTime.now());

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Weekly Menu",
            subtitle: "Select a day to view breakfast, lunch, snacks, and dinner",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List<Widget>.generate(_weekDays.length, (index) {
                      final dayCode = _weekDays[index];
                      return Padding(
                        padding: EdgeInsets.only(right: index == _weekDays.length - 1 ? 0 : 8),
                        child: ChoiceChip(
                          label: Text(_humanDay(dayCode)),
                          selected: _selectedMenuDayIndex == index,
                          onSelected: (_) {
                            setState(() {
                              _selectedMenuDayIndex = index;
                            });
                          },
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _humanDay(selectedCode),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _mealTile("Breakfast", selectedMenu?.breakfast ?? ""),
                const SizedBox(height: 12),
                _mealTile("Lunch", selectedMenu?.lunch ?? ""),
                const SizedBox(height: 12),
                _mealTile("Snacks", selectedMenu?.snacks ?? ""),
                const SizedBox(height: 12),
                _mealTile("Dinner", selectedMenu?.dinner ?? ""),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Caterers",
            subtitle: "Block-wise mapping",
            child: Column(
              children: _caterers
                  .map((c) => ListTile(title: Text(c.name), subtitle: Text("Block ${c.blockName} | ${c.mealTypes}")))
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Feedback And Polls",
            subtitle: "$month student actions",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedFeedbackDay,
                  decoration: const InputDecoration(labelText: "Day", border: OutlineInputBorder()),
                  items: _weekDays
                      .map((day) => DropdownMenuItem<String>(value: day, child: Text(_humanDay(day))))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedFeedbackDay = value;
                      _syncFeedbackSelectionWithMenu();
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFeedbackSlot,
                  decoration: const InputDecoration(labelText: "Time Of Day", border: OutlineInputBorder()),
                  items: const ["breakfast", "lunch", "snacks", "dinner"]
                      .map((slot) => DropdownMenuItem<String>(
                            value: slot,
                            child: Text(slot[0].toUpperCase() + slot.substring(1)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedFeedbackSlot = value;
                      _syncFeedbackSelectionWithMenu();
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFeedbackItem.isEmpty ? null : _selectedFeedbackItem,
                  decoration: const InputDecoration(labelText: "Menu Item", border: OutlineInputBorder()),
                  items: feedbackItems
                      .map((item) => DropdownMenuItem<String>(value: item, child: Text(item)))
                      .toList(),
                  onChanged: feedbackItems.isEmpty
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedFeedbackItem = value;
                          });
                        },
                ),
                const SizedBox(height: 8),
                Row(
                  children: List<Widget>.generate(5, (index) {
                    final star = index + 1;
                    return IconButton(
                      onPressed: () {
                        setState(() {
                          _selectedFeedbackRating = star;
                        });
                      },
                      icon: Icon(
                        _selectedFeedbackRating >= star ? Icons.star_rounded : Icons.star_border_rounded,
                        color: const Color(0xFFFFB900),
                      ),
                    );
                  }),
                ),
                FluentTextField(
                  controller: _feedbackCommentController,
                  labelText: "Comments (optional)",
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _isStudent ? _submitFeedback : null,
                  icon: const Icon(FluentIcons.comment_multiple_24_regular),
                  label: const Text("Submit Rating"),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: pollIsActive ? _openPollModal : null,
                  child: Text(pollIsActive ? "Open Active Poll" : "Poll Not Active Yet"),
                ),
                const SizedBox(height: 12),
                Text(
                  "Least Rated Dishes",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (leastRated.isEmpty)
                  const Text("No rating data yet")
                else
                  ...leastRated.map(
                    (dish) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(dish.item),
                        subtitle: Text("Avg: ${dish.averageRating.toStringAsFixed(2)} • Votes: ${dish.totalVotes}"),
                      ),
                    ),
                  ),
                if (_isAdmin || _isMessManager) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPollType,
                    decoration: const InputDecoration(labelText: "Create Poll Option", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: "ADD", child: Text("Add New Item (Like)")),
                      DropdownMenuItem(value: "REMOVE", child: Text("Remove Existing (Dislike)")),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedPollType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  FluentTextField(
                    controller: _pollCreateItemController,
                    labelText: "Item Name",
                    hintText: "Example: Paneer Fried Rice",
                  ),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _createPollOption, child: const Text("Save Poll Option")),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Mess Change",
            subtitle: "Students can request and managers can review",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isStudent) ...[
                  FluentTextField(controller: _messChangeController, labelText: "Requested mess"),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _requestMessChange, child: const Text("Request Mess Change")),
                ],
                if (_isMessManager) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Pending Requests",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (pendingRequests.isEmpty)
                    const Text("No pending mess change requests")
                  else
                    ...pendingRequests.map(
                      (request) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(request.requestedMess),
                          subtitle: Text("Student: ${request.studentId ?? "N/A"} • Month: ${request.month}"),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              OutlinedButton(
                                onPressed: () => _setMessChangeStatus(requestId: request.id, approve: false),
                                child: const Text("Reject"),
                              ),
                              FilledButton(
                                onPressed: () => _setMessChangeStatus(requestId: request.id, approve: true),
                                child: const Text("Approve"),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_messFeedbacks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    Text(
                      "Latest Feedback",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ..._messFeedbacks.take(5).map(
                      (feedback) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${feedback.menuItem} • ${feedback.rating}/5", style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text("${_humanDay(feedback.weekDay)} • ${feedback.mealTime}"),
                              if (feedback.comment.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(feedback.comment),
                              ],
                              if (feedback.managerReply.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text("Reply: ${feedback.managerReply}"),
                              ],
                              const SizedBox(height: 8),
                              FluentTextField(controller: _feedbackReplyController, labelText: "Reply"),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: () => _replyToFeedback(feedback.id),
                                child: const Text("Submit Reply"),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted || scannedRaw == null) return;

    final payload = _extractLaundryPayload(scannedRaw);
    if (payload == null) {
      _toast("QR must include student_id and qr_token");
      return;
    }

    setState(() {
      _scanStudentIdController.text = payload["student_id"]!;
      _scanTokenController.text = payload["qr_token"]!;
    });
    _toast("QR scanned. Verify action and process.");
  }

  Future<void> _votePoll() async {
    _toast("Select an option from the poll list to vote");
  }

  Future<void> _votePollOption(int optionId) async {
    final studentId = _profile?.studentId;
    if (!_isStudent || studentId == null) {
      _toast("Only student accounts can vote in polls");
      return;
    }

    try {
      await widget.dashboardService.votePoll(
        token: widget.session.accessToken,
        studentId: studentId,
        optionId: optionId,
      );
      _toast("Vote submitted");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _createPollOption() async {
    if (!_isAdmin && !_isMessManager) {
      _toast("Only admins and mess managers can create polls");
      return;
    }

    final itemName = _pollCreateItemController.text.trim();
    if (itemName.isEmpty) {
      _toast("Poll item name is required");
      return;
    }

    try {
      await widget.dashboardService.createPollOption(
        token: widget.session.accessToken,
        month: DateFormat("yyyy-MM").format(DateTime.now()),
        itemName: itemName,
        pollType: _selectedPollType,
      );
      _pollCreateItemController.clear();
      _toast("Poll option created");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _requestMessChange() async {
    final studentId = _profile?.studentId;
    if (!_isStudent || studentId == null) {
      _toast("Only student accounts can request mess changes");
      return;
    }
    if (_messChangeController.text.trim().isEmpty) {
      _toast("Requested mess is required");
      return;
    }
    try {
      await widget.dashboardService.requestMessChange(
        token: widget.session.accessToken,
        studentId: studentId,
        requestedMess: _messChangeController.text.trim(),
        month: DateFormat("yyyy-MM").format(DateTime.now()),
      );
      _messChangeController.clear();
      _toast("Mess change request submitted");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _setMessChangeStatus({
    required int requestId,
    required bool approve,
  }) async {
    if (!_isMessManager) {
      _toast("Only mess managers can update mess change requests");
      return;
    }

    try {
      if (approve) {
        await widget.dashboardService.approveMessChange(
          token: widget.session.accessToken,
          requestId: requestId,
        );
      } else {
        await widget.dashboardService.rejectMessChange(
          token: widget.session.accessToken,
          requestId: requestId,
        );
      }
      _toast(approve ? "Request approved" : "Request rejected");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _humanDay(String dayCode) {
    switch (dayCode.toUpperCase()) {
      case "MON":
        return "Monday";
      case "TUE":
        return "Tuesday";
      case "WED":
        return "Wednesday";
      case "THU":
        return "Thursday";
      case "FRI":
        return "Friday";
      case "SAT":
        return "Saturday";
      case "SUN":
        return "Sunday";
      default:
        return dayCode;
    }
  }

  MessMenu? _menuForDay(String dayCode) {
    for (final menu in _menus) {
      if (menu.weekDay.trim().toUpperCase() == dayCode) {
        return menu;
      }
    }
    return null;
  }

  Widget _mediaPreview(ComplaintItem complaint) {
    if (complaint.mediaUrl.isEmpty || complaint.mediaType == "TEXT") {
      return const SizedBox.shrink();
    }

    if (complaint.mediaType == "IMAGE") {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          complaint.mediaUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text("Image preview unavailable"),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Video attached",
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SelectableText(complaint.mediaUrl),
        ],
      ),
    );
  }

  Future<void> _openComplaintDetails(ComplaintItem complaint) async {
    final replyController = TextEditingController();
    ComplaintItem current = complaint;
    bool busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> runAction(
              Future<ComplaintItem> Function() action,
              String successMessage,
            ) async {
              setModalState(() {
                busy = true;
              });
              try {
                final updated = await action();
                current = updated;
                _replaceComplaint(updated);
                if (!mounted) return;
                _toast(successMessage);
              } catch (e) {
                _toast(e.toString());
              } finally {
                if (ctx.mounted) {
                  setModalState(() {
                    busy = false;
                  });
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        current.category,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Status: ${current.statusLabel.isEmpty ? current.status : current.statusLabel}",
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "By: ${current.authorName.isNotEmpty ? current.authorName : current.studentName}",
                      ),
                      const SizedBox(height: 10),
                      Text(current.text),
                      if (current.mediaUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _mediaPreview(current),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => runAction(
                                      () =>
                                          widget.dashboardService.voteComplaint(
                                        token: widget.session.accessToken,
                                        complaintId: current.id,
                                        direction: "up",
                                      ),
                                      "Upvoted thread",
                                    ),
                            icon: const Icon(FluentIcons.thumb_like_24_regular),
                            label: Text("${current.upvotes} Upvotes"),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => runAction(
                                      () =>
                                          widget.dashboardService.voteComplaint(
                                        token: widget.session.accessToken,
                                        complaintId: current.id,
                                        direction: "down",
                                      ),
                                      "Downvoted thread",
                                    ),
                            icon: const Icon(
                                FluentIcons.thumb_dislike_24_regular),
                            label: Text("${current.downvotes} Downvotes"),
                          ),
                        ],
                      ),
                      if (current.canManage) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: current.status,
                          decoration: const InputDecoration(
                            labelText: "Change Status",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: "OPEN", child: Text("Open")),
                            DropdownMenuItem(
                                value: "IN_PROGRESS",
                                child: Text("In Progress")),
                            DropdownMenuItem(
                                value: "CLOSED", child: Text("Closed")),
                          ],
                          onChanged: busy
                              ? null
                              : (value) {
                                  if (value == null ||
                                      value == current.status) {
                                    return;
                                  }
                                  runAction(
                                    () => widget.dashboardService
                                        .setComplaintStatus(
                                      token: widget.session.accessToken,
                                      complaintId: current.id,
                                      status: value,
                                    ),
                                    "Status updated",
                                  );
                                },
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        "Comments (${current.replies.length})",
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (current.replies.isEmpty)
                        const Text("No comments yet.")
                      else
                        ...current.replies.map(
                          (reply) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reply.authorName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(reply.text),
                                if (reply.createdAt != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat("dd MMM yyyy, hh:mm a")
                                        .format(reply.createdAt!),
                                    style: Theme.of(ctx).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      FluentTextField(
                        controller: replyController,
                        labelText: "Add a comment",
                        minLines: 2,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                final text = replyController.text.trim();
                                if (text.isEmpty) {
                                  _toast("Comment cannot be empty");
                                  return;
                                }
                                runAction(
                                  () =>
                                      widget.dashboardService.addComplaintReply(
                                    token: widget.session.accessToken,
                                    complaintId: current.id,
                                    text: text,
                                  ),
                                  "Comment posted",
                                );
                                replyController.clear();
                              },
                        icon: const Icon(FluentIcons.send_24_regular),
                        label: const Text("Post Comment"),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    replyController.dispose();
  }

  void _showProfileSheet() {
    final profile = _profile;
    final student = profile?.student;
    final detailRows = <MapEntry<String, String>>[
      MapEntry(
          "Name",
          profile?.fullName.isNotEmpty == true
              ? profile!.fullName
              : widget.session.username),
      MapEntry(
          "Email",
          profile?.email.isNotEmpty == true
              ? profile!.email
              : widget.session.email),
      MapEntry(
          "Role",
          profile?.role.isNotEmpty == true
              ? profile!.role
              : widget.session.role),
      MapEntry("Registration Number", student?.rollNo ?? "N/A"),
      MapEntry("Hostel Block", student?.blockName ?? "N/A"),
      MapEntry("Room Number", student?.roomNo ?? "N/A"),
      MapEntry("Mess Allotment", student?.messAllotment ?? "N/A"),
      MapEntry("Points Balance", student?.pointsBalance ?? "N/A"),
      MapEntry(
          "Phone",
          profile == null
              ? "N/A"
              : "${profile.phoneCountryCode} ${profile.phoneNumber}".trim()),
      MapEntry("Department",
          profile?.department.isNotEmpty == true ? profile!.department : "N/A"),
      MapEntry("Job Title",
          profile?.jobTitle.isNotEmpty == true ? profile!.jobTitle : "N/A"),
      MapEntry(
          "Assigned Mess",
          profile?.assignedMessName.isNotEmpty == true
              ? profile!.assignedMessName
              : "N/A"),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Profile",
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detailRows
                      .map(
                        (entry) => Container(
                          width: MediaQuery.of(ctx).size.width > 500
                              ? (MediaQuery.of(ctx).size.width - 56) / 2
                              : double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.value.isEmpty ? "N/A" : entry.value,
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ThemeMode>(
                  initialValue: widget.themeMode,
                  decoration: const InputDecoration(
                    labelText: "Theme",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text("System"),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text("Light"),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text("Dark"),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    widget.onThemeModeChanged(value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          final changed =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ChangePasswordScreen(
                                authService: widget.authService,
                                token: widget.session.accessToken,
                              ),
                            ),
                          );
                          if (changed == true && mounted) {
                            _toast("Password updated successfully");
                          }
                        },
                        icon: const Icon(FluentIcons.key_24_regular),
                        label: const Text("Change Password"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await widget.onLogout();
                        },
                        icon: const Icon(FluentIcons.sign_out_24_regular),
                        label: const Text("Logout"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _communityTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Community Threads",
            subtitle: _isWarden
                ? "Warden moderation enabled"
                : "Student community complaints",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FluentTextField(
                  controller: _studentIdController,
                  labelText: "Student ID",
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _complaintCategoryController,
                  labelText: "Category",
                  hintText: "PLUMBING/ELECTRICAL/CIVIL/WATER/AC/OTHER",
                ),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _complaintController,
                  labelText: "Complaint text",
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (_isStudent || _isWarden || _isAdmin)
                      ? _submitComplaint
                      : null,
                  icon: const Icon(FluentIcons.send_24_regular),
                  label: const Text("Post Complaint"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ..._complaints.map(
            (c) => Card(
              child: ListTile(
                onTap: () => _openComplaintDetails(c),
                leading: Icon(
                  c.status == "OPEN"
                      ? FluentIcons.error_circle_24_regular
                      : FluentIcons.checkmark_circle_24_filled,
                  color: c.status == "OPEN" ? Colors.orange : Colors.green,
                ),
                title: Text(
                    "${c.category} - ${c.statusLabel.isEmpty ? c.status : c.statusLabel}"),
                subtitle: Text(
                  "${c.text}\n${c.upvotes} upvotes, ${c.downvotes} downvotes, ${c.replies.length} comments",
                ),
                isThreeLine: true,
                trailing: const Icon(FluentIcons.chevron_right_20_regular),
              ),
            ),
          ),
          if (_complaints.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("No complaints available"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _homeTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Top Notifications",
            subtitle: "Replies, mess meetings, and hostel alerts",
            child: Column(
              children: _notifications.isEmpty
                  ? const [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("No notifications available right now."),
                      ),
                    ]
                  : _notifications
                      .take(6)
                      .map(
                        (n) => ListTile(
                          leading: Icon(
                            n.level == "URGENT"
                                ? FluentIcons.warning_24_filled
                                : (n.level == "WARNING"
                                    ? FluentIcons.warning_24_regular
                                    : FluentIcons.info_24_regular),
                            color: n.level == "URGENT"
                                ? const Color(0xFFE81123)
                                : (n.level == "WARNING"
                                    ? const Color(0xFFFFB900)
                                    : Theme.of(context).colorScheme.primary),
                          ),
                          title: Text(
                            n.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(n.message),
                        ),
                      )
                      .toList(),
            ),
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 10),
            _sectionCard(
              title: "Admin Actions",
              subtitle: "Notification publishing is available in Django panel",
              child: const Text(
                "Open web notification panel to publish alerts for both website and app.",
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mealTile(String heading, String items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(items.isEmpty ? "Not updated" : items),
        ],
      ),
    );
  }

  Widget _messTab() {
    final selectedCode = _weekDays[_selectedMenuDayIndex];
    final selectedMenu = _menuForDay(selectedCode);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Weekly Menu",
            subtitle: "Swipe horizontally to switch between Monday and Sunday",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List<Widget>.generate(_weekDays.length, (index) {
                      final dayCode = _weekDays[index];
                      final selected = _selectedMenuDayIndex == index;
                      return Padding(
                        padding: EdgeInsets.only(
                            right: index == _weekDays.length - 1 ? 0 : 8),
                        child: ChoiceChip(
                          label: Text(_humanDay(dayCode)),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _selectedMenuDayIndex = index;
                            });
                          },
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _humanDay(selectedCode),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                _mealTile("Breakfast", selectedMenu?.breakfast ?? ""),
                const SizedBox(height: 12),
                _mealTile("Lunch", selectedMenu?.lunch ?? ""),
                const SizedBox(height: 12),
                _mealTile("Snacks", selectedMenu?.snacks ?? ""),
                const SizedBox(height: 12),
                _mealTile("Dinner", selectedMenu?.dinner ?? ""),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Caterers",
            subtitle: "Block-wise mapping",
            child: Column(
              children: _caterers
                  .map(
                    (c) => ListTile(
                      title: Text(c.name),
                      subtitle: Text("Block ${c.blockName} | ${c.mealTypes}"),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Mess Feedback",
            subtitle: "Students can submit item-wise feedback",
            child: Column(
              children: [
                FluentTextField(
                  controller: _feedbackMenuItemController,
                  labelText: "Menu item",
                ),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _feedbackRatingController,
                  labelText: "Rating (1-5)",
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _feedbackCommentController,
                  labelText: "Comment",
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (_isStudent || _isAdmin) ? _submitFeedback : null,
                  icon: const Icon(FluentIcons.comment_multiple_24_regular),
                  label: const Text("Submit Feedback"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Poll + Mess Change",
            subtitle: "Vote next month menu item and request mess change",
            child: Column(
              children: [
                FluentTextField(
                  controller: _pollOptionController,
                  labelText: "Poll option ID",
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_isStudent || _isAdmin) ? _votePoll : null,
                  child: const Text("Vote Poll"),
                ),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _messChangeController,
                  labelText: "Requested mess",
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed:
                      (_isStudent || _isAdmin) ? _requestMessChange : null,
                  child: const Text("Request Mess Change"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _laundryTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Laundry Schedule",
            subtitle: "Submission orange, collection green",
            child: Column(
              children: _schedules
                  .map(
                    (s) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: s.collection
                              ? Colors.green
                              : (s.submission
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.primary),
                          child: Text(s.day.substring(0, 1)),
                        ),
                        title: Text("Schedule #${s.id} - ${s.day}"),
                        subtitle: Text(
                          "Submission: ${s.submission} | Collection: ${s.collection}",
                        ),
                        trailing: _isLaundryPerson
                            ? Wrap(
                                spacing: 6,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _markSubmission(s.id),
                                    child: const Text("Submit"),
                                  ),
                                  FilledButton(
                                    onPressed: () => _markCollection(s.id),
                                    child: const Text("Collect"),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Student QR",
            subtitle: "Your QR payload is always visible here",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_studentQrPayload == null)
                  const Text("No student QR data available for this account.")
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: SelectableText(_studentQrPayload!),
                  ),
                if (_isLaundryPerson || _isAdmin) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openLaundryQrScanner,
                    icon: const Icon(FluentIcons.scan_camera_24_regular),
                    label: const Text("Scan QR With Camera"),
                  ),
                  const SizedBox(height: 8),
                  FluentTextField(
                    controller: _scanStudentIdController,
                    labelText: "Scan Student ID",
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FluentTextField(
                    controller: _scanTokenController,
                    labelText: "Scan QR Token",
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _scanEventType,
                    decoration: const InputDecoration(
                      labelText: "Scan Action",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "SUBMISSION", child: Text("Submission")),
                      DropdownMenuItem(
                          value: "COLLECTION", child: Text("Collection")),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _scanEventType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _scanLaundryByToken,
                    icon: const Icon(FluentIcons.qr_code_24_regular),
                    label: const Text("Process QR Scan"),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard(
          title: "Create Block",
          subtitle: "You can also manage this in Django admin",
          child: Column(
            children: [
              FluentTextField(
                controller: _blockNameController,
                labelText: "Block name",
                hintText: "A/B/C/D1/D2/E",
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _createBlock,
                child: const Text("Create Block"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: "Create Caterer",
          subtitle: "Enter block ID from backend",
          child: Column(
            children: [
              FluentTextField(
                controller: _catererNameController,
                labelText: "Caterer name",
              ),
              const SizedBox(height: 8),
              FluentTextField(
                controller: _catererMealsController,
                labelText: "Meal types",
              ),
              const SizedBox(height: 8),
              FluentTextField(
                controller: _catererBlockIdController,
                labelText: "Block ID",
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _createCaterer,
                child: const Text("Create Caterer"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: "Create / Update Menu",
          subtitle: "Weekly day-based menu",
          child: Column(
            children: [
              FluentTextField(
                controller: _menuDayController,
                labelText: "Week day code",
                hintText: "MON, TUE, WED, THU, FRI, SAT, SUN",
              ),
              const SizedBox(height: 8),
              FluentTextField(
                controller: _breakfastController,
                labelText: "Breakfast",
              ),
              const SizedBox(height: 8),
              FluentTextField(
                controller: _lunchController,
                labelText: "Lunch",
              ),
              const SizedBox(height: 8),
              FluentTextField(
                controller: _snacksController,
                labelText: "Snacks",
              ),
              const SizedBox(height: 8),
              FluentTextField(
                controller: _dinnerController,
                labelText: "Dinner",
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _createMenu,
                child: const Text("Save Menu"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeTab(),
      _communityTab(),
      if (!_isLaundryPerson) _messTab(),
      _laundryTab(),
      if (_isAdmin) _adminTab(),
    ];
    final selectedIndex = _selectedNavIndex.clamp(0, pages.length - 1);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          onPressed: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _selectedNavIndex = 0;
              });
            }
          },
          icon: const Icon(FluentIcons.arrow_left_24_regular),
          tooltip: "Back",
        ),
        title: Text(
          "HostelCC",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(FluentIcons.arrow_sync_24_regular),
            tooltip: "Refresh",
          ),
          IconButton(
            onPressed: _showProfileSheet,
            icon: const Icon(FluentIcons.person_circle_24_filled),
            tooltip: "Profile",
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
            : pages[selectedIndex],
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xCC101828)
                  : const Color(0xD9FFFFFF),
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white12
                      : Colors.black12,
                ),
              ),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: Colors.transparent,
                elevation: 0,
                indicatorColor: Colors.transparent,
                labelTextStyle:
                    WidgetStateProperty.resolveWith<TextStyle>((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).textTheme.bodySmall?.color,
                  );
                }),
                iconTheme:
                    WidgetStateProperty.resolveWith<IconThemeData>((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).iconTheme.color,
                    size: 24,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: selectedIndex,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(FluentIcons.home_24_regular),
                    selectedIcon: Icon(FluentIcons.home_24_filled),
                    label: "Home",
                  ),
                  const NavigationDestination(
                    icon: Icon(FluentIcons.chat_bubbles_question_24_regular),
                    selectedIcon:
                        Icon(FluentIcons.chat_bubbles_question_24_filled),
                    label: "Community",
                  ),
                  if (!_isLaundryPerson)
                    const NavigationDestination(
                      icon: Icon(FluentIcons.food_24_regular),
                      selectedIcon: Icon(FluentIcons.food_24_filled),
                      label: "Mess",
                    ),
                  const NavigationDestination(
                    icon: Icon(FluentIcons.water_24_regular),
                    selectedIcon: Icon(FluentIcons.water_24_filled),
                    label: "Laundry",
                  ),
                  if (_isAdmin)
                    const NavigationDestination(
                      icon: Icon(FluentIcons.settings_24_regular),
                      selectedIcon: Icon(FluentIcons.settings_24_filled),
                      label: "Admin",
                    ),
                ],
                onDestinationSelected: (index) {
                  setState(() {
                    _selectedNavIndex = index;
                  });
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
