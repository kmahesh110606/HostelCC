from rest_framework import serializers

from .models import HostelBlock, Room


class HostelBlockSerializer(serializers.ModelSerializer):
    class Meta:
        model = HostelBlock
        fields = ["id", "block_name"]


class RoomSerializer(serializers.ModelSerializer):
    block_name = serializers.CharField(source="block.block_name", read_only=True)

    class Meta:
        model = Room
        fields = ["id", "room_no", "capacity", "block", "block_name"]
