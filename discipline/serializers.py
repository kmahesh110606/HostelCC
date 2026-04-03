from rest_framework import serializers

from students.models import Student

from .models import DisciplineCase
from .policies import POLICY_BY_CODE, VIOLATION_POLICIES, action_for_occurrence


class DisciplineCaseSerializer(serializers.ModelSerializer):
    student_roll_no = serializers.CharField(source="student.roll_no", read_only=True)
    student_name = serializers.CharField(source="student.name", read_only=True)
    block_name = serializers.CharField(source="student.block.block_name", read_only=True)
    room_no = serializers.CharField(source="student.room_no", read_only=True)
    violation_title = serializers.SerializerMethodField()
    created_by_name = serializers.SerializerMethodField()
    returned_by_name = serializers.SerializerMethodField()
    is_id_card_active_confiscation = serializers.BooleanField(read_only=True)

    class Meta:
        model = DisciplineCase
        fields = [
            "id",
            "student",
            "student_roll_no",
            "student_name",
            "block_name",
            "room_no",
            "violation_code",
            "violation_title",
            "occurrence_number",
            "action_taken",
            "notes",
            "id_card_confiscated",
            "id_card_confiscated_at",
            "id_card_returned_at",
            "return_notes",
            "is_id_card_active_confiscation",
            "created_by",
            "created_by_name",
            "returned_by",
            "returned_by_name",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "occurrence_number",
            "id_card_confiscated",
            "id_card_confiscated_at",
            "id_card_returned_at",
            "created_by",
            "returned_by",
            "created_at",
            "updated_at",
        ]

    def get_violation_title(self, obj):
        policy = POLICY_BY_CODE.get(obj.violation_code)
        return policy["title"] if policy else obj.violation_code

    def get_created_by_name(self, obj):
        if not obj.created_by:
            return ""
        return obj.created_by.get_full_name().strip() or obj.created_by.username

    def get_returned_by_name(self, obj):
        if not obj.returned_by:
            return ""
        return obj.returned_by.get_full_name().strip() or obj.returned_by.username


class DisciplineCaseCreateSerializer(serializers.Serializer):
    reg_no = serializers.CharField(max_length=30, required=False, allow_blank=True)
    student_id = serializers.IntegerField(required=False)
    violation_code = serializers.CharField(max_length=80)
    action_taken = serializers.CharField(max_length=255, required=False, allow_blank=True)
    notes = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        reg_no = (attrs.get("reg_no") or "").strip().upper()
        student_id = attrs.get("student_id")

        student = None
        if reg_no:
            student = Student.objects.select_related("block", "room", "user").filter(roll_no__iexact=reg_no).first()
        elif student_id:
            student = Student.objects.select_related("block", "room", "user").filter(id=student_id).first()

        if not student:
            raise serializers.ValidationError({"detail": "Student not found for the given registration number."})

        violation_code = (attrs.get("violation_code") or "").strip().upper()
        if violation_code not in POLICY_BY_CODE:
            raise serializers.ValidationError({"violation_code": "Invalid violation code."})

        previous_count = DisciplineCase.objects.filter(
            student=student,
            violation_code=violation_code,
        ).count()
        occurrence_number = previous_count + 1

        action_taken = (attrs.get("action_taken") or "").strip()
        if not action_taken:
            action_taken = action_for_occurrence(violation_code, occurrence_number)

        attrs["student"] = student
        attrs["violation_code"] = violation_code
        attrs["occurrence_number"] = occurrence_number
        attrs["action_taken"] = action_taken
        attrs["notes"] = (attrs.get("notes") or "").strip()
        return attrs


class DisciplineReturnSerializer(serializers.Serializer):
    return_notes = serializers.CharField(required=False, allow_blank=True)


def build_policy_payload() -> list[dict]:
    payload = []
    for policy in VIOLATION_POLICIES:
        payload.append(
            {
                "code": policy["code"],
                "title": policy["title"],
                "actions": list(policy.get("actions") or []),
            }
        )
    return payload
