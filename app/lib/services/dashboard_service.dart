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

  Future<void> submitComplaint({
    required String token,
    required int studentId,
    required String category,
    required String text,
  }) async {
    await apiClient.post("/api/complaints/", {
      "student": studentId,
      "category": category,
      "text": text,
    }, token: token);
  }

  Future<void> submitFeedback({
    required String token,
    required int studentId,
    required String menuItem,
    required int rating,
    required String comment,
    required String month,
  }) async {
    await apiClient.post("/api/mess/feedback/", {
      "student": studentId,
      "menu_item": menuItem,
      "rating": rating,
      "comment": comment,
      "month": month,
    }, token: token);
  }

  Future<void> createBlock({
    required String token,
    required String blockName,
  }) async {
    await apiClient.post("/api/hostels/blocks/", {
      "block_name": blockName,
    }, token: token);
  }

  Future<void> createCaterer({
    required String token,
    required String name,
    required String mealTypes,
    required int blockId,
  }) async {
    await apiClient.post("/api/mess/caterers/", {
      "name": name,
      "meal_types": mealTypes,
      "block": blockId,
    }, token: token);
  }

  Future<void> createMenu({
    required String token,
    required String weekDay,
    required String breakfast,
    required String lunch,
    required String snacks,
    required String dinner,
  }) async {
    await apiClient.post("/api/mess/menu/", {
      "week_day": weekDay,
      "breakfast_items": breakfast,
      "lunch_items": lunch,
      "snacks_items": snacks,
      "dinner_items": dinner,
    }, token: token);
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
      "/api/laundry/schedules/qr/$studentId",
      token: token,
    );
  }

  Future<void> votePoll({
    required String token,
    required int studentId,
    required int optionId,
  }) async {
    await apiClient.post("/api/mess/poll/vote/", {
      "student": studentId,
      "option": optionId,
    }, token: token);
  }

  Future<void> requestMessChange({
    required String token,
    required int studentId,
    required String requestedMess,
    required String month,
  }) async {
    await apiClient.post("/api/mess/change/", {
      "student": studentId,
      "requested_mess": requestedMess,
      "month": month,
    }, token: token);
  }
}
