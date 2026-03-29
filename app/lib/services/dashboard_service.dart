import "../models/app_models.dart";
import "api_client.dart";

class DashboardService {
  DashboardService({required this.apiClient});

  final ApiClient apiClient;

  Map<String, dynamic> _unwrapDataMap(Map<String, dynamic> response) {
    final data = response["data"];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return response;
  }

  String _buildPath(String basePath, Map<String, String> params) {
    if (params.isEmpty) {
      return basePath;
    }
    final query = params.entries
        .map(
          (entry) =>
              "${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}",
        )
        .join("&");
    return "$basePath?$query";
  }

  void _addQueryParam(
    Map<String, String> params,
    String key,
    String? value,
  ) {
    final trimmed = value?.trim() ?? "";
    if (trimmed.isNotEmpty) {
      params[key] = trimmed;
    }
  }

  Future<List<MessMenu>> getMenus(String token, {String? messType}) async {
    final path = (messType != null && messType.trim().isNotEmpty)
        ? "/api/mess/menu/?mess_type=${Uri.encodeQueryComponent(messType.trim())}"
        : "/api/mess/menu/";
    final rows = await apiClient.getList(path, token: token);
    return rows
        .map((e) => MessMenu.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ComplaintItem>> getComplaints(
    String token, {
    String? query,
    String? category,
    String? mediaType,
    String? status,
    String? block,
    String? sort,
  }) async {
    final params = <String, String>{};
    _addQueryParam(params, "q", query);
    _addQueryParam(params, "category", category);
    _addQueryParam(params, "media_type", mediaType);
    _addQueryParam(params, "status", status);
    _addQueryParam(params, "block", block);
    _addQueryParam(params, "sort", sort);

    final rows = await apiClient.getList(
      _buildPath("/api/complaints/", params),
      token: token,
    );
    return rows
        .map((e) => ComplaintItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LaundrySchedule>> getSchedules(String token) async {
    final rows = await apiClient.getList(
      "/api/laundry/schedules/",
      token: token,
    );
    return rows
        .map((e) => LaundrySchedule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CatererItem>> getCaterers(String token) async {
    final rows = await apiClient.getList("/api/mess/caterers/", token: token);
    return rows
        .map((e) => CatererItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppNotificationItem>> getNotifications(String token) async {
    final rows =
        await apiClient.getList("/api/auth/notifications/", token: token);
    return rows
        .map((e) => AppNotificationItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserProfileItem> getMyProfile(String token) async {
    final row = await apiClient.getMap("/api/auth/me/", token: token);
    return UserProfileItem.fromJson(row);
  }

  Future<void> submitComplaint({
    required String token,
    required String category,
    required String text,
    String? mediaFilePath,
  }) async {
    final hasMedia = mediaFilePath != null && mediaFilePath.trim().isNotEmpty;
    if (hasMedia) {
      await apiClient.postMultipart(
        "/api/complaints/",
        {
          "category": category,
          "text": text,
        },
        token: token,
        fileFieldName: "media",
        filePath: mediaFilePath.trim(),
      );
      return;
    }

    await apiClient.post(
      "/api/complaints/",
      {
        "category": category,
        "text": text,
      },
      token: token,
    );
  }

  Future<void> deleteComplaint({
    required String token,
    required int complaintId,
  }) async {
    await apiClient.delete(
      "/api/complaints/$complaintId/",
      token: token,
    );
  }

  Future<void> submitFeedback({
    required String token,
    int? studentId,
    required String weekDay,
    required String mealTime,
    required String menuItem,
    required int rating,
    required String comment,
  }) async {
    final payload = <String, dynamic>{
      "week_day": weekDay,
      "meal_time": mealTime,
      "menu_item": menuItem,
      "rating": rating,
      "comment": comment,
    };
    if (studentId != null) {
      payload["student"] = studentId;
    }

    await apiClient.post(
      "/api/mess/feedback/",
      payload,
      token: token,
    );
  }

  Future<List<MessFeedbackItem>> getMessFeedbacks(String token) async {
    final rows = await apiClient.getList("/api/mess/feedback/", token: token);
    return rows
        .map((e) => MessFeedbackItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MessFeedbackItem> replyToFeedback({
    required String token,
    required int feedbackId,
    required String managerReply,
  }) async {
    final row = await apiClient.post(
      "/api/mess/feedback/$feedbackId/reply/",
      {"manager_reply": managerReply},
      token: token,
    );
    return MessFeedbackItem.fromJson(_unwrapDataMap(row));
  }

  Future<ComplaintItem> addComplaintReply({
    required String token,
    required int complaintId,
    required String text,
  }) async {
    await apiClient.post(
      "/api/complaints/$complaintId/reply/",
      {"text": text},
      token: token,
    );
    final complaint = await apiClient.getMap(
      "/api/complaints/$complaintId/",
      token: token,
    );
    return ComplaintItem.fromJson(complaint);
  }

  Future<ComplaintItem> voteComplaint({
    required String token,
    required int complaintId,
    required String direction,
  }) async {
    await apiClient.post(
      "/api/complaints/$complaintId/vote/",
      {"direction": direction},
      token: token,
    );
    final complaint = await apiClient.getMap(
      "/api/complaints/$complaintId/",
      token: token,
    );
    return ComplaintItem.fromJson(complaint);
  }

  Future<ComplaintItem> setComplaintStatus({
    required String token,
    required int complaintId,
    required String status,
  }) async {
    final updated = await apiClient.post(
      "/api/complaints/$complaintId/set-status/",
      {"status": status},
      token: token,
    );
    return ComplaintItem.fromJson(_unwrapDataMap(updated));
  }

  Future<void> createBlock({
    required String token,
    required String blockName,
  }) async {
    await apiClient.post(
        "/api/hostels/blocks/",
        {
          "block_name": blockName,
        },
        token: token);
  }

  Future<void> createCaterer({
    required String token,
    required String name,
    required String mealTypes,
    required int blockId,
  }) async {
    await apiClient.post(
        "/api/mess/caterers/",
        {
          "name": name,
          "meal_types": mealTypes,
          "block": blockId,
        },
        token: token);
  }

  Future<void> createMenu({
    required String token,
    required String messType,
    required String weekDay,
    required String breakfast,
    required String lunch,
    required String snacks,
    required String dinner,
  }) async {
    await apiClient.post(
        "/api/mess/menu/",
        {
          "mess_type": messType,
          "week_day": weekDay,
          "breakfast_items": breakfast,
          "lunch_items": lunch,
          "snacks_items": snacks,
          "dinner_items": dinner,
        },
        token: token);
  }

  Future<void> markLaundrySubmission({
    required String token,
    required int scheduleId,
  }) async {
    await apiClient.post(
      "/api/laundry/schedules/$scheduleId/submission/",
      {},
      token: token,
    );
  }

  Future<void> markLaundryCollection({
    required String token,
    required int scheduleId,
  }) async {
    await apiClient.post(
      "/api/laundry/schedules/$scheduleId/collection/",
      {},
      token: token,
    );
  }

  Future<Map<String, dynamic>> getLaundryQr({
    required String token,
    required int studentId,
  }) {
    return apiClient.getMap(
      "/api/laundry/schedules/qr/$studentId/",
      token: token,
    );
  }

  Future<Map<String, dynamic>> scanLaundryQr({
    required String token,
    int? studentId,
    String? qrToken,
    String? qrText,
    required String eventType,
  }) async {
    final payload = <String, dynamic>{"event_type": eventType};

    final cleanedQrText = (qrText ?? "").trim();
    final cleanedQrToken = (qrToken ?? "").trim();
    if (cleanedQrText.isNotEmpty) {
      payload["qr_text"] = cleanedQrText;
    }
    if (studentId != null) {
      payload["student_id"] = studentId;
    }
    if (cleanedQrToken.isNotEmpty) {
      payload["qr_token"] = cleanedQrToken;
    }

    if (!payload.containsKey("qr_text") &&
        (!payload.containsKey("student_id") ||
            !payload.containsKey("qr_token"))) {
      throw ArgumentError("Provide qrText or both studentId and qrToken.");
    }

    final response = await apiClient.post(
      "/api/laundry/schedules/scan/",
      payload,
      token: token,
    );

    return _unwrapDataMap(response);
  }

  Future<void> votePoll({
    required String token,
    required int optionId,
  }) async {
    await apiClient.post(
        "/api/mess/poll/vote/",
        {
          "option": optionId,
        },
        token: token);
  }

  Future<List<MessPollOptionItem>> getPollOptions(
    String token, {
    String? month,
  }) async {
    final params = <String, String>{};
    _addQueryParam(params, "month", month);

    final rows = await apiClient.getList(
      _buildPath("/api/mess/poll/", params),
      token: token,
    );
    return rows
        .map((e) => MessPollOptionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LeastRatedMessItem>> getLeastRatedMessItems(
    String token, {
    int limit = 10,
  }) async {
    final rows = await apiClient.getList(
      "/api/mess/feedback/least-rated/?limit=$limit",
      token: token,
    );

    return rows
        .map((e) => LeastRatedMessItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createPollOption({
    required String token,
    required String month,
    required String itemName,
    required String pollType,
  }) async {
    await apiClient.post(
      "/api/mess/poll/",
      {
        "month": month,
        "item_name": itemName,
        "poll_type": pollType,
      },
      token: token,
    );
  }

  Future<void> requestMessChange({
    required String token,
    required int requestedCatererId,
    required String month,
  }) async {
    await apiClient.post(
        "/api/mess/change/",
        {
          "requested_caterer_id": requestedCatererId,
          "month": month,
        },
        token: token);
  }

  Future<List<MessChangeRequestItem>> getMessChangeRequests(
      String token) async {
    final rows = await apiClient.getList("/api/mess/change/", token: token);
    return rows
        .map((e) => MessChangeRequestItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveMessChange({
    required String token,
    required int requestId,
  }) async {
    await apiClient.post(
      "/api/mess/change/$requestId/approve/",
      {},
      token: token,
    );
  }

  Future<void> rejectMessChange({
    required String token,
    required int requestId,
  }) async {
    await apiClient.post(
      "/api/mess/change/$requestId/reject/",
      {},
      token: token,
    );
  }
}
