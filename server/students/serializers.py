from rest_framework import serializers

from .models import Student


class StudentSerializer(serializers.ModelSerializer):
    block_name = serializers.CharField(source="block.block_name", read_only=True)

    class Meta:
        model = Student
        fields = [
            "id",
            "user",
            "name",
            "roll_no",
            "block",
            "block_name",
            "room",
            "room_no",
            "points_balance",
            "mess_allotment",
        ]
