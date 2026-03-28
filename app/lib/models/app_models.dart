class MessMenu {
  const MessMenu({
    required this.weekDay,
    required this.breakfast,
    required this.lunch,
    required this.snacks,
    required this.dinner,
  });

  final String weekDay;
  final String breakfast;
  final String lunch;
  final String snacks;
  final String dinner;

  factory MessMenu.fromJson(Map<String, dynamic> json) => MessMenu(
        weekDay: (json["week_day"] ?? "").toString(),
        breakfast: (json["breakfast_items"] ?? "").toString(),
        lunch: (json["lunch_items"] ?? "").toString(),
        snacks: (json["snacks_items"] ?? "").toString(),
        dinner: (json["dinner_items"] ?? "").toString(),
      );
}

class MessFeedbackItem {
  const MessFeedbackItem({
    required this.id,
    required this.studentId,
    required this.weekDay,
    required this.mealTime,
    required this.menuItem,
    required this.rating,
    required this.comment,
    required this.month,
    required this.managerReply,
    required this.createdAt,
  });

  final int id;
  final int? studentId;
  final String weekDay;
  final String mealTime;
  final String menuItem;
  final int rating;
  final String comment;
  final String month;
  final String managerReply;
  final DateTime? createdAt;

  factory MessFeedbackItem.fromJson(Map<String, dynamic> json) =>
      MessFeedbackItem(
        id: (json["id"] ?? 0) as int,
        studentId: json["student"] is int ? json["student"] as int : null,
        weekDay: (json["week_day"] ?? "").toString(),
        mealTime: (json["meal_time"] ?? "").toString(),
        menuItem: (json["menu_item"] ?? "").toString(),
        rating: (json["rating"] ?? 0) as int,
        comment: (json["comment"] ?? "").toString(),
        month: (json["month"] ?? "").toString(),
        managerReply: (json["manager_reply"] ?? "").toString(),
        createdAt: json["created_at"] != null
            ? DateTime.tryParse(json["created_at"].toString())
            : null,
      );
}

class MessPollOptionItem {
  const MessPollOptionItem({
    required this.id,
    required this.month,
    required this.itemName,
    required this.pollType,
    required this.votes,
  });

  final int id;
  final String month;
  final String itemName;
  final String pollType;
  final int votes;

  factory MessPollOptionItem.fromJson(Map<String, dynamic> json) =>
      MessPollOptionItem(
        id: (json["id"] ?? 0) as int,
        month: (json["month"] ?? "").toString(),
        itemName: (json["item_name"] ?? "").toString(),
        pollType: (json["poll_type"] ?? "").toString(),
        votes: (json["votes"] ?? 0) as int,
      );
}

