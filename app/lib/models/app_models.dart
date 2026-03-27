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

class ComplaintItem {
  const ComplaintItem({
    required this.id,
    required this.category,
    required this.text,
    required this.status,
  });

  final int id;
  final String category;
  final String text;
  final String status;

  factory ComplaintItem.fromJson(Map<String, dynamic> json) => ComplaintItem(
    id: (json["id"] ?? 0) as int,
    category: (json["category"] ?? "").toString(),
    text: (json["text"] ?? "").toString(),
    status: (json["status"] ?? "").toString(),
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
