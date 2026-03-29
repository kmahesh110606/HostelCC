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
import "package:video_player/video_player.dart";

import "../../models/app_models.dart";
import "../../models/user_session.dart";
import "../../screens/auth/change_password_screen.dart";
import "../../screens/dashboard/laundry_qr_scanner_screen.dart";
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

  int _selectedNavIndex = 0;
  String _selectedMenuType = _messTypes.first;
  String _selectedMessMenuDay = "";

  String _communityQuery = "";
  String _communityCategoryFilter = "";
  String _communityStatusFilter = "";
  String _communitySort = "newest";

  final TextEditingController _communitySearchController =
      TextEditingController();
  final TextEditingController _rateCommentController = TextEditingController();
  final TextEditingController _createPollItemController =
      TextEditingController();
  late final PageController _messMenuPageController;
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
  bool get _isDepartmentStaff => widget.session.role == "DEPARTMENT_STAFF";
  bool get _canViewMessFeedback => _isMessManager || _isWarden;
  bool get _canManageMessPolls => _isMessManager || _isAdmin;

  bool get _canCreateComplaint =>
      _isStudent || _isWarden || _isAdmin || _isDepartmentStaff;

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

  int _weekDayIndexForCode(String dayCode) {
    final normalized = dayCode.trim().toUpperCase();
    for (var index = 0; index < _weekDayOptions.length; index += 1) {
      if (_weekDayOptions[index].key == normalized) {
        return index;
      }
    }
    return 0;
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

  void _syncMessMenuDayWithMenus() {
    final dayCodes = _weekDayOptions
        .map((entry) => entry.key.trim().toUpperCase())
        .where((day) => day.isNotEmpty)
        .toSet();

    final fallbackDay = dayCodes.contains(_currentWeekDayCode)
        ? _currentWeekDayCode
        : _weekDayOptions.first.key;

    if (_selectedMessMenuDay.isEmpty ||
        !dayCodes.contains(_selectedMessMenuDay)) {
      _selectedMessMenuDay = fallbackDay;
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
    _selectedMessMenuDay = _currentWeekDayCode;
    _messMenuPageController = PageController(
      initialPage: _weekDayIndexForCode(_selectedMessMenuDay),
      viewportFraction: 0.94,
    );
    _loadData();
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _communitySearchController.dispose();
    _rateCommentController.dispose();
    _createPollItemController.dispose();
    _messMenuPageController.dispose();
    _notificationAttachmentCache.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }

    String? syncErrorMessage;

    setState(() {
      _loading = true;
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
      await _saveDashboardCache(
        menus: results[0] as List<MessMenu>,
        complaints: results[1] as List<ComplaintItem>,
        schedules: schedules,
        laundryQrText: laundryQrText,
        caterers: results[3] as List<CatererItem>,
        feedbacks: results[4] as List<MessFeedbackItem>,
        pollOptions: results[5] as List<MessPollOptionItem>,
        leastRatedItems: results[6] as List<LeastRatedMessItem>,
        notifications: notifications,
        profile: profile,
      );
      await widget.storageService
          .saveCachedProfile(jsonEncode(profile.toJson()));

      if (!mounted) {
        return;
      }

      setState(() {
        _menus = results[0] as List<MessMenu>;
        _syncMessMenuDayWithMenus();
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
      final restoredFromCache = await _restoreDashboardCache();
      syncErrorMessage = restoredFromCache
          ? "Sync unsuccessful. Showing cached data."
          : "Sync unsuccessful. No cached data is available yet.";
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }

    if (!mounted || syncErrorMessage == null) {
      return;
    }

    await _showSyncErrorDialog(syncErrorMessage);
  }

  bool get _hasDashboardData {
    return _profile != null ||
        _menus.isNotEmpty ||
        _complaints.isNotEmpty ||
        _schedules.isNotEmpty ||
        _caterers.isNotEmpty ||
        _feedbacks.isNotEmpty ||
        _pollOptions.isNotEmpty ||
        _leastRatedItems.isNotEmpty ||
        _notifications.isNotEmpty;
  }

  List<T> _decodeCachedList<T>(
    dynamic raw,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (raw is! List<dynamic>) {
      return <T>[];
    }

    final values = <T>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          values.add(fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip malformed cache entries.
        }
      }
    }
    return values;
  }

  Map<String, dynamic> _messMenuToCache(MessMenu menu) {
    return <String, dynamic>{
      "mess_type": menu.messType,
      "week_day": menu.weekDay,
      "breakfast_items": menu.breakfast,
      "lunch_items": menu.lunch,
      "snacks_items": menu.snacks,
      "dinner_items": menu.dinner,
    };
  }

  Map<String, dynamic> _complaintReplyToCache(ComplaintReplyItem reply) {
    return <String, dynamic>{
      "id": reply.id,
      "author_name": reply.authorName,
      "text": reply.text,
      "created_at": reply.createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _complaintToCache(ComplaintItem complaint) {
    return <String, dynamic>{
      "id": complaint.id,
      "student": complaint.studentId,
      "author_name": complaint.authorName,
      "student_name": complaint.studentName,
      "registration_no": complaint.registrationNo,
      "block_name": complaint.blockName,
      "room_no": complaint.roomNo,
      "category": complaint.category,
      "text": complaint.text,
      "media_url": complaint.mediaUrl,
      "media_type": complaint.mediaType,
      "status": complaint.status,
      "status_label": complaint.statusLabel,
      "user_vote": complaint.userVote,
      "upvotes": complaint.upvotes,
      "downvotes": complaint.downvotes,
      "replies":
          complaint.replies.map(_complaintReplyToCache).toList(growable: false),
      "created_at": complaint.createdAt?.toIso8601String(),
      "can_manage": complaint.canManage,
      "can_delete": complaint.canDelete,
    };
  }

  Map<String, dynamic> _scheduleToCache(LaundrySchedule schedule) {
    return <String, dynamic>{
      "id": schedule.id,
      "student": schedule.studentId,
      "day_of_week": schedule.dayCode,
      "submission_status": schedule.submission,
      "collection_status": schedule.collection,
      "qr_token": schedule.qrToken,
      "last_submission_at": schedule.lastSubmissionAt?.toIso8601String(),
      "due_collection_by": schedule.dueCollectionBy?.toIso8601String(),
    };
  }

  Map<String, dynamic> _catererToCache(CatererItem caterer) {
    return <String, dynamic>{
      "name": caterer.name,
      "block_name": caterer.blockName,
      "meal_types": caterer.mealTypes,
    };
  }

  Map<String, dynamic> _feedbackToCache(MessFeedbackItem feedback) {
    return <String, dynamic>{
      "id": feedback.id,
      "student": feedback.studentId,
      "week_day": feedback.weekDay,
      "meal_time": feedback.mealTime,
      "menu_item": feedback.menuItem,
      "rating": feedback.rating,
      "comment": feedback.comment,
      "month": feedback.month,
      "manager_reply": feedback.managerReply,
      "created_at": feedback.createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _pollOptionToCache(MessPollOptionItem option) {
    return <String, dynamic>{
      "id": option.id,
      "month": option.month,
      "item_name": option.itemName,
      "poll_type": option.pollType,
      "votes": option.votes,
    };
  }

  Map<String, dynamic> _leastRatedItemToCache(LeastRatedMessItem item) {
    return <String, dynamic>{
      "menu_item": item.menuItem,
      "item_name": item.itemName,
      "week_day": item.weekDay,
      "meal_time": item.mealTime,
      "avg_rating": item.avgRating,
      "total": item.totalVotes,
    };
  }

  Map<String, dynamic> _notificationToCache(AppNotificationItem notification) {
    return <String, dynamic>{
      "id": notification.id,
      "title": notification.title,
      "message": notification.message,
      "poster_url": notification.posterUrl,
      "level": notification.level,
      "audience": notification.audience,
      "created_by_name": notification.createdByName,
      "created_at": notification.createdAt?.toIso8601String(),
    };
  }

  Future<void> _saveDashboardCache({
    required List<MessMenu> menus,
    required List<ComplaintItem> complaints,
    required List<LaundrySchedule> schedules,
    required String laundryQrText,
    required List<CatererItem> caterers,
    required List<MessFeedbackItem> feedbacks,
    required List<MessPollOptionItem> pollOptions,
    required List<LeastRatedMessItem> leastRatedItems,
    required List<AppNotificationItem> notifications,
    required UserProfileItem profile,
  }) async {
    final payload = <String, dynamic>{
      "menus": menus.map(_messMenuToCache).toList(growable: false),
      "complaints": complaints.map(_complaintToCache).toList(growable: false),
      "schedules": schedules.map(_scheduleToCache).toList(growable: false),
      "laundry_qr_text": laundryQrText,
      "caterers": caterers.map(_catererToCache).toList(growable: false),
      "feedbacks": feedbacks.map(_feedbackToCache).toList(growable: false),
      "poll_options":
          pollOptions.map(_pollOptionToCache).toList(growable: false),
      "least_rated_items":
          leastRatedItems.map(_leastRatedItemToCache).toList(growable: false),
      "notifications":
          notifications.map(_notificationToCache).toList(growable: false),
      "profile": profile.toJson(),
      "cached_at": DateTime.now().toIso8601String(),
    };

    await widget.storageService.saveCachedDashboard(jsonEncode(payload));
  }

  Future<bool> _restoreDashboardCache() async {
    UserProfileItem? profile;
    List<MessMenu>? menus;
    List<ComplaintItem>? complaints;
    List<LaundrySchedule>? schedules;
    List<CatererItem>? caterers;
    List<MessFeedbackItem>? feedbacks;
    List<MessPollOptionItem>? pollOptions;
    List<LeastRatedMessItem>? leastRatedItems;
    List<AppNotificationItem>? notifications;
    String? laundryQrText;

    try {
      final dashboardRaw = await widget.storageService.readCachedDashboard();
      if (dashboardRaw != null && dashboardRaw.trim().isNotEmpty) {
        final decoded = jsonDecode(dashboardRaw);
        if (decoded is Map) {
          final data = Map<String, dynamic>.from(decoded);
          menus = _decodeCachedList(data["menus"], MessMenu.fromJson);
          complaints =
              _decodeCachedList(data["complaints"], ComplaintItem.fromJson);
          schedules =
              _decodeCachedList(data["schedules"], LaundrySchedule.fromJson);
          caterers = _decodeCachedList(data["caterers"], CatererItem.fromJson);
          feedbacks =
              _decodeCachedList(data["feedbacks"], MessFeedbackItem.fromJson);
          pollOptions = _decodeCachedList(
            data["poll_options"],
            MessPollOptionItem.fromJson,
          );
          leastRatedItems = _decodeCachedList(
            data["least_rated_items"],
            LeastRatedMessItem.fromJson,
          );
          notifications = _decodeCachedList(
            data["notifications"],
            AppNotificationItem.fromJson,
          );
          laundryQrText = (data["laundry_qr_text"] ?? "").toString();

          if (data["profile"] is Map<String, dynamic>) {
            profile = UserProfileItem.fromJson(
                data["profile"] as Map<String, dynamic>);
          } else if (data["profile"] is Map) {
            profile = UserProfileItem.fromJson(
              Map<String, dynamic>.from(data["profile"] as Map),
            );
          }
        }
      }
    } catch (_) {
      // Fall back to profile-only cache below.
    }

    if (profile == null) {
      try {
        final cachedProfile = await widget.storageService.readCachedProfile();
        if (cachedProfile != null && cachedProfile.trim().isNotEmpty) {
          profile = UserProfileItem.fromJson(
            jsonDecode(cachedProfile) as Map<String, dynamic>,
          );
        }
      } catch (_) {
        profile = null;
      }
    }

    final hasAnyCache = profile != null ||
        (menus?.isNotEmpty ?? false) ||
        (complaints?.isNotEmpty ?? false) ||
        (schedules?.isNotEmpty ?? false) ||
        (caterers?.isNotEmpty ?? false) ||
        (feedbacks?.isNotEmpty ?? false) ||
        (pollOptions?.isNotEmpty ?? false) ||
        (leastRatedItems?.isNotEmpty ?? false) ||
        (notifications?.isNotEmpty ?? false) ||
        (laundryQrText?.trim().isNotEmpty ?? false);

    if (!hasAnyCache || !mounted) {
      return false;
    }

    setState(() {
      if (menus != null) {
        _menus = menus;
      }
      if (complaints != null) {
        _complaints = complaints;
      }
      if (schedules != null) {
        _schedules = schedules;
      }
      if (caterers != null) {
        _caterers = caterers;
      }
      if (feedbacks != null) {
        _feedbacks = feedbacks;
      }
      if (pollOptions != null) {
        _pollOptions = pollOptions;
      }
      if (leastRatedItems != null) {
        _leastRatedItems = leastRatedItems;
      }
      if (notifications != null) {
        _notifications = notifications;
      }
      if (laundryQrText != null) {
        _laundryQrText = laundryQrText;
      }
      if (profile != null) {
        _profile = profile;
      }

      _syncMessMenuDayWithMenus();
      _syncRateSelectorsWithMenus();
    });

    return true;
  }

  Future<void> _showSyncErrorDialog(String message) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Sync Error"),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
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

  int _communityActiveFilterCount() {
    var count = 0;
    if (_communityCategoryFilter.isNotEmpty) {
      count += 1;
    }
    if (_communityStatusFilter.isNotEmpty) {
      count += 1;
    }
    if (_communitySort != "newest") {
      count += 1;
    }
    return count;
  }

  Future<void> _openCommunityFilterSheet() async {
    var category = _communityCategoryFilter;
    var status = _communityStatusFilter;
    var sort = _communitySort;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);

        return StatefulBuilder(
          builder: (ctx, setModalState) {
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
                        "Filters",
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Refine community posts by category, status, and sort",
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: category,
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
                          setModalState(() {
                            category = value ?? "";
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: status,
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
                          setModalState(() {
                            status = value ?? "";
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: sort,
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
                          setModalState(() {
                            sort = value;
                          });
                        },
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                await _clearCommunityFilters();
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded),
                              label: const Text("Reset"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                setState(() {
                                  _communityCategoryFilter = category;
                                  _communityStatusFilter = status;
                                  _communitySort = sort;
                                });
                                await _applyCommunityFilters();
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text("Apply"),
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
      },
    );
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

    final resolvedUrl = _resolveComplaintMediaUrl(complaint.mediaUrl);
    if (resolvedUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final mediaType = complaint.mediaType.trim().toUpperCase();
    final isVideo = mediaType == "VIDEO" || _looksLikeVideoUrl(resolvedUrl);

    if (isVideo) {
      return _InlineNetworkVideoPlayer(
        url: resolvedUrl,
        headers: _complaintMediaRequestHeaders(),
      );
    }

    if (mediaType == "IMAGE") {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          resolvedUrl,
          headers: _complaintMediaRequestHeaders(),
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
      child: SelectableText(resolvedUrl),
    );
  }

  String _resolveComplaintMediaUrl(String mediaUrl) {
    final trimmed = mediaUrl.trim();
    if (trimmed.isEmpty) {
      return "";
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    final baseUri = Uri.tryParse(widget.dashboardService.apiClient.baseUrl);
    if (baseUri == null) {
      return trimmed;
    }
    if (trimmed.startsWith("//")) {
      return "${baseUri.scheme}:$trimmed";
    }
    return baseUri.resolve(trimmed).toString();
  }

  Map<String, String> _complaintMediaRequestHeaders() {
    final token = widget.session.accessToken.trim();
    if (token.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{"Authorization": "Bearer $token"};
  }

  bool _looksLikeVideoUrl(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return path.endsWith(".mp4") ||
        path.endsWith(".mov") ||
        path.endsWith(".webm") ||
        path.endsWith(".m4v") ||
        path.endsWith(".3gp");
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
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
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
                                label: const Text("Delete", softWrap: false),
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
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
        ? profile?.fullName ?? ""
        : widget.session.username;
    final displayEmail = profile?.email.isNotEmpty == true
        ? profile?.email ?? ""
        : widget.session.email;
    final phoneCountryCode = (profile?.phoneCountryCode ?? "").trim();
    final phoneNumber = (profile?.phoneNumber ?? "").trim();
    final phone = phoneNumber.isNotEmpty
        ? "${phoneCountryCode.isNotEmpty ? "$phoneCountryCode " : ""}$phoneNumber"
            .trim()
        : "";

    bool hasValue(String? value) {
      final normalized = (value ?? "").trim();
      if (normalized.isEmpty) {
        return false;
      }
      return normalized.toLowerCase() != "null";
    }

    final rows = <Widget>[
      _detailRow(label: "Full Name", value: _displayValue(displayName)),
      _detailRow(
        label: "Username",
        value: _displayValue(profile?.username ?? widget.session.username),
      ),
      _detailRow(
        label: "Role",
        value: _formatEnumLabel(profile?.role ?? widget.session.role),
      ),
    ];

    if (hasValue(displayEmail)) {
      rows.add(_detailRow(label: "Email", value: displayEmail.trim()));
    }
    if (hasValue(phone)) {
      rows.add(_detailRow(label: "Phone", value: phone));
    }
    if (hasValue(profile?.department)) {
      rows.add(
        _detailRow(
          label: "Department",
          value: (profile?.department ?? "").trim(),
        ),
      );
    }
    if (hasValue(profile?.jobTitle)) {
      rows.add(
        _detailRow(
          label: "Job Title",
          value: (profile?.jobTitle ?? "").trim(),
        ),
      );
    }

    rows.addAll([
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
        "Student Details",
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
        label: "Assigned Mess",
        value: _displayValue(student?.messAllotment ?? ""),
      ),
      _detailRow(
        label: "Allotted Caterer",
        value: _displayValue(student?.messCatererName ?? ""),
      ),
    ]);

    return rows;
  }

  Future<void> _openProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        final themeLabel =
            widget.themeMode == ThemeMode.dark ? "Light Theme" : "Dark Theme";

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
                              label: const Text(
                                "Change Password",
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                              ),
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
                              label: Text(
                                themeLabel,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                              ),
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
        ? (profile?.fullName ?? "").trim()
        : (student?.name ?? "").trim().isNotEmpty
            ? (student?.name ?? "").trim()
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
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFF0B3D91),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Registration Number: ${registrationNo.isEmpty ? "-" : registrationNo}",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              "Notifications",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF0B3D91),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Column(
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

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          onTap: () => _openNotificationDetails(notification),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withAlpha(120),
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
                            "${hasAttachment ? "Attachment included • " : ""}${_formatDate(notification.createdAt)}",
                          ),
                        ),
                      );
                    },
                  ).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _communityTab() {
    final tabPadding = _tabContentPadding(context);
    final activeFilterCount = _communityActiveFilterCount();
    final accentText = const Color(0xFF8FB3D9);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: tabPadding,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF101214),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF2A2F36),
                      ),
                    ),
                    child: TextField(
                      controller: _communitySearchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _applyCommunityFilters(),
                      style: const TextStyle(color: Color(0xFFE6EEF7)),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: "Search posts",
                        hintStyle: const TextStyle(color: Color(0xFF6C7B8F)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        prefixIcon: const Icon(
                          FluentIcons.search_24_regular,
                          size: 18,
                          color: Color(0xFF7F93AA),
                        ),
                        suffixIcon:
                            _communitySearchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _communitySearchController.clear();
                                      _clearCommunityFilters();
                                    },
                                    icon: const Icon(
                                      FluentIcons.dismiss_24_regular,
                                      size: 18,
                                      color: Color(0xFF7F93AA),
                                    ),
                                    tooltip: "Clear search",
                                  ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _canCreateComplaint ? _openNewComplaintPage : null,
                  style: TextButton.styleFrom(
                    foregroundColor: accentText,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(FluentIcons.add_24_regular, size: 18),
                  label: const Text("New"),
                ),
                const SizedBox(width: 2),
                TextButton.icon(
                  onPressed: _openCommunityFilterSheet,
                  style: TextButton.styleFrom(
                    foregroundColor: accentText,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(FluentIcons.filter_24_regular, size: 18),
                  label: Text(
                    activeFilterCount > 0
                        ? "Filter ($activeFilterCount)"
                        : "Filter",
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              "Community Threads",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _hasCommunityFilters
                ? "Filtered complaint feed"
                : "Search and discuss student complaints",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
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
            )
          else
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
                statusIcon = FluentIcons.clock_24_regular;
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
                        if (complaint.mediaUrl.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _mediaPreview(complaint),
                        ],
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              TextButton.icon(
                                onPressed: voteBusy
                                    ? null
                                    : () => _voteFromCommunityCard(
                                          complaint: complaint,
                                          direction: "up",
                                        ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  complaint.isUpvotedByMe
                                      ? FluentIcons.thumb_like_24_filled
                                      : FluentIcons.thumb_like_24_regular,
                                  size: 18,
                                  color: complaint.isUpvotedByMe
                                      ? _activeVoteColor
                                      : null,
                                ),
                                label: Text("${complaint.upvotes}"),
                              ),
                              const SizedBox(width: 10),
                              TextButton.icon(
                                onPressed: voteBusy
                                    ? null
                                    : () => _voteFromCommunityCard(
                                          complaint: complaint,
                                          direction: "down",
                                        ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  complaint.isDownvotedByMe
                                      ? FluentIcons.thumb_dislike_24_filled
                                      : FluentIcons.thumb_dislike_24_regular,
                                  size: 18,
                                  color: complaint.isDownvotedByMe
                                      ? _activeVoteColor
                                      : null,
                                ),
                                label: Text("${complaint.downvotes}"),
                              ),
                              const SizedBox(width: 10),
                              TextButton.icon(
                                onPressed: () =>
                                    _openComplaintDetails(complaint),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(
                                  FluentIcons.chat_24_regular,
                                  size: 18,
                                ),
                                label: Text("${complaint.replies.length}"),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
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
                  Text(
                    _isStudent &&
                            _profile?.student?.messAllotment
                                    .trim()
                                    .toUpperCase() ==
                                "FOODPARK"
                        ? "Food Park has no fixed weekly menu."
                        : "No menu entries available.",
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth =
                          (constraints.maxWidth - 6).clamp(280.0, 560.0);
                      return SizedBox(
                        height: 370,
                        child: PageView.builder(
                          controller: _messMenuPageController,
                          pageSnapping: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _weekDayOptions.length,
                          onPageChanged: (index) {
                            final dayCode = _weekDayOptions[index].key;
                            if (_selectedMessMenuDay == dayCode) {
                              return;
                            }
                            setState(() {
                              _selectedMessMenuDay = dayCode;
                            });
                          },
                          itemBuilder: (context, index) {
                            final dayEntry = _weekDayOptions[index];
                            final dayMenu = menuByDay[dayEntry.key];
                            final mealRows = <({String label, String value})>[
                              (
                                label: "Breakfast",
                                value: dayMenu?.breakfast ?? "",
                              ),
                              (
                                label: "Lunch",
                                value: dayMenu?.lunch ?? "",
                              ),
                              (
                                label: "Snacks",
                                value: dayMenu?.snacks ?? "",
                              ),
                              (
                                label: "Dinner",
                                value: dayMenu?.dinner ?? "",
                              ),
                            ];

                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Container(
                                width: cardWidth,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF1A1A1A)
                                      : const Color(0xFFFAFAFA),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context)
                                          .shadowColor
                                          .withValues(alpha: 0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _weekDayLabel(dayEntry.key),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 10),
                                    Expanded(
                                      child: dayMenu == null
                                          ? const Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                "Menu is not configured for this day yet.",
                                              ),
                                            )
                                          : SingleChildScrollView(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: mealRows.map((meal) {
                                                  final mealValue =
                                                      meal.value.trim().isEmpty
                                                          ? "No items listed"
                                                          : meal.value.trim();
                                                  return Container(
                                                    width: double.infinity,
                                                    margin:
                                                        const EdgeInsets.only(
                                                      bottom: 8,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        8,
                                                      ),
                                                      color: Theme.of(context)
                                                                  .brightness ==
                                                              Brightness.dark
                                                          ? const Color(
                                                              0xFF252525)
                                                          : const Color(
                                                              0xFFF5F5F5),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color:
                                                              Theme.of(context)
                                                                  .shadowColor
                                                                  .withValues(
                                                                      alpha:
                                                                          0.08),
                                                          blurRadius: 4,
                                                          offset: const Offset(
                                                              0, 1),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          meal.label,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                        ),
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        Text(mealValue),
                                                      ],
                                                    ),
                                                  );
                                                }).toList(growable: false),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
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
                        final selected = _selectedRating >= value;

                        return Semantics(
                          button: true,
                          selected: selected,
                          label: "Rate $value star${value == 1 ? "" : "s"}",
                          child: IconButton(
                            tooltip: "$value star${value == 1 ? "" : "s"}",
                            onPressed: _messActionBusy
                                ? null
                                : () {
                                    setState(() {
                                      _selectedRating = value;
                                    });
                                  },
                            icon: Icon(
                              selected
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: selected ? Colors.amber : Colors.grey,
                              size: 34,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedRating == 0
                          ? "Tap stars to rate"
                          : "$_selectedRating/5 selected",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
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
          if (_isLaundryPerson || _isAdmin)
            _sectionCard(
              title: "QR Code Scanner",
              subtitle: "Scan student laundry QR codes",
              child: Column(
                children: [
                  const Text(
                    "Scan QR codes or search by registration number to log laundry submissions and collections.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        try {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => LaundryQRScannerScreen(
                                session: widget.session,
                                dashboardService: widget.dashboardService,
                              ),
                            ),
                          );
                          await _loadData();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Error: $e"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text("Open Scanner"),
                    ),
                  ),
                ],
              ),
            ),
          _sectionCard(
            title: "Laundry Schedule",
            subtitle: _isLaundryPerson
                ? "View submission and collection status"
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
                    ? const Color(0x233D8FB2)
                    : (isDark
                        ? const Color(0xFF1A1E23)
                        : const Color(0xFFFFFFFF));
                final borderColor = isToday
                    ? const Color(0xFF1483E3)
                    : (highlight ? const Color(0xFF3D8FB2) : edgeColor);

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
                          ? const Color(0xFF2B8BC3)
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
                    "Blue dates are your room's assigned laundry dates this month.",
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
                            FocusManager.instance.primaryFocus?.unfocus();
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

    final showMessTab = !_isLaundryPerson && !_isDepartmentStaff;
    final showLaundryTab = !_isMessManager && !_isDepartmentStaff;
    final showAdminTab = _isAdmin;

    final pageBuilders = <Widget Function()>[
      _homeTab,
      _communityTab,
      if (showMessTab) _messTab,
      if (showLaundryTab) _laundryTab,
      if (showAdminTab) _adminTab,
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

    assert(navItems.length == pageBuilders.length);
    final selectedIndex = _selectedNavIndex.clamp(0, navItems.length - 1);
    final selectedPage = pageBuilders[selectedIndex]();

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
      body: _loading && !_hasDashboardData
          ? const Center(child: CircularProgressIndicator())
          : selectedPage,
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

class _InlineNetworkVideoPlayer extends StatefulWidget {
  const _InlineNetworkVideoPlayer({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String> headers;

  @override
  State<_InlineNetworkVideoPlayer> createState() =>
      _InlineNetworkVideoPlayerState();
}

class _InlineNetworkVideoPlayerState extends State<_InlineNetworkVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers,
    );
    _initializeFuture = _controller!.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasError = true;
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    if (_hasError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Text("Video preview unavailable"),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const CircularProgressIndicator(),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(controller),
              ),
              Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    controller.value.isPlaying
                        ? FluentIcons.pause_24_regular
                        : FluentIcons.play_24_filled,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
      unawaited(_loadAttachment());
    }
  }

  Map<String, String> _requestHeaders() {
    final token = widget.authToken.trim();
    if (token.isEmpty) {
      return <String, String>{};
    }
    return <String, String>{"Authorization": "Bearer $token"};
  }

  Future<void> _loadAttachment() async {
    if (!_hasAttachment) {
      return;
    }

    setState(() {
      _loadingAttachment = true;
      _attachmentError = null;
    });

    try {
      final cachedPath = await widget.attachmentCache.getCachedFilePath(
        notificationId: widget.notification.id,
        attachmentUrl: _attachmentUrl,
        apiBaseUrl: widget.apiBaseUrl,
      );

      final resolvedPath = cachedPath ??
          await widget.attachmentCache.ensureCached(
            notificationId: widget.notification.id,
            attachmentUrl: _attachmentUrl,
            apiBaseUrl: widget.apiBaseUrl,
            headers: _requestHeaders(),
          );

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

      return const Text("Error loading attachment, view in website.");
    }

    final typeHint = _cachedAttachmentPath ?? _attachmentUrl;
    final isPdf = _isPdfFile(typeHint);
    final shouldRenderAsImage = !isPdf;
    final bytes = _cachedAttachmentBytes;
    if (bytes == null) {
      return const Text("Error loading attachment, view in website.");
    }

    if (isPdf) {
      return SizedBox(
        height: 560,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SfPdfViewer.memory(bytes),
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
                bytes,
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
