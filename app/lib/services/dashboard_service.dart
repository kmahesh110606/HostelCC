import "../models/app_models.dart";
import "api_client.dart";

class DashboardService {
  DashboardService({required this.apiClient});

  final ApiClient apiClient;

  Future<List<MessMenu>> getMenus(String token) async {
    final rows = await apiClient.getList("/api/mess/menu/", token: token);
    return rows
        .map((e) => MessMenu.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ComplaintItem>> getComplaints(String token) async {
    final rows = await apiClient.getList("/api/complaints/", token: token);
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
    required int studentId,
    required String category,
    required String text,
  }) async {
    await apiClient.post(
        "/api/complaints/",
        {
          "student": studentId,
          "category": category,
          "text": text,
        },
        token: token);
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
    return MessFeedbackItem.fromJson(row);
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
    final updated = await apiClient.post(
      "/api/complaints/$complaintId/vote/",
      {"direction": direction},
      token: token,
    );
    return ComplaintItem.fromJson(updated);
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
    return ComplaintItem.fromJson(updated);
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
    required String weekDay,
    required String breakfast,
    required String lunch,
    required String snacks,
    required String dinner,
  }) async {
    await apiClient.post(
        "/api/mess/menu/",
        {
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

  Future<void> scanLaundryQr({
    required String token,
    required int studentId,
    required String qrToken,
    required String eventType,
  }) async {
    await apiClient.post(
      "/api/laundry/schedules/scan/",
      {
        "student_id": studentId,
        "qr_token": qrToken,
        "event_type": eventType,
      },
      token: token,
    );
  }

  Future<void> votePoll({
    required String token,
    required int studentId,
    required int optionId,
  }) async {
    await apiClient.post(
        "/api/mess/poll/vote/",
        {
          "student": studentId,
          "option": optionId,
        },
        token: token);
  }

  Future<List<MessPollOptionItem>> getPollOptions(String token) async {
    final rows = await apiClient.getList("/api/mess/poll/", token: token);
    return rows
        .map((e) => MessPollOptionItem.fromJson(e as Map<String, dynamic>))
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
    required int studentId,
    required String requestedMess,
    required String month,
  }) async {
    await apiClient.post(
        "/api/mess/change/",
        {
          "student": studentId,
          "requested_mess": requestedMess,
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
