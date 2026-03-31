from rest_framework import serializers

from mess.models import Caterer

from .models import Student


class StudentSerializer(serializers.ModelSerializer):
    block_name = serializers.CharField(source="block.block_name", read_only=True)
    mess_caterer_name = serializers.CharField(source="mess_caterer.name", read_only=True)
    mess_caterer = serializers.PrimaryKeyRelatedField(
        queryset=Caterer.objects.select_related("block").all(),
        required=False,
        allow_null=True,
    )

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
            "mess_caterer",
            "mess_caterer_name",
            "mess_allotment",
        ]

    def validate(self, attrs):
        block = attrs.get("block") or getattr(self.instance, "block", None)
        mess_caterer = attrs.get("mess_caterer", getattr(self.instance, "mess_caterer", None))

        if mess_caterer and block and mess_caterer.block_id != block.id:
            raise serializers.ValidationError({"mess_caterer": "Selected caterer must belong to the student's block."})

        if mess_caterer:
            attrs["mess_allotment"] = mess_caterer.meal_types

        return attrs
