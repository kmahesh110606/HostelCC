from rest_framework import serializers

from .models import LaundryEvent, LaundrySchedule


class LaundryScheduleSerializer(serializers.ModelSerializer):
    student_roll_no = serializers.CharField(source="student.roll_no", read_only=True)

    class Meta:
        model = LaundrySchedule
        fields = [
            "id",
            "student",
            "student_roll_no",
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
