import "dart:async";
import "dart:convert";
import "dart:typed_data";
import "dart:ui";

import "package:fluentui_system_icons/fluentui_system_icons.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:screen_brightness/screen_brightness.dart";
import "package:syncfusion_flutter_pdfviewer/pdfviewer.dart";

import "../../models/app_models.dart";
import "../../models/user_session.dart";
import "../../screens/auth/change_password_screen.dart";
import "../../screens/dashboard/new_complaint_screen.dart";
import "../../services/auth_service.dart";
import "../../services/dashboard_service.dart";
import "../../services/notification_attachment_cache.dart";
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

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  static const List<String> _messTypes = <String>[
    "VEG",
    "NON_VEG",
    "SPECIAL",
    "FOODPARK",
  ];

  static const List<MapEntry<String, String>> _weekDayOptions =
      <MapEntry<String, String>>[
    MapEntry<String, String>("MON", "Monday"),
    MapEntry<String, String>("TUE", "Tuesday"),
    MapEntry<String, String>("WED", "Wednesday"),
    MapEntry<String, String>("THU", "Thursday"),
    MapEntry<String, String>("FRI", "Friday"),
    MapEntry<String, String>("SAT", "Saturday"),
    MapEntry<String, String>("SUN", "Sunday"),
  ];

  static const List<MapEntry<String, String>> _mealTimeOptions =
      <MapEntry<String, String>>[
    MapEntry<String, String>("BREAKFAST", "Breakfast"),
    MapEntry<String, String>("LUNCH", "Lunch"),
    MapEntry<String, String>("SNACKS", "Snacks"),
    MapEntry<String, String>("DINNER", "Dinner"),
  ];

  static const List<MapEntry<String, String>> _pollTypeOptions =
      <MapEntry<String, String>>[
    MapEntry<String, String>("ADD", "Add New Item (Like)"),
    MapEntry<String, String>("REMOVE", "Remove Existing (Dislike)"),
  ];

  static const List<MapEntry<String, String>> _categoryOptions =
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

  static const List<MapEntry<String, String>> _statusFilters =
      <MapEntry<String, String>>[
    MapEntry<String, String>("", "All statuses"),
    MapEntry<String, String>("OPEN", "Open"),
    MapEntry<String, String>("IN_PROGRESS", "In Progress"),
    MapEntry<String, String>("CLOSED", "Closed"),
  ];

  static const List<MapEntry<String, String>> _sortOptions =
      <MapEntry<String, String>>[
    MapEntry<String, String>("newest", "Newest"),
    MapEntry<String, String>("oldest", "Oldest"),
    MapEntry<String, String>("upvotes", "Most Upvoted"),
  ];

  static const Set<String> _statusValues = <String>{
    "OPEN",
    "IN_PROGRESS",
    "CLOSED",
  };
  static const Color _activeVoteColor = Color(0xFF0B3D91);
  static const Color _activeNavColor = Color(0xFF0B3D91);
  static const double _tabBottomSafePadding = 132;

  bool _loading = true;
  String? _error;

  int _selectedNavIndex = 0;
  String _selectedMenuType = _messTypes.first;

  String _communityQuery = "";
  String _communityCategoryFilter = "";
  String _communityStatusFilter = "";
  String _communitySort = "newest";

  final TextEditingController _communitySearchController =
      TextEditingController();
  final TextEditingController _rateCommentController = TextEditingController();
  final TextEditingController _createPollItemController =
      TextEditingController();
  final NotificationAttachmentCache _notificationAttachmentCache =
      NotificationAttachmentCache();

  List<MessMenu> _menus = <MessMenu>[];
  List<ComplaintItem> _complaints = <ComplaintItem>[];
  List<LaundrySchedule> _schedules = <LaundrySchedule>[];
  String _laundryQrText = "";
  List<CatererItem> _caterers = <CatererItem>[];
  List<MessFeedbackItem> _feedbacks = <MessFeedbackItem>[];
  List<MessPollOptionItem> _pollOptions = <MessPollOptionItem>[];
  List<LeastRatedMessItem> _leastRatedItems = <LeastRatedMessItem>[];
  List<AppNotificationItem> _notifications = <AppNotificationItem>[];
  UserProfileItem? _profile;
  final Set<int> _communityVoteBusyIds = <int>{};
  final Set<int> _pollVoteBusyOptionIds = <int>{};

  String _selectedRateDay = "";
  String _selectedMealTime = "";
  String _selectedMenuItem = "";
  int _selectedRating = 0;
  String _createPollType = "ADD";
  bool _messActionBusy = false;

  bool get _isStudent => widget.session.role == "STUDENT";
  bool get _isWarden => widget.session.role == "WARDEN";
  bool get _isAdmin => widget.session.role == "ADMIN";
  bool get _isMessManager => widget.session.role == "MESS_MANAGER";
  bool get _isLaundryPerson => widget.session.role == "LAUNDRY_PERSON";
  bool get _canViewMessFeedback => _isMessManager || _isWarden;
  bool get _canManageMessPolls => _isMessManager || _isAdmin;

  bool get _canCreateComplaint => _isStudent || _isWarden || _isAdmin;

  bool get _hasCommunityFilters =>
      _communityQuery.isNotEmpty ||
      _communityCategoryFilter.isNotEmpty ||
      _communityStatusFilter.isNotEmpty ||
      _communitySort != "newest";

  String get _currentMonth => DateFormat("yyyy-MM").format(DateTime.now());

  String get _currentWeekDayCode {
    const dayCodes = <String>["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
    final dayIndex = DateTime.now().weekday - 1;
    if (dayIndex < 0 || dayIndex >= dayCodes.length) {
      return dayCodes.first;
    }
    return dayCodes[dayIndex];
  }

  String _weekDayLabel(String code) {
    final normalized = code.trim().toUpperCase();
    for (final entry in _weekDayOptions) {
      if (entry.key == normalized) {
        return entry.value;
      }
    }
    return normalized.isEmpty ? "-" : normalized;
  }

  String _mealTimeLabel(String code) {
    final normalized = code.trim().toUpperCase();
    for (final entry in _mealTimeOptions) {
      if (entry.key == normalized) {
        return entry.value;
      }
    }
    return normalized.isEmpty ? "-" : _formatEnumLabel(normalized);
  }

  MessMenu? _menuForDay(String dayCode) {
    final normalized = dayCode.trim().toUpperCase();
    for (final menu in _menus) {
      if (menu.weekDay.trim().toUpperCase() == normalized) {
        return menu;
      }
    }
    return null;
  }

  List<String> _splitMenuItems(String raw) {
    return raw
        .split(",")
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _menuItemsForMealTime(MessMenu menu, String mealTime) {
    switch (mealTime.trim().toUpperCase()) {
      case "BREAKFAST":
        return _splitMenuItems(menu.breakfast);
      case "LUNCH":
        return _splitMenuItems(menu.lunch);
      case "SNACKS":
        return _splitMenuItems(menu.snacks);
      case "DINNER":
        return _splitMenuItems(menu.dinner);
      default:
        return <String>[];
    }
  }

  List<String> _availableRateDays() {
    final configuredDays = _menus
        .map((menu) => menu.weekDay.trim().toUpperCase())
        .where((day) => day.isNotEmpty)
        .toSet();

    return _weekDayOptions
        .map((entry) => entry.key)
        .where(configuredDays.contains)
        .toList(growable: false);
  }

  List<String> _availableMenuItemsForSelection() {
    final selectedMenu = _menuForDay(_selectedRateDay);
    if (selectedMenu == null || _selectedMealTime.isEmpty) {
      return <String>[];
    }
    return _menuItemsForMealTime(selectedMenu, _selectedMealTime);
  }

  void _syncRateSelectorsWithMenus() {
    final availableDays = _availableRateDays();
    if (availableDays.isEmpty) {
      _selectedRateDay = "";
      _selectedMealTime = "";
      _selectedMenuItem = "";
      return;
    }

    if (!availableDays.contains(_selectedRateDay)) {
      _selectedRateDay = availableDays.contains(_currentWeekDayCode)
          ? _currentWeekDayCode
          : availableDays.first;
    }

    final selectedMenu = _menuForDay(_selectedRateDay);
    if (selectedMenu == null) {
      _selectedMealTime = "";
      _selectedMenuItem = "";
      return;
    }

    final mealCodes =
        _mealTimeOptions.map((entry) => entry.key).toList(growable: false);
    if (!mealCodes.contains(_selectedMealTime)) {
      _selectedMealTime = mealCodes.first;
    }

    final items = _availableMenuItemsForSelection();
    if (items.isEmpty) {
      _selectedMenuItem = "";
      return;
    }

    if (!items.contains(_selectedMenuItem)) {
      _selectedMenuItem = items.first;
    }
  }

  List<MessPollOptionItem> _pollOptionsForType(String pollType) {
    final normalizedType = pollType.trim().toUpperCase();
    final month = _currentMonth;

    return _pollOptions
        .where(
          (option) =>
              option.month.trim() == month &&
              option.pollType.trim().toUpperCase() == normalizedType,
        )
        .toList(growable: false);
  }

  bool get _isPollActive {
    return _pollOptionsForType("ADD").isNotEmpty ||
        _pollOptionsForType("REMOVE").isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _communitySearchController.dispose();
    _rateCommentController.dispose();
    _createPollItemController.dispose();
    _notificationAttachmentCache.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = widget.session.accessToken;

      final results = await Future.wait<dynamic>([
        _isStudent
            ? widget.dashboardService.getMenus(token)
            : widget.dashboardService
                .getMenus(token, messType: _selectedMenuType),
        widget.dashboardService.getComplaints(
          token,
          query: _communityQuery,
          category: _communityCategoryFilter,
          status: _communityStatusFilter,
          sort: _communitySort,
        ),
        _isMessManager
            ? Future<List<LaundrySchedule>>.value(<LaundrySchedule>[])
            : widget.dashboardService.getSchedules(token),
        widget.dashboardService.getCaterers(token),
        _canViewMessFeedback
            ? widget.dashboardService.getMessFeedbacks(token)
            : Future<List<MessFeedbackItem>>.value(<MessFeedbackItem>[]),
        widget.dashboardService.getPollOptions(token, month: _currentMonth),
        widget.dashboardService.getLeastRatedMessItems(token),
        widget.dashboardService.getNotifications(token),
        widget.dashboardService.getMyProfile(token),
      ]);

      final schedules = results[2] as List<LaundrySchedule>;
      var laundryQrText = "";
      if (_isStudent && schedules.isNotEmpty && schedules.first.studentId > 0) {
        try {
          final qrPayload = await widget.dashboardService.getLaundryQr(
            token: token,
            studentId: schedules.first.studentId,
          );
          laundryQrText = (qrPayload["qr_text"] ?? "").toString().trim();
        } catch (_) {
          laundryQrText = "";
        }
      }

      final profile = results[8] as UserProfileItem;
      final notifications = results[7] as List<AppNotificationItem>;
      await widget.storageService
          .saveCachedProfile(jsonEncode(profile.toJson()));

      if (!mounted) {
        return;
      }

      setState(() {
        _menus = results[0] as List<MessMenu>;
        _syncRateSelectorsWithMenus();
        _complaints = results[1] as List<ComplaintItem>;
        _schedules = schedules;
        _laundryQrText = laundryQrText;
        _caterers = results[3] as List<CatererItem>;
        _feedbacks = results[4] as List<MessFeedbackItem>;
        _pollOptions = results[5] as List<MessPollOptionItem>;
        _leastRatedItems = results[6] as List<LeastRatedMessItem>;
        _notifications = notifications;
        _profile = profile;
      });

      unawaited(_prefetchNotificationAttachments(notifications));
    } catch (e) {
      UserProfileItem? cachedProfile;
      try {
        final cached = await widget.storageService.readCachedProfile();
        if (cached != null && cached.trim().isNotEmpty) {
          cachedProfile = UserProfileItem.fromJson(
            jsonDecode(cached) as Map<String, dynamic>,
          );
        }
      } catch (_) {
        cachedProfile = null;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
        _laundryQrText = "";
        if (cachedProfile != null) {
          _profile = cachedProfile;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return "Unknown";
    }
    return DateFormat("dd MMM yyyy, hh:mm a").format(value);
  }

  String _displayValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? "-" : trimmed;
  }

  String _formatEnumLabel(String value) {
    final parts = value.trim().split("_").where((part) => part.isNotEmpty).map(
          (part) =>
              "${part[0].toUpperCase()}${part.substring(1).toLowerCase()}",
        );
    final combined = parts.join(" ");
    return combined.isEmpty ? "-" : combined;
  }

  IconData _notificationLevelIcon(String level) {
    switch (level.toUpperCase()) {
      case "URGENT":
        return FluentIcons.warning_24_filled;
      case "WARNING":
        return FluentIcons.warning_24_regular;
      default:
        return FluentIcons.info_24_regular;
    }
  }

  Map<String, String> _notificationRequestHeaders() {
    final token = widget.session.accessToken.trim();
    if (token.isEmpty) {
      return <String, String>{};
    }
    return <String, String>{"Authorization": "Bearer $token"};
  }

  Future<void> _prefetchNotificationAttachments(
    List<AppNotificationItem> notifications,
  ) async {
    if (notifications.isEmpty) {
      return;
    }

    final headers = _notificationRequestHeaders();
    final apiBaseUrl = widget.dashboardService.apiClient.baseUrl;

    for (final notification in notifications) {
      final attachmentUrl = notification.posterUrl.trim();
      if (attachmentUrl.isEmpty) {
        continue;
      }

      try {
        await _notificationAttachmentCache.ensureCached(
          notificationId: notification.id,
          attachmentUrl: attachmentUrl,
          apiBaseUrl: apiBaseUrl,
          headers: headers,
        );
      } catch (_) {
        // Ignore prefetch failures and allow manual retry in details screen.
      }
    }
  }

  Future<void> _openNotificationDetails(
      AppNotificationItem notification) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _NotificationDetailsScreen(
          notification: notification,
          authToken: widget.session.accessToken,
          apiBaseUrl: widget.dashboardService.apiClient.baseUrl,
          attachmentCache: _notificationAttachmentCache,
          formattedCreatedAt: _formatDate(notification.createdAt),
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _categoryLabel(String categoryCode) {
    for (final option in _categoryOptions) {
      if (option.key == categoryCode) {
        return option.value;
      }
    }
    return categoryCode;
  }

  String _authorLabel(ComplaintItem complaint) {
    if (complaint.authorName.isNotEmpty) {
      return complaint.authorName;
    }
    if (complaint.studentName.isNotEmpty) {
      return complaint.studentName;
    }
    return "Unknown";
  }

  Future<void> _applyCommunityFilters() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _communityQuery = _communitySearchController.text.trim();
    });
    await _loadData();
  }

  Future<void> _clearCommunityFilters() async {
    FocusScope.of(context).unfocus();
    _communitySearchController.clear();
    setState(() {
      _communityQuery = "";
      _communityCategoryFilter = "";
      _communityStatusFilter = "";
      _communitySort = "newest";
    });
    await _loadData();
  }

  Future<void> _openNewComplaintPage() async {
    if (!_canCreateComplaint) {
      _toast("Only students, wardens, and admins can post complaints.");
      return;
    }

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NewComplaintScreen(
          dashboardService: widget.dashboardService,
          accessToken: widget.session.accessToken,
        ),
      ),
    );

    if (created == true) {
      _toast("Complaint posted successfully.");
      await _loadData();
    }
  }

  void _replaceComplaint(ComplaintItem updated) {
    final index = _complaints.indexWhere((item) => item.id == updated.id);
    if (index < 0 || !mounted) {
      return;
    }
    setState(() {
      _complaints[index] = updated;
    });
  }

  bool _isCommunityVoteBusy(int complaintId) {
    return _communityVoteBusyIds.contains(complaintId);
  }

  Future<void> _voteFromCommunityCard({
    required ComplaintItem complaint,
    required String direction,
  }) async {
    if (_isCommunityVoteBusy(complaint.id)) {
      return;
    }

    setState(() {
      _communityVoteBusyIds.add(complaint.id);
    });

    try {
      final updated = await widget.dashboardService.voteComplaint(
        token: widget.session.accessToken,
        complaintId: complaint.id,
        direction: direction,
      );
      _replaceComplaint(updated);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _communityVoteBusyIds.remove(complaint.id);
        });
      } else {
        _communityVoteBusyIds.remove(complaint.id);
      }
    }
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
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Text("Image preview unavailable"),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SelectableText(complaint.mediaUrl),
    );
  }

  Future<void> _openComplaintDetails(ComplaintItem complaint) async {
    final replyController = TextEditingController();
    ComplaintItem current = complaint;
    bool busy = false;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
                _replaceComplaint(updated);

                if (ctx.mounted) {
                  setModalState(() {
                    current = updated;
                  });
                }

                if (successMessage.isNotEmpty) {
                  _toast(successMessage);
                }
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

            Future<void> runDelete() async {
              setModalState(() {
                busy = true;
              });

              try {
                await widget.dashboardService.deleteComplaint(
                  token: widget.session.accessToken,
                  complaintId: current.id,
                );

                if (mounted) {
                  setState(() {
                    _complaints.removeWhere((item) => item.id == current.id);
                  });
                }

                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }

                _toast("Post deleted.");
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

            final selectedStatus = _statusValues.contains(current.status)
                ? current.status
                : "OPEN";
            final mediaQuery = MediaQuery.of(ctx);
            final maxSheetHeight = mediaQuery.size.height * 0.75;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: mediaQuery.viewInsets.bottom + 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _categoryLabel(current.category),
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text("By ${_authorLabel(current)}"),
                        Text(
                          "Status: ${current.statusLabel.isEmpty ? current.status : current.statusLabel}",
                        ),
                        const SizedBox(height: 8),
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
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => runAction(
                                        () => widget.dashboardService
                                            .voteComplaint(
                                          token: widget.session.accessToken,
                                          complaintId: current.id,
                                          direction: "up",
                                        ),
                                        "",
                                      ),
                              icon: Icon(
                                current.isUpvotedByMe
                                    ? FluentIcons.thumb_like_24_filled
                                    : FluentIcons.thumb_like_24_regular,
                                color: current.isUpvotedByMe
                                    ? _activeVoteColor
                                    : null,
                              ),
                              label: Text("${current.upvotes}"),
                            ),
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => runAction(
                                        () => widget.dashboardService
                                            .voteComplaint(
                                          token: widget.session.accessToken,
                                          complaintId: current.id,
                                          direction: "down",
                                        ),
                                        "",
                                      ),
                              icon: Icon(
                                current.isDownvotedByMe
                                    ? FluentIcons.thumb_dislike_24_filled
                                    : FluentIcons.thumb_dislike_24_regular,
                                color: current.isDownvotedByMe
                                    ? _activeVoteColor
                                    : null,
                              ),
                              label: Text("${current.downvotes}"),
                            ),
                            if (current.canDelete)
                              OutlinedButton.icon(
                                onPressed: busy ? null : runDelete,
                                icon: const Icon(FluentIcons.delete_24_regular),
                                label: const Text("Delete"),
                              ),
                          ],
                        ),
                        if (current.canManage) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              "status-${current.id}-${current.status}",
                            ),
                            initialValue: selectedStatus,
                            decoration: const InputDecoration(
                              labelText: "Change Status",
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem<String>(
                                value: "OPEN",
                                child: Text("Open"),
                              ),
                              DropdownMenuItem<String>(
                                value: "IN_PROGRESS",
                                child: Text("In Progress"),
                              ),
                              DropdownMenuItem<String>(
                                value: "CLOSED",
                                child: Text("Closed"),
                              ),
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
                                      "Status updated.",
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
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(reply.text),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(reply.createdAt),
                                    style: Theme.of(ctx).textTheme.bodySmall,
                                  ),
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
                                    _toast("Comment cannot be empty.");
                                    return;
                                  }

                                  runAction(
                                    () => widget.dashboardService
                                        .addComplaintReply(
                                      token: widget.session.accessToken,
                                      complaintId: current.id,
                                      text: text,
                                    ),
                                    "Comment posted.",
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
              ),
            );
          },
        );
      },
    );

    replyController.dispose();
  }

  Future<void> _markSubmission(int scheduleId) async {
    try {
      await widget.dashboardService.markLaundrySubmission(
        token: widget.session.accessToken,
        scheduleId: scheduleId,
      );
      _toast("Submission marked.");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _markCollection(int scheduleId) async {
    try {
      await widget.dashboardService.markLaundryCollection(
        token: widget.session.accessToken,
        scheduleId: scheduleId,
      );
      _toast("Collection marked.");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _submitMessFeedback() async {
    if (!_isStudent) {
      _toast("Only student accounts can submit mess feedback.");
      return;
    }

    if (_selectedRateDay.isEmpty ||
        _selectedMealTime.isEmpty ||
        _selectedMenuItem.trim().isEmpty) {
      _toast("Select day, meal time, and menu item before submitting.");
      return;
    }

    if (_selectedRating < 1 || _selectedRating > 5) {
      _toast("Please choose a rating between 1 and 5.");
      return;
    }

    if (_messActionBusy) {
      return;
    }

    setState(() {
      _messActionBusy = true;
    });

    try {
      await widget.dashboardService.submitFeedback(
        token: widget.session.accessToken,
        weekDay: _selectedRateDay,
        mealTime: _selectedMealTime,
        menuItem: _selectedMenuItem,
        rating: _selectedRating,
        comment: _rateCommentController.text.trim(),
      );

      _rateCommentController.clear();
      if (mounted) {
        setState(() {
          _selectedRating = 0;
        });
      }

      _toast("Rating submitted.");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _messActionBusy = false;
        });
      } else {
        _messActionBusy = false;
      }
    }
  }

  Future<void> _votePollOption(MessPollOptionItem option) async {
    if (!_isStudent) {
      _toast("Only student accounts can vote in mess polls.");
      return;
    }

    if (_pollVoteBusyOptionIds.contains(option.id)) {
      return;
    }

    setState(() {
      _pollVoteBusyOptionIds.add(option.id);
    });

    try {
      await widget.dashboardService.votePoll(
        token: widget.session.accessToken,
        optionId: option.id,
      );
      _toast("Vote submitted.");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _pollVoteBusyOptionIds.remove(option.id);
        });
      } else {
        _pollVoteBusyOptionIds.remove(option.id);
      }
    }
  }

  Future<void> _createPollOption() async {
    if (!_canManageMessPolls) {
      _toast("Only admins and mess managers can create poll options.");
      return;
    }

    final itemName = _createPollItemController.text.trim();
    if (itemName.isEmpty) {
      _toast("Enter an item name to create a poll option.");
      return;
    }

    if (_messActionBusy) {
      return;
    }

    setState(() {
      _messActionBusy = true;
    });

    try {
      await widget.dashboardService.createPollOption(
        token: widget.session.accessToken,
        month: _currentMonth,
        itemName: itemName,
        pollType: _createPollType,
      );

      _createPollItemController.clear();
      _toast("Poll option created.");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _messActionBusy = false;
        });
      } else {
        _messActionBusy = false;
      }
    }
  }

  String _leastRatedTitle(LeastRatedMessItem item) {
    final normalizedName = item.itemName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }

    final menuValue = item.menuItem.trim();
    return menuValue.isNotEmpty ? menuValue : "Unknown item";
  }

  String _leastRatedMeta(LeastRatedMessItem item) {
    final parts = <String>[];
    if (item.weekDay.trim().isNotEmpty) {
      parts.add(_weekDayLabel(item.weekDay));
    }
    if (item.mealTime.trim().isNotEmpty) {
      parts.add(_mealTimeLabel(item.mealTime));
    }
    return parts.join(" • ");
  }

  Future<void> _openChangePassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChangePasswordScreen(
          authService: widget.authService,
          token: widget.session.accessToken,
        ),
      ),
    );

    if (changed == true) {
      _toast("Password updated.");
    }
  }

  Future<void> _handleAppBarAction(String value) async {
    if (value == "change_password") {
      await _openChangePassword();
      return;
    }

    if (value == "toggle_theme") {
      final nextMode =
          widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      widget.onThemeModeChanged(nextMode);
      return;
    }

    if (value == "logout") {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Logout"),
          content: const Text("Are you sure you want to logout?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Logout"),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await widget.onLogout();
      }
    }
  }

  EdgeInsets _tabContentPadding(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return EdgeInsets.fromLTRB(12, 12, 12, _tabBottomSafePadding + bottomInset);
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

  Widget _detailRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _boolLabel(bool? value) {
    if (value == null) {
      return "-";
    }
    return value ? "Yes" : "No";
  }

  List<Widget> _profileDetailRows() {
    final profile = _profile;
    final student = profile?.student;
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : widget.session.username;
    final displayEmail = profile?.email.isNotEmpty == true
        ? profile!.email
        : widget.session.email;
    final phone =
        "${profile?.phoneCountryCode ?? ""} ${profile?.phoneNumber ?? ""}"
            .trim();

    return <Widget>[
      _detailRow(label: "Full Name", value: _displayValue(displayName)),
      _detailRow(label: "Email", value: _displayValue(displayEmail)),
      _detailRow(
        label: "Username",
        value: _displayValue(profile?.username ?? widget.session.username),
      ),
      _detailRow(
        label: "Role",
        value: _formatEnumLabel(profile?.role ?? widget.session.role),
      ),
      _detailRow(
        label: "Phone",
        value: _displayValue(phone),
      ),
      _detailRow(
        label: "Department",
        value: _displayValue(profile?.department ?? ""),
      ),
      _detailRow(
        label: "Job Title",
        value: _displayValue(profile?.jobTitle ?? ""),
      ),
      _detailRow(
        label: "Assigned Mess",
        value: _displayValue(profile?.assignedMessName ?? ""),
      ),
      _detailRow(
        label: "Email Verified",
        value: _boolLabel(profile?.isEmailVerified),
      ),
      _detailRow(
        label: "Account Active",
        value: _boolLabel(profile?.isActive),
      ),
      _detailRow(
        label: "Must Change Password",
        value: _boolLabel(profile?.mustChangePassword),
      ),
      const Divider(height: 18),
      Text(
        "Student Information",
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      const SizedBox(height: 8),
      _detailRow(
        label: "Student ID",
        value: student != null ? student.id.toString() : "-",
      ),
      _detailRow(
        label: "Student Name",
        value: _displayValue(student?.name ?? ""),
      ),
      _detailRow(
        label: "Roll Number",
        value: _displayValue(student?.rollNo ?? ""),
      ),
      _detailRow(
        label: "Block",
        value: _displayValue(student?.blockName ?? ""),
      ),
      _detailRow(
        label: "Room",
        value: _displayValue(student?.roomNo ?? ""),
      ),
      _detailRow(
        label: "Mess Allotment",
        value: _displayValue(student?.messAllotment ?? ""),
      ),
    ];
  }

  Future<void> _openProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        final themeLabel = widget.themeMode == ThemeMode.dark
            ? "Use Light Theme"
            : "Use Dark Theme";

        Future<void> runProfileAction(String action) async {
          Navigator.of(ctx).pop();
          await _handleAppBarAction(action);
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: mediaQuery.viewInsets.bottom + 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.75,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Profile",
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "View profile details and account settings",
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _profileDetailRows(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  runProfileAction("change_password"),
                              icon: const Icon(FluentIcons.password_24_regular),
                              label: const Text("Change Password"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => runProfileAction("toggle_theme"),
                              icon: Icon(
                                widget.themeMode == ThemeMode.dark
                                    ? FluentIcons.weather_sunny_24_regular
                                    : FluentIcons.weather_moon_24_regular,
                              ),
                              label: Text(themeLabel),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: FilledButton.icon(
                          onPressed: () => runProfileAction("logout"),
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
        );
      },
    );
  }

  Widget _homeTab() {
    final profile = _profile;
    final student = profile?.student;
    final displayName = (profile?.fullName ?? "").trim().isNotEmpty
        ? profile!.fullName.trim()
        : (student?.name ?? "").trim().isNotEmpty
            ? student!.name.trim()
            : widget.session.username;
    final registrationNo = (student?.rollNo ?? "").trim();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: _tabContentPadding(context),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hi, $displayName",
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Registration Number: ${registrationNo.isEmpty ? "-" : registrationNo}",
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Notifications",
            subtitle:
                "Tap a notification to view full description and attachment",
            child: Column(
              children: _notifications.isEmpty
                  ? const [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("No notifications available."),
                      ),
                    ]
                  : _notifications.map(
                      (notification) {
                        final hasAttachment =
                            notification.posterUrl.trim().isNotEmpty;
                        final message = notification.message.trim().isEmpty
                            ? "No description provided."
                            : notification.message.trim();

                        return ListTile(
                          onTap: () => _openNotificationDetails(notification),
                          leading: Icon(
                            _notificationLevelIcon(notification.level),
                          ),
                          trailing:
                              const Icon(FluentIcons.chevron_right_20_regular),
                          title: Text(
                            notification.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            "${hasAttachment ? "Attachment included\n" : ""}$message\n${_formatDate(notification.createdAt)}",
                          ),
                          isThreeLine: true,
                        );
                      },
                    ).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _communityTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: _tabContentPadding(context),
        children: [
          _sectionCard(
            title: "Community Threads",
            subtitle: _hasCommunityFilters
                ? "Filtered complaint feed"
                : "Search and discuss student complaints",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FluentTextField(
                  controller: _communitySearchController,
                  labelText: "Search posts",
                  hintText: "Search complaint text or author",
                  prefixIcon: Icons.search_rounded,
                  textInputAction: TextInputAction.search,
                  onEditingComplete: _applyCommunityFilters,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>(
                          "community-category-$_communityCategoryFilter",
                        ),
                        initialValue: _communityCategoryFilter,
                        decoration: const InputDecoration(
                          labelText: "Category",
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: "",
                            child: Text("All categories"),
                          ),
                          ..._categoryOptions.map(
                            (option) => DropdownMenuItem<String>(
                              value: option.key,
                              child: Text(option.value),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _communityCategoryFilter = value ?? "";
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>(
                          "community-status-$_communityStatusFilter",
                        ),
                        initialValue: _communityStatusFilter,
                        decoration: const InputDecoration(
                          labelText: "Status",
                          border: OutlineInputBorder(),
                        ),
                        items: _statusFilters
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option.key,
                                child: Text(option.value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setState(() {
                            _communityStatusFilter = value ?? "";
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String>("community-sort-$_communitySort"),
                        initialValue: _communitySort,
                        decoration: const InputDecoration(
                          labelText: "Sort",
                          border: OutlineInputBorder(),
                        ),
                        items: _sortOptions
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option.key,
                                child: Text(option.value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _communitySort = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _applyCommunityFilters,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text("Search"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearCommunityFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: const Text("Clear"),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _canCreateComplaint ? _openNewComplaintPage : null,
                      icon: const Icon(Icons.add_comment_rounded),
                      label: const Text("New Complaint"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ..._complaints.map((complaint) {
            final status = complaint.status.toUpperCase();
            final statusLabel = complaint.statusLabel.isNotEmpty
                ? complaint.statusLabel
                : status;
            final voteBusy = _isCommunityVoteBusy(complaint.id);

            Color statusColor;
            IconData statusIcon;
            if (status == "OPEN") {
              statusColor = Colors.orange;
              statusIcon = FluentIcons.error_circle_24_regular;
            } else if (status == "IN_PROGRESS") {
              statusColor = const Color(0xFF0078D4);
              statusIcon = Icons.timelapse_rounded;
            } else {
              statusColor = Colors.green;
              statusIcon = FluentIcons.checkmark_circle_24_filled;
            }

            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openComplaintDetails(complaint),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _authorLabel(complaint),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(FluentIcons.chevron_right_20_regular),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          "${_categoryLabel(complaint.category)} - $statusLabel"),
                      const SizedBox(height: 6),
                      Text(
                        complaint.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: voteBusy
                                ? null
                                : () => _voteFromCommunityCard(
                                      complaint: complaint,
                                      direction: "up",
                                    ),
                            icon: Icon(
                              complaint.isUpvotedByMe
                                  ? FluentIcons.thumb_like_24_filled
                                  : FluentIcons.thumb_like_24_regular,
                              color: complaint.isUpvotedByMe
                                  ? _activeVoteColor
                                  : null,
                            ),
                            label: Text("${complaint.upvotes}"),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: voteBusy
                                ? null
                                : () => _voteFromCommunityCard(
                                      complaint: complaint,
                                      direction: "down",
                                    ),
                            icon: Icon(
                              complaint.isDownvotedByMe
                                  ? FluentIcons.thumb_dislike_24_filled
                                  : FluentIcons.thumb_dislike_24_regular,
                              color: complaint.isDownvotedByMe
                                  ? _activeVoteColor
                                  : null,
                            ),
                            label: Text("${complaint.downvotes}"),
                          ),
                          const Spacer(),
                          const Icon(FluentIcons.chat_24_regular, size: 18),
                          const SizedBox(width: 4),
                          Text("${complaint.replies.length}"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_complaints.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _hasCommunityFilters
                      ? "No posts found for the selected filters."
                      : "No complaints available.",
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _messTab() {
    final menuByDay = <String, MessMenu>{
      for (final menu in _menus) menu.weekDay.trim().toUpperCase(): menu,
    };
    final availableDays = _availableRateDays();
    final availableItems = _availableMenuItemsForSelection();
    final addPollOptions = _pollOptionsForType("ADD");
    final removePollOptions = _pollOptionsForType("REMOVE");

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: _tabContentPadding(context),
        children: [
          _sectionCard(
            title: "Mess Menu",
            subtitle: "Weekly menu overview",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isStudent) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMenuType,
                    decoration: const InputDecoration(
                      labelText: "Mess Type",
                      border: OutlineInputBorder(),
                    ),
                    items: _messTypes
                        .map(
                          (type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedMenuType = value;
                      });
                      _loadData();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                if (_menus.isEmpty)
                  const Text("No menu entries available.")
                else
                  ..._weekDayOptions.map((dayEntry) {
                    final menu = menuByDay[dayEntry.key];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dayEntry.value,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          if (menu == null)
                            const Text(
                                "Menu is not configured for this day yet.")
                          else ...[
                            Text(
                              "Breakfast: ${menu.breakfast.trim().isEmpty ? "No items listed" : menu.breakfast}",
                            ),
                            Text(
                              "Lunch: ${menu.lunch.trim().isEmpty ? "No items listed" : menu.lunch}",
                            ),
                            Text(
                              "Snacks: ${menu.snacks.trim().isEmpty ? "No items listed" : menu.snacks}",
                            ),
                            Text(
                              "Dinner: ${menu.dinner.trim().isEmpty ? "No items listed" : menu.dinner}",
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_isStudent) ...[
            _sectionCard(
              title: "Rate Food",
              subtitle:
                  "Choose day, meal time, and menu item to submit your rating",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (availableDays.isEmpty)
                    const Text(
                      "Menu is not configured yet, so rating is currently unavailable.",
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        "rate-day-${_selectedRateDay.isEmpty ? "empty" : _selectedRateDay}",
                      ),
                      initialValue: availableDays.contains(_selectedRateDay)
                          ? _selectedRateDay
                          : null,
                      decoration: const InputDecoration(
                        labelText: "Day",
                        border: OutlineInputBorder(),
                      ),
                      items: availableDays
                          .map(
                            (dayCode) => DropdownMenuItem<String>(
                              value: dayCode,
                              child: Text(_weekDayLabel(dayCode)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _messActionBusy
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedRateDay = value;
                                _selectedMealTime = _mealTimeOptions.first.key;
                                final dayItems =
                                    _availableMenuItemsForSelection();
                                _selectedMenuItem =
                                    dayItems.isEmpty ? "" : dayItems.first;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        "rate-meal-${_selectedMealTime.isEmpty ? "empty" : _selectedMealTime}",
                      ),
                      initialValue: _selectedMealTime.isNotEmpty
                          ? _selectedMealTime
                          : null,
                      decoration: const InputDecoration(
                        labelText: "Time Of Day",
                        border: OutlineInputBorder(),
                      ),
                      items: _mealTimeOptions
                          .map(
                            (meal) => DropdownMenuItem<String>(
                              value: meal.key,
                              child: Text(meal.value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _messActionBusy
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedMealTime = value;
                                final mealItems =
                                    _availableMenuItemsForSelection();
                                _selectedMenuItem =
                                    mealItems.isEmpty ? "" : mealItems.first;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        "rate-item-${availableItems.length}-${_selectedMenuItem.isEmpty ? "empty" : _selectedMenuItem}",
                      ),
                      initialValue: availableItems.contains(_selectedMenuItem)
                          ? _selectedMenuItem
                          : null,
                      decoration: const InputDecoration(
                        labelText: "Menu Item",
                        border: OutlineInputBorder(),
                      ),
                      items: availableItems
                          .map(
                            (menuItem) => DropdownMenuItem<String>(
                              value: menuItem,
                              child: Text(menuItem),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _messActionBusy
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedMenuItem = value;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Rating",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                      final value = index + 1;
                      return IconButton(
                        icon: Icon(
                            Icons.star,
                            color: _selectedRating >= value ? Colors.amber : Colors.grey,
                            size: 32,
                          ),
                        onPressed: _messActionBusy
                        ? null
                        : () {
                      setState(() {
                        _selectedRating = value;
                        });
                        },
                      );
                    }),
                  ),
                    const SizedBox(height: 10),
                    FluentTextField(
                      controller: _rateCommentController,
                      labelText: "Comment (optional)",
                      hintText: "Share what worked well or what should improve",
                      maxLines: 2,
                      enabled: !_messActionBusy,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _messActionBusy ? null : _submitMessFeedback,
                      icon: const Icon(FluentIcons.send_24_regular),
                      label: const Text("Submit Rating"),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          _sectionCard(
            title: "Poll For Mess Meeting",
            subtitle:
                "Vote on additions/removals and view current poll options",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isPollActive
                      ? "Poll is active for $_currentMonth"
                      : "Poll is not active yet for $_currentMonth",
                ),
                const SizedBox(height: 10),
                Text(
                  "Add Items (Likes)",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                if (addPollOptions.isEmpty)
                  const Text("No add-item options yet.")
                else
                  ...addPollOptions.map(
                    (option) => Card(
                      child: ListTile(
                        title: Text(option.itemName),
                        subtitle: Text("Votes: ${option.votes}"),
                        trailing: _isStudent
                            ? FilledButton(
                                onPressed:
                                    _pollVoteBusyOptionIds.contains(option.id)
                                        ? null
                                        : () => _votePollOption(option),
                                child: const Text("Like"),
                              )
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  "Remove Items (Dislikes)",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                if (removePollOptions.isEmpty)
                  const Text("No remove-item options yet.")
                else
                  ...removePollOptions.map(
                    (option) => Card(
                      child: ListTile(
                        title: Text(option.itemName),
                        subtitle: Text("Votes: ${option.votes}"),
                        trailing: _isStudent
                            ? FilledButton.tonal(
                                onPressed:
                                    _pollVoteBusyOptionIds.contains(option.id)
                                        ? null
                                        : () => _votePollOption(option),
                                child: const Text("Dislike"),
                              )
                            : null,
                      ),
                    ),
                  ),
                if (_canManageMessPolls) ...[
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    "Create Poll Option",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _createPollType,
                    decoration: const InputDecoration(
                      labelText: "Poll Type",
                      border: OutlineInputBorder(),
                    ),
                    items: _pollTypeOptions
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option.key,
                            child: Text(option.value),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _messActionBusy
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _createPollType = value;
                            });
                          },
                  ),
                  const SizedBox(height: 8),
                  FluentTextField(
                    controller: _createPollItemController,
                    labelText: "Item Name",
                    hintText: "Example: Paneer Fried Rice",
                    enabled: !_messActionBusy,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _messActionBusy ? null : _createPollOption,
                    icon: const Icon(FluentIcons.add_24_regular),
                    label: const Text("Save Poll Option"),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Least Rated Dishes",
            subtitle: "Lowest rated menu items from available feedback",
            child: Column(
              children: _leastRatedItems.isEmpty
                  ? const [Text("No rating data available yet.")]
                  : _leastRatedItems
                      .map(
                        (item) => Card(
                          child: ListTile(
                            title: Text(
                              _leastRatedTitle(item),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              [
                                if (_leastRatedMeta(item).isNotEmpty)
                                  _leastRatedMeta(item),
                                "Avg: ${item.avgRating.toStringAsFixed(2)} • Votes: ${item.totalVotes}",
                              ].join("\n"),
                            ),
                            isThreeLine: _leastRatedMeta(item).isNotEmpty,
                          ),
                        ),
                      )
                      .toList(growable: false),
            ),
          ),
          const SizedBox(height: 10),
          if (_canViewMessFeedback) ...[
            _sectionCard(
              title: "Recent Item Feedback",
              subtitle: "Student feedback from your assigned mess",
              child: Column(
                children: _feedbacks.isEmpty
                    ? const [Text("No feedback available for your mess yet.")]
                    : _feedbacks
                        .take(12)
                        .map(
                          (feedback) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feedback.menuItem,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${_weekDayLabel(feedback.weekDay)} • ${_mealTimeLabel(feedback.mealTime)} • Rating ${feedback.rating}/5",
                                  ),
                                  if (feedback.comment.trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(feedback.comment.trim()),
                                  ],
                                  if (feedback.managerReply
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      "Reply: ${feedback.managerReply.trim()}",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    "Student #${feedback.studentId ?? '-'} • ${_formatDate(feedback.createdAt)}",
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _sectionCard(
            title: "Caterers",
            subtitle: "Current caterer assignments",
            child: Column(
              children: _caterers.isEmpty
                  ? const [Text("No caterers available.")]
                  : _caterers
                      .map(
                        (caterer) => ListTile(
                          title: Text(caterer.name),
                          subtitle: Text(
                              "${caterer.blockName} - ${caterer.mealTypes}"),
                        ),
                      )
                      .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _laundryTab() {
    if (_isStudent) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: _tabContentPadding(context),
          children: [
            if (_schedules.isEmpty)
              _sectionCard(
                title: "Student Laundry",
                subtitle: "My laundry schedule",
                child:
                    const Text("No student schedule found for this account."),
              )
            else
              _studentLaundryCard(_schedules.first),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: _tabContentPadding(context),
        children: [
          _sectionCard(
            title: "Laundry Schedule",
            subtitle: _isLaundryPerson
                ? "Mark submission and collection"
                : "Track laundry status",
            child: Column(
              children: _schedules.isEmpty
                  ? const [Text("No laundry schedules available.")]
                  : _schedules
                      .map(
                        (schedule) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  schedule.day,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Submission: ${schedule.submission ? "Done" : "Pending"}",
                                ),
                                Text(
                                  "Collection: ${schedule.collection ? "Done" : "Pending"}",
                                ),
                                if (_isLaundryPerson || _isAdmin) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton(
                                        onPressed: schedule.submission
                                            ? null
                                            : () =>
                                                _markSubmission(schedule.id),
                                        child: const Text("Mark Submission"),
                                      ),
                                      OutlinedButton(
                                        onPressed: schedule.collection
                                            ? null
                                            : () =>
                                                _markCollection(schedule.id),
                                        child: const Text("Mark Collection"),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  String _laundryStatusLabel(LaundrySchedule schedule) {
    if (schedule.submission) {
      return "Clothes Submitted";
    }
    if (schedule.collection) {
      return "Ready for New Submission";
    }
    return "Not Submitted Yet";
  }

  Color _laundryStatusColor(LaundrySchedule schedule) {
    if (schedule.submission) {
      return const Color(0xFF107C10);
    }
    if (schedule.collection) {
      return const Color(0xFFFFB900);
    }
    return const Color(0xFFE81123);
  }

  String _weekdayCodeFromInt(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return "MON";
      case DateTime.tuesday:
        return "TUE";
      case DateTime.wednesday:
        return "WED";
      case DateTime.thursday:
        return "THU";
      case DateTime.friday:
        return "FRI";
      case DateTime.saturday:
        return "SAT";
      case DateTime.sunday:
        return "SUN";
      default:
        return "";
    }
  }

  List<Map<String, dynamic>> _buildLaundryCalendarDays(
    DateTime month,
    LaundrySchedule schedule,
  ) {
    final firstDay = DateTime(month.year, month.month, 1);
    final totalDays = DateUtils.getDaysInMonth(month.year, month.month);
    final today = DateTime.now();
    final cells = <Map<String, dynamic>>[];

    for (var i = 0; i < firstDay.weekday - 1; i++) {
      cells.add(<String, dynamic>{
        "day": null,
        "highlight": false,
        "today": false,
      });
    }

    for (var day = 1; day <= totalDays; day++) {
      final current = DateTime(month.year, month.month, day);
      final highlighted =
          _weekdayCodeFromInt(current.weekday) == schedule.dayCode;
      final isToday = current.year == today.year &&
          current.month == today.month &&
          current.day == today.day;

      cells.add(<String, dynamic>{
        "day": day,
        "highlight": highlighted,
        "today": isToday,
      });
    }

    while (cells.length % 7 != 0) {
      cells.add(<String, dynamic>{
        "day": null,
        "highlight": false,
        "today": false,
      });
    }

    return cells;
  }

  String _studentLaundryQrData(LaundrySchedule schedule) {
    final qrText = _laundryQrText.trim();
    if (qrText.isNotEmpty) {
      return qrText;
    }
    return jsonEncode(
      <String, dynamic>{
        "student_id": schedule.studentId,
        "qr_token": schedule.qrToken,
        "day_of_week": schedule.dayCode,
      },
    );
  }

  Future<void> _openQrPreview(String qrText) async {
    double? previousBrightness;
    var setToMax = false;

    try {
      previousBrightness = await ScreenBrightness().current;
    } catch (_) {
      previousBrightness = null;
    }

    try {
      await ScreenBrightness().setScreenBrightness(1);
      setToMax = true;
    } catch (_) {
      setToMax = false;
    }

    try {
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) {
          final shortestSide = MediaQuery.of(ctx).size.shortestSide;
          final qrSize = (shortestSide * 0.9).clamp(220.0, 520.0).toDouble();

          return Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: qrText,
                        size: qrSize,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton.filled(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      if (!setToMax) {
        return;
      }

      try {
        if (previousBrightness != null) {
          await ScreenBrightness().setScreenBrightness(previousBrightness);
        } else {
          await ScreenBrightness().resetScreenBrightness();
        }
      } catch (_) {
        // Ignore brightness restore issues and keep the QR flow uninterrupted.
      }
    }
  }

  Widget _studentLaundryCard(LaundrySchedule schedule) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final statusColor = _laundryStatusColor(schedule);
    final qrData = _studentLaundryQrData(schedule);
    final calendarMonth = DateTime.now();
    final calendarDays = _buildLaundryCalendarDays(calendarMonth, schedule);

    final lastSubmission = schedule.lastSubmissionAt == null
        ? "N/A"
        : _formatDate(schedule.lastSubmissionAt);
    final dueCollection = schedule.dueCollectionBy == null
        ? "N/A"
        : _formatDate(schedule.dueCollectionBy);

    final edgeColor =
        isDark ? const Color(0xFF34393F) : const Color(0xFFD8DEE7);
    final leftPanelColor =
        isDark ? const Color(0xFF1A1C20) : const Color(0xFFFFFFFF);
    final cardGradient = isDark
        ? const [Color(0xFF0F1A26), Color(0xFF1E2128), Color(0xFF2A2418)]
        : const [Color(0xFFF3F9FF), Color(0xFFF7F7F7), Color(0xFFFFF9E8)];

    Widget infoRow({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                icon,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: "$label: ",
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget qrPanel() {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: leftPanelColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: edgeColor),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => _openQrPreview(qrData),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: qrData,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Tap QR to view full screen",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    Widget calendarCard() {
      final weekHeaders = <String>[
        "MON",
        "TUE",
        "WED",
        "THU",
        "FRI",
        "SAT",
        "SUN"
      ];

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: leftPanelColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: edgeColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat("MMMM yyyy").format(calendarMonth),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: weekHeaders.length + calendarDays.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (_, index) {
                if (index < weekHeaders.length) {
                  return Center(
                    child: Text(
                      weekHeaders[index],
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final entry = calendarDays[index - weekHeaders.length];
                final day = entry["day"] as int?;
                final highlight = entry["highlight"] == true;
                final isToday = entry["today"] == true;
                final blank = day == null;

                final cellColor = highlight
                    ? const Color(0x232AA44F)
                    : (isDark
                        ? const Color(0xFF1A1E23)
                        : const Color(0xFFFFFFFF));
                final borderColor = isToday
                    ? const Color(0xFF1483E3)
                    : (highlight ? const Color(0xFF2AA44F) : edgeColor);

                return Container(
                  decoration: BoxDecoration(
                    color: blank ? Colors.transparent : cellColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: blank ? edgeColor.withAlpha(100) : borderColor,
                      width: isToday ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    blank ? "" : "$day",
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: highlight
                          ? const Color(0xFF138A2E)
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_box_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Green dates are your room's assigned laundry dates this month.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: edgeColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cardGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 70 : 25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wideLayout = constraints.maxWidth > 900;

          final leftContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 18,
                    color: colorScheme.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Student Laundry",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "My Laundry Schedule",
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              infoRow(
                icon: Icons.calendar_today_outlined,
                label: "Pickup Day",
                value: schedule.day,
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: leftPanelColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: edgeColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withAlpha(110),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _laundryStatusLabel(schedule),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              infoRow(
                icon: Icons.history_rounded,
                label: "Last Submission",
                value: lastSubmission,
              ),
              infoRow(
                icon: Icons.alarm_on_outlined,
                label: "Due Collection By",
                value: dueCollection,
              ),
              qrPanel(),
            ],
          );

          if (wideLayout) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: leftContent),
                const SizedBox(width: 16),
                Expanded(flex: 12, child: calendarCard()),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftContent,
              const SizedBox(height: 14),
              calendarCard(),
            ],
          );
        },
      ),
    );
  }

  Widget _adminTab() {
    return ListView(
      padding: _tabContentPadding(context),
      children: [
        _sectionCard(
          title: "Admin Overview",
          subtitle: "Quick system snapshot",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Community posts: ${_complaints.length}"),
              Text("Laundry schedules: ${_schedules.length}"),
              Text("Caterers: ${_caterers.length}"),
              Text("Notifications: ${_notifications.length}"),
              const SizedBox(height: 10),
              const Text(
                "Use the Django admin panel for advanced management operations.",
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingNavBar({
    required List<_DashboardNavItem> items,
    required int selectedIndex,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final navSurface = isDark
        ? const Color(0xFF0B1628).withAlpha(185)
        : Colors.white.withAlpha(205);
    final borderColor = isDark
        ? Colors.white.withAlpha(30)
        : const Color(0xFF0C2D66).withAlpha(24);
    final activeBackgroundColor = isDark ? Colors.white : _activeNavColor;
    final activeIconColor = isDark ? _activeNavColor : Colors.white;
    final activeTextColor = isDark ? Colors.white : _activeNavColor;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 70 : 30),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: navSurface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < items.length; index++)
                      Expanded(
                        child: _buildNavItemButton(
                          item: items[index],
                          isActive: selectedIndex == index,
                          activeBackgroundColor: activeBackgroundColor,
                          activeIconColor: activeIconColor,
                          activeTextColor: activeTextColor,
                          inactiveIconColor:
                              colorScheme.onSurface.withAlpha(145),
                          inactiveTextColor:
                              colorScheme.onSurface.withAlpha(170),
                          onTap: () {
                            if (_selectedNavIndex == index) {
                              return;
                            }
                            setState(() {
                              _selectedNavIndex = index;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItemButton({
    required _DashboardNavItem item,
    required bool isActive,
    required Color activeBackgroundColor,
    required Color activeIconColor,
    required Color activeTextColor,
    required Color inactiveIconColor,
    required Color inactiveTextColor,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isActive,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? activeBackgroundColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isActive ? item.filledIcon : item.regularIcon,
                  size: 20,
                  color: isActive ? activeIconColor : inactiveIconColor,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  color: isActive ? activeTextColor : inactiveTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleBarSurface = Color.alphaBlend(
      _activeNavColor.withAlpha(isDark ? 34 : 16),
      isDark
          ? const Color(0xFF0B1628).withAlpha(185)
          : Colors.white.withAlpha(205),
    );
    final titleBarBorderColor = isDark
        ? Colors.white.withAlpha(30)
        : const Color(0xFF0C2D66).withAlpha(24);
    final titleBarIconColor = isDark ? Colors.white : _activeNavColor;

    final showMessTab = !_isLaundryPerson;
    final showLaundryTab = !_isMessManager;
    final showAdminTab = _isAdmin;

    final pages = <Widget>[
      _homeTab(),
      _communityTab(),
      if (showMessTab) _messTab(),
      if (showLaundryTab) _laundryTab(),
      if (showAdminTab) _adminTab(),
    ];

    final navItems = <_DashboardNavItem>[
      const _DashboardNavItem(
        label: "Home",
        regularIcon: FluentIcons.home_24_regular,
        filledIcon: FluentIcons.home_24_filled,
      ),
      const _DashboardNavItem(
        label: "Community",
        regularIcon: FluentIcons.chat_bubbles_question_24_regular,
        filledIcon: FluentIcons.chat_bubbles_question_24_filled,
      ),
      if (showMessTab)
        const _DashboardNavItem(
          label: "Mess",
          regularIcon: FluentIcons.food_24_regular,
          filledIcon: FluentIcons.food_24_filled,
        ),
      if (showLaundryTab)
        const _DashboardNavItem(
          label: "Laundry",
          regularIcon: FluentIcons.water_24_regular,
          filledIcon: FluentIcons.water_24_filled,
        ),
      if (showAdminTab)
        const _DashboardNavItem(
          label: "Admin",
          regularIcon: FluentIcons.settings_24_regular,
          filledIcon: FluentIcons.settings_24_filled,
        ),
    ];

    assert(navItems.length == pages.length);
    final selectedIndex = _selectedNavIndex.clamp(0, navItems.length - 1);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: titleBarIconColor),
        actionsIconTheme: IconThemeData(color: titleBarIconColor),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: titleBarIconColor,
          fontWeight: FontWeight.w700,
        ),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: titleBarSurface,
                border: Border(
                  bottom: BorderSide(color: titleBarBorderColor),
                ),
              ),
            ),
          ),
        ),
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).maybePop();
          },
          icon: const Icon(FluentIcons.arrow_left_24_regular),
          tooltip: "Back",
        ),
        title: const Text("HostelCC"),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(FluentIcons.arrow_sync_24_regular),
            tooltip: "Refresh",
          ),
          IconButton(
            onPressed: _openProfileSheet,
            icon: const Icon(FluentIcons.person_circle_24_regular),
            tooltip: "Profile",
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : pages[selectedIndex],
      bottomNavigationBar: _buildFloatingNavBar(
        items: navItems,
        selectedIndex: selectedIndex,
      ),
    );
  }
}

class _DashboardNavItem {
  const _DashboardNavItem({
    required this.label,
    required this.regularIcon,
    required this.filledIcon,
  });

  final String label;
  final IconData regularIcon;
  final IconData filledIcon;
}

class _NotificationDetailsScreen extends StatefulWidget {
  const _NotificationDetailsScreen({
    required this.notification,
    required this.authToken,
    required this.apiBaseUrl,
    required this.attachmentCache,
    required this.formattedCreatedAt,
  });

  final AppNotificationItem notification;
  final String authToken;
  final String apiBaseUrl;
  final NotificationAttachmentCache attachmentCache;
  final String formattedCreatedAt;

  @override
  State<_NotificationDetailsScreen> createState() =>
      _NotificationDetailsScreenState();
}

class _NotificationDetailsScreenState
    extends State<_NotificationDetailsScreen> {
  bool _loadingAttachment = false;
  String? _cachedAttachmentPath;
  Uint8List? _cachedAttachmentBytes;
  String? _attachmentError;

  String get _attachmentUrl => widget.notification.posterUrl.trim();
  bool get _hasAttachment => _attachmentUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasAttachment) {
      unawaited(_loadAttachment(forceDownload: false));
    }
  }

  Map<String, String> _requestHeaders() {
    final token = widget.authToken.trim();
    if (token.isEmpty) {
      return <String, String>{};
    }
    return <String, String>{"Authorization": "Bearer $token"};
  }

  Future<void> _loadAttachment({required bool forceDownload}) async {
    if (!_hasAttachment) {
      return;
    }

    setState(() {
      _loadingAttachment = true;
      if (forceDownload) {
        _attachmentError = null;
      }
    });

    try {
      final cachedPath = await widget.attachmentCache.getCachedFilePath(
        notificationId: widget.notification.id,
        attachmentUrl: _attachmentUrl,
        apiBaseUrl: widget.apiBaseUrl,
      );

      // For initial rendering, only use locally cached content.
      // Download should happen only when user explicitly retries.
      final resolvedPath = cachedPath ??
          (forceDownload
              ? await widget.attachmentCache.ensureCached(
                  notificationId: widget.notification.id,
                  attachmentUrl: _attachmentUrl,
                  apiBaseUrl: widget.apiBaseUrl,
                  headers: _requestHeaders(),
                )
              : null);

      if (resolvedPath == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _cachedAttachmentPath = null;
          _cachedAttachmentBytes = null;
          _attachmentError =
              "Attachment is not cached on this device yet. Connect to internet and retry download.";
        });
        return;
      }

      final bytes = await widget.attachmentCache.readCachedBytes(resolvedPath);
      if (!mounted) {
        return;
      }

      setState(() {
        _cachedAttachmentPath = resolvedPath;
        _cachedAttachmentBytes = Uint8List.fromList(bytes);
        _attachmentError = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cachedAttachmentPath = null;
        _cachedAttachmentBytes = null;
        _attachmentError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAttachment = false;
        });
      }
    }
  }

  bool _isPdfFile(String url) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith(".pdf");
  }

  bool _hasKnownImageExtension(String url) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith(".png") ||
        path.endsWith(".jpg") ||
        path.endsWith(".jpeg") ||
        path.endsWith(".webp");
  }

  Widget _buildAttachmentPreview(BuildContext context) {
    if (!_hasAttachment) {
      return const Text("No attachment available.");
    }

    if (_cachedAttachmentBytes == null) {
      if (_loadingAttachment) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      final resolvedUrl = widget.attachmentCache.resolveAttachmentUrl(
        _attachmentUrl,
        widget.apiBaseUrl,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Attachment is not available offline yet. Connect to internet and retry download.",
          ),
          if (_attachmentError != null && _attachmentError!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _attachmentError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (resolvedUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(resolvedUrl),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadingAttachment
                ? null
                : () => _loadAttachment(forceDownload: true),
            icon: const Icon(Icons.download_rounded),
            label:
                Text(_loadingAttachment ? "Downloading..." : "Retry Download"),
          ),
        ],
      );
    }

    final typeHint = _cachedAttachmentPath ?? _attachmentUrl;
    final isPdf = _isPdfFile(typeHint);
    final shouldRenderAsImage = !isPdf;

    if (isPdf) {
      return SizedBox(
        height: 560,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SfPdfViewer.memory(_cachedAttachmentBytes!),
        ),
      );
    }

    if (shouldRenderAsImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: _hasKnownImageExtension(typeHint) ? 4 / 3 : 16 / 10,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.memory(
                _cachedAttachmentBytes!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("Unable to load attachment preview."),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const Text("Attachment format is not supported for preview.");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleBarSurface = Color.alphaBlend(
      const Color(0xFF0B3D91).withAlpha(isDark ? 34 : 16),
      isDark
          ? const Color(0xFF0B1628).withAlpha(185)
          : Colors.white.withAlpha(205),
    );
    final titleBarBorderColor = isDark
        ? Colors.white.withAlpha(30)
        : const Color(0xFF0C2D66).withAlpha(24);
    final titleBarIconColor = isDark ? Colors.white : const Color(0xFF0B3D91);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: titleBarIconColor),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: titleBarIconColor,
          fontWeight: FontWeight.w700,
        ),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: titleBarSurface,
                border: Border(
                  bottom: BorderSide(color: titleBarBorderColor),
                ),
              ),
            ),
          ),
        ),
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).maybePop();
          },
          icon: const Icon(FluentIcons.arrow_left_24_regular),
          tooltip: "Back",
        ),
        title: const Text("Notification Details"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.notification.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(widget.notification.level)),
              Chip(label: Text(widget.notification.audience)),
              Chip(label: Text(widget.formattedCreatedAt)),
            ],
          ),
          if (widget.notification.createdByName.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("Posted by ${widget.notification.createdByName.trim()}"),
          ],
          const SizedBox(height: 16),
          Text(
            "Description",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.notification.message.trim().isEmpty
                ? "No description provided."
                : widget.notification.message.trim(),
          ),
          const SizedBox(height: 20),
          Text(
            "Attachment",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          _buildAttachmentPreview(context),
        ],
      ),
    );
  }
}
