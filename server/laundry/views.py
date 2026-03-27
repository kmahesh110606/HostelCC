from django.core.cache import cache
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from students.models import Student
from users.permissions import IsAdmin, IsLaundryPerson

from .models import LaundryEvent, LaundrySchedule
from .serializers import LaundryEventSerializer, LaundryScheduleSerializer


class LaundryScheduleViewSet(viewsets.ModelViewSet):
    queryset = LaundrySchedule.objects.select_related("student").all()
    serializer_class = LaundryScheduleSerializer

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy", "mark_submission", "mark_collection"]:
            permission_classes = [IsLaundryPerson]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    @action(detail=False, methods=["get"], url_path=r"qr/(?P<student_id>[^/.]+)")
    def qr_for_student(self, request, student_id=None):
        cache_key = f"laundry_qr_{student_id}"
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)

        schedule = LaundrySchedule.objects.select_related("student").get(student_id=student_id)
        payload = {"student_id": student_id, "qr_token": schedule.qr_token, "day_of_week": schedule.day_of_week}
        cache.set(cache_key, payload, timeout=300)
        return Response(payload)

    @action(detail=True, methods=["post"], url_path="submission")
    def mark_submission(self, request, pk=None):
        schedule = self.get_object()
        try:
            schedule.mark_submission()
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        LaundryEvent.objects.create(
            student=schedule.student,
            schedule=schedule,
            event_type=LaundryEvent.EventType.SUBMISSION,
            scanned_by=request.user,
        )
        return Response({"status": "submission_marked", "color": "orange"})

    @action(detail=True, methods=["post"], url_path="collection")
    def mark_collection(self, request, pk=None):
        schedule = self.get_object()
        try:
            schedule.mark_collection()
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        LaundryEvent.objects.create(
            student=schedule.student,
            schedule=schedule,
            event_type=LaundryEvent.EventType.COLLECTION,
            scanned_by=request.user,
        )
        return Response({"status": "collection_marked", "color": "green"})


class LaundryEventViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = LaundryEvent.objects.select_related("student", "schedule", "scanned_by").all()
    serializer_class = LaundryEventSerializer
    permission_classes = [IsAdmin]
