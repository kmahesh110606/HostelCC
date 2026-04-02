from rest_framework import serializers

from .models import LaundryEvent, LaundryHoliday, LaundryRoomRange, LaundrySchedule


class LaundryScheduleSerializer(serializers.ModelSerializer):
    student_roll_no = serializers.CharField(source="student.roll_no", read_only=True)
    block_name = serializers.CharField(source="student.block.block_name", read_only=True)
    room_no = serializers.CharField(source="student.room_no", read_only=True)

    class Meta:
        model = LaundrySchedule
        fields = [
            "id",
            "student",
            "student_roll_no",
            "block_name",
            "room_no",
            "day_of_week",
            "holidays",
            "qr_token",
            "submission_status",
            "collection_status",
            "last_submission_at",
            "due_collection_by",
        ]


class LaundryEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = LaundryEvent
        fields = ["id", "student", "schedule", "event_type", "scanned_by", "created_at"]
        read_only_fields = ["scanned_by", "created_at"]


class LaundryRoomRangeSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        day_of_week = attrs.get("day_of_week", getattr(self.instance, "day_of_week", None))
        scheduled_date = attrs.get("scheduled_date", getattr(self.instance, "scheduled_date", None))
        if not day_of_week and not scheduled_date:
            raise serializers.ValidationError("Provide either scheduled_date or day_of_week.")
        return attrs

    class Meta:
        model = LaundryRoomRange
        fields = [
            "id",
            "block_name",
            "day_of_week",
            "scheduled_date",
            "room_from",
            "room_to",
            "is_active",
            "created_at",
        ]
        read_only_fields = ["created_at"]


class LaundryHolidaySerializer(serializers.ModelSerializer):
    class Meta:
        model = LaundryHoliday
        fields = ["id", "holiday_date", "name", "is_active", "created_at"]
        read_only_fields = ["created_at"]
