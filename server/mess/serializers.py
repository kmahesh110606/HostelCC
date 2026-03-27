from rest_framework import serializers

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu


class MessMenuSerializer(serializers.ModelSerializer):
    class Meta:
        model = MessMenu
        fields = ["id", "week_day", "breakfast_items", "lunch_items", "snacks_items", "dinner_items"]


class CatererSerializer(serializers.ModelSerializer):
    block_name = serializers.CharField(source="block.block_name", read_only=True)

    class Meta:
        model = Caterer
        fields = ["id", "name", "meal_types", "block", "block_name"]


class FeedbackSerializer(serializers.ModelSerializer):
    class Meta:
        model = Feedback
        fields = ["id", "student", "menu_item", "rating", "comment", "month", "manager_reply", "created_at"]
        read_only_fields = ["manager_reply", "created_at"]


class MenuPollOptionSerializer(serializers.ModelSerializer):
    votes = serializers.IntegerField(source="votes.count", read_only=True)

    class Meta:
        model = MenuPollOption
        fields = ["id", "month", "item_name", "votes"]


class MenuPollVoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = MenuPollVote
        fields = ["id", "student", "option", "created_at"]
        read_only_fields = ["created_at"]


class MessChangeRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = MessChangeRequest
        fields = ["id", "student", "requested_mess", "month", "status", "created_at"]
        read_only_fields = ["status", "created_at"]