class MessChangeRequestItem {
  const MessChangeRequestItem({
    required this.id,
    required this.studentId,
    required this.requestedMess,
    required this.month,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int? studentId;
  final String requestedMess;
  final String month;
  final String status;
  final DateTime? createdAt;

  factory MessChangeRequestItem.fromJson(Map<String, dynamic> json) =>
      MessChangeRequestItem(
        id: (json["id"] ?? 0) as int,
        studentId: json["student"] is int ? json["student"] as int : null,
        requestedMess: (json["requested_mess"] ?? "").toString(),
        month: (json["month"] ?? "").toString(),
        status: (json["status"] ?? "").toString(),
        createdAt: json["created_at"] != null
            ? DateTime.tryParse(json["created_at"].toString())
            : null,
      );
}

class ComplaintItem {
  const ComplaintItem({
    required this.id,
    required this.studentId,
    required this.authorName,
    required this.studentName,
    required this.registrationNo,
    required this.blockName,
    required this.roomNo,
    required this.category,
    required this.text,
    required this.mediaUrl,
    required this.mediaType,
    required this.status,
    required this.statusLabel,
    required this.upvotes,
    required this.downvotes,
    required this.replies,
    required this.createdAt,
    required this.canManage,
    required this.canDelete,
  });

  final int id;
  final int? studentId;
  final String authorName;
  final String studentName;
  final String registrationNo;
  final String blockName;
  final String roomNo;
  final String category;
  final String text;
  final String mediaUrl;
  final String mediaType;
  final String status;
  final String statusLabel;
  final int upvotes;
  final int downvotes;
  final List<ComplaintReplyItem> replies;
  final DateTime? createdAt;
  final bool canManage;
  final bool canDelete;

  factory ComplaintItem.fromJson(Map<String, dynamic> json) => ComplaintItem(
        id: (json["id"] ?? 0) as int,
        studentId: json["student"] is int ? json["student"] as int : null,
        authorName: (json["author_name"] ?? "").toString(),
        studentName: (json["student_name"] ?? "").toString(),
        registrationNo: (json["registration_no"] ?? "").toString(),
        blockName: (json["block_name"] ?? "").toString(),
        roomNo: (json["room_no"] ?? "").toString(),
        category: (json["category"] ?? "").toString(),
        text: (json["text"] ?? "").toString(),
        mediaUrl: (json["media_url"] ?? "").toString(),
        mediaType: (json["media_type"] ?? "TEXT").toString(),
        status: (json["status"] ?? "").toString(),
        statusLabel: (json["status_label"] ?? "").toString(),
        upvotes: (json["upvotes"] ?? 0) as int,
        downvotes: (json["downvotes"] ?? 0) as int,
        replies: ((json["replies"] as List<dynamic>?) ?? const <dynamic>[])
            .map((reply) =>
                ComplaintReplyItem.fromJson(reply as Map<String, dynamic>))
            .toList(),
        createdAt: json["created_at"] != null
            ? DateTime.tryParse(json["created_at"].toString())
            : null,
        canManage: json["can_manage"] == true,
        canDelete: json["can_delete"] == true,
      );
}

class ComplaintReplyItem {
  const ComplaintReplyItem({
    required this.id,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  factory ComplaintReplyItem.fromJson(Map<String, dynamic> json) =>
      ComplaintReplyItem(
        id: (json["id"] ?? 0) as int,
        authorName: (json["author_name"] ?? "").toString(),
        text: (json["text"] ?? "").toString(),
        createdAt: json["created_at"] != null
            ? DateTime.tryParse(json["created_at"].toString())
            : null,
      );
}

class LaundrySchedule {
  const LaundrySchedule({
    required this.id,
    required this.day,
    required this.submission,
    required this.collection,
  });

  final int id;
  final String day;
  final bool submission;
  final bool collection;

  factory LaundrySchedule.fromJson(Map<String, dynamic> json) =>
      LaundrySchedule(
        id: (json["id"] ?? 0) as int,
        day: (json["day_of_week"] ?? "").toString(),
        submission: json["submission_status"] == true,
        collection: json["collection_status"] == true,
      );
}

class CatererItem {
  const CatererItem({
    required this.name,
    required this.blockName,
    required this.mealTypes,
  });

  final String name;
  final String blockName;
  final String mealTypes;

  factory CatererItem.fromJson(Map<String, dynamic> json) => CatererItem(
        name: (json["name"] ?? "").toString(),
        blockName: (json["block_name"] ?? "").toString(),
        mealTypes: (json["meal_types"] ?? "").toString(),
      );
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.level,
    required this.audience,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String message;
  final String level;
  final String audience;
  final DateTime? createdAt;

  factory AppNotificationItem.fromJson(Map<String, dynamic> json) =>
      AppNotificationItem(
        id: (json["id"] ?? 0) as int,
        title: (json["title"] ?? "").toString(),
        message: (json["message"] ?? "").toString(),
        level: (json["level"] ?? "INFO").toString(),
        audience: (json["audience"] ?? "ALL").toString(),
        createdAt: json["created_at"] != null
            ? DateTime.tryParse(json["created_at"].toString())
            : null,
      );
}

class UserProfileItem {
  const UserProfileItem({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.role,
    required this.phoneCountryCode,
    required this.phoneNumber,
    required this.jobTitle,
    required this.department,
    required this.assignedMessName,
    required this.mustChangePassword,
    required this.isEmailVerified,
    required this.isActive,
    required this.student,
  });

  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String fullName;
  final String role;
  final String phoneCountryCode;
  final String phoneNumber;
  final String jobTitle;
  final String department;
  final String assignedMessName;
  final bool mustChangePassword;
  final bool isEmailVerified;
  final bool isActive;
  final UserProfileStudentItem? student;

  int? get studentId => student?.id;

  factory UserProfileItem.fromJson(Map<String, dynamic> json) =>
      UserProfileItem(
        id: (json["id"] ?? 0) as int,
        username: (json["username"] ?? "").toString(),
        email: (json["email"] ?? "").toString(),
        firstName: (json["first_name"] ?? "").toString(),
        lastName: (json["last_name"] ?? "").toString(),
        fullName: (json["full_name"] ?? "").toString(),
        role: (json["role"] ?? "").toString(),
        phoneCountryCode: (json["phone_country_code"] ?? "").toString(),
        phoneNumber: (json["phone_number"] ?? "").toString(),
        jobTitle: (json["job_title"] ?? "").toString(),
        department: (json["department"] ?? "").toString(),
        assignedMessName: (json["assigned_mess_name"] ?? "").toString(),
        mustChangePassword: json["must_change_password"] == true,
        isEmailVerified: json["is_email_verified"] == true,
        isActive: json["is_active"] == true,
        student: json["student"] is Map<String, dynamic>
            ? UserProfileStudentItem.fromJson(
                json["student"] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "username": username,
        "email": email,
        "first_name": firstName,
        "last_name": lastName,
        "full_name": fullName,
        "role": role,
        "phone_country_code": phoneCountryCode,
        "phone_number": phoneNumber,
        "job_title": jobTitle,
        "department": department,
        "assigned_mess_name": assignedMessName,
        "must_change_password": mustChangePassword,
        "is_email_verified": isEmailVerified,
        "is_active": isActive,
        "student": student?.toJson(),
      };
}

class UserProfileStudentItem {
  const UserProfileStudentItem({
    required this.id,
    required this.name,
    required this.rollNo,
    required this.blockName,
    required this.roomNo,
    required this.messAllotment,
    required this.pointsBalance,
  });

  final int id;
  final String name;
  final String rollNo;
  final String blockName;
  final String roomNo;
  final String messAllotment;
  final String pointsBalance;

  factory UserProfileStudentItem.fromJson(Map<String, dynamic> json) =>
      UserProfileStudentItem(
        id: (json["id"] ?? 0) as int,
        name: (json["name"] ?? "").toString(),
        rollNo: (json["roll_no"] ?? "").toString(),
        blockName: (json["block_name"] ?? "").toString(),
        roomNo: (json["room_no"] ?? "").toString(),
        messAllotment: (json["mess_allotment"] ?? "").toString(),
        pointsBalance: (json["points_balance"] ?? "0").toString(),
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "roll_no": rollNo,
        "block_name": blockName,
        "room_no": roomNo,
        "mess_allotment": messAllotment,
        "points_balance": pointsBalance,
      };
}
