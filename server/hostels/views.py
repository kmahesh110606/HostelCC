from rest_framework import viewsets

from users.permissions import IsAdmin

from .models import HostelBlock, Room
from .serializers import HostelBlockSerializer, RoomSerializer


class HostelBlockViewSet(viewsets.ModelViewSet):
    queryset = HostelBlock.objects.all().order_by("block_name")
    serializer_class = HostelBlockSerializer
    permission_classes = [IsAdmin]


class RoomViewSet(viewsets.ModelViewSet):
    queryset = Room.objects.select_related("block").all().order_by("block__block_name", "room_no")
    serializer_class = RoomSerializer
    permission_classes = [IsAdmin]
