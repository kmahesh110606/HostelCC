from rest_framework import serializers

from .models import CloakroomEntry, CloakroomRoom


class CloakroomRoomSerializer(serializers.ModelSerializer):
    block_name = serializers.CharField(source="block.block_name", read_only=True)
    display_name = serializers.SerializerMethodField()

    class Meta:
        model = CloakroomRoom
        fields = [
            "id",
            "block",
            "block_name",
            "room_no",
            "item_name",
            "next_token_no",
            "display_name",
            "is_active",
        ]

    def get_display_name(self, obj):
        basket = (obj.item_name or "").strip()
        storage = f"{obj.block.block_name}-{obj.room_no}"
        return f"{basket} @ {storage}" if basket else storage


class CloakroomEntrySerializer(serializers.ModelSerializer):
    student_id = serializers.IntegerField(source="student.id", read_only=True)
    student_name = serializers.CharField(source="student.name", read_only=True)
    student_roll_no = serializers.CharField(source="student.roll_no", read_only=True)
    block_name = serializers.CharField(source="student.block.block_name", read_only=True)
    room_no = serializers.CharField(source="student.room_no", read_only=True)
    status_label = serializers.CharField(source="get_status_display", read_only=True)
    submitted_by_name = serializers.SerializerMethodField()
    returned_by_name = serializers.SerializerMethodField()

    class Meta:
        model = CloakroomEntry
        fields = [
            "id",
            "student_id",
            "student_name",
            "student_roll_no",
            "block_name",
            "room_no",
            "basket_token_no",
            "token_no",
            "item_name",
            "storage_room_no",
            "notes",
            "status",
            "status_label",
            "submitted_at",
            "returned_at",
            "submitted_by_name",
            "returned_by_name",
        ]

    def get_submitted_by_name(self, obj):
        if not obj.submitted_by:
            return ""
        return obj.submitted_by.get_full_name().strip() or obj.submitted_by.username

    def get_returned_by_name(self, obj):
        if not obj.returned_by:
            return ""
        return obj.returned_by.get_full_name().strip() or obj.returned_by.username
