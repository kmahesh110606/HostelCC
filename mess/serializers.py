from rest_framework import serializers

from mess.options import DEFAULT_MESS_TYPE, canonical_mess_type
from students.utils import resolve_student_for_user

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu


class MessMenuSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        raw_mess_type = attrs.get("mess_type")
        if raw_mess_type is None and self.instance is not None:
            raw_mess_type = self.instance.mess_type

        if canonical_mess_type(raw_mess_type) == "FOODPARK":
            raise serializers.ValidationError(
                {
                    "mess_type": "Food Park menu changes daily and does not use a fixed weekly menu.",
                }
            )

        return attrs

    class Meta:
        model = MessMenu
        fields = ["id", "mess_type", "week_day", "breakfast_items", "lunch_items", "snacks_items", "dinner_items"]


class CatererSerializer(serializers.ModelSerializer):
    block_name = serializers.CharField(source="block.block_name", read_only=True)
    mess_type = serializers.CharField(source="meal_types", read_only=True)

    class Meta:
        model = Caterer
        fields = ["id", "name", "meal_types", "mess_type", "block", "block_name"]


class FeedbackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feedback
        fields = [
            "id",
            "student",
            "week_day",
            "meal_time",
            "menu_item",
            "rating",
            "comment",
            "month",
            "manager_reply",
            "created_at",
        ]
        read_only_fields = ["student", "month", "manager_reply", "created_at"]

    def validate_rating(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError("Rating must be between 1 and 5.")
        return value

    def validate_menu_item(self, value):
        if not value.strip():
            raise serializers.ValidationError("Menu item is required.")
        return value.strip()


class MenuPollOptionSerializer(serializers.ModelSerializer):
    votes = serializers.IntegerField(source="votes.count", read_only=True)

    class Meta:
        model = MenuPollOption
        fields = ["id", "month", "item_name", "poll_type", "votes"]


class MenuPollVoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = MenuPollVote
        fields = ["id", "student", "option", "created_at"]
        read_only_fields = ["created_at"]


class MessChangeRequestSerializer(serializers.ModelSerializer):
    requested_caterer_name = serializers.CharField(source="requested_mess", read_only=True)
    requested_caterer_id = serializers.IntegerField(write_only=True, required=True)

    class Meta:
        model = MessChangeRequest
        fields = [
            "id",
            "student",
            "requested_mess",
            "requested_caterer_id",
            "requested_caterer_name",
            "month",
            "status",
            "created_at",
        ]
        read_only_fields = ["student", "requested_mess", "status", "created_at"]

    def validate(self, attrs):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        student = resolve_student_for_user(user)

        if not student:
            raise serializers.ValidationError("Only mapped students can request mess change.")

        requested_caterer_id = attrs.get("requested_caterer_id")
        normalized_type = canonical_mess_type(student.mess_allotment) or DEFAULT_MESS_TYPE
        selected_caterer = Caterer.objects.filter(
            id=requested_caterer_id,
            block_id=student.block_id,
            meal_types=normalized_type,
        ).first()
        if not selected_caterer:
            raise serializers.ValidationError(
                {
                    "requested_caterer_id": (
                        "Selected caterer is not available for your block and mess type."
                    )
                }
            )

        attrs["student"] = student
        attrs["requested_mess"] = selected_caterer.name
        return attrs

    def create(self, validated_data):
        validated_data.pop("requested_caterer_id", None)
        return super().create(validated_data)
