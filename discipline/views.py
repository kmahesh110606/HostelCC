from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from students.models import Student

from .models import DisciplineCase
from .serializers import (
    DisciplineCaseCreateSerializer,
    DisciplineCaseSerializer,
    DisciplineReturnSerializer,
    build_policy_payload,
)


DISCIPLINE_ALLOWED_ROLES = {"WARDEN", "SUPERVISOR", "ADMIN", "DIRECTOR"}


def _is_discipline_staff(user) -> bool:
    return bool(user and user.is_authenticated and user.role in DISCIPLINE_ALLOWED_ROLES)


class DisciplineCaseViewSet(viewsets.ModelViewSet):
    serializer_class = DisciplineCaseSerializer
    permission_classes = [IsAuthenticated]
    queryset = DisciplineCase.objects.select_related(
        "student",
        "student__block",
        "created_by",
        "returned_by",
    ).all()

    def get_queryset(self):
        queryset = self.queryset

        user = self.request.user
        if _is_discipline_staff(user):
            reg_no = (self.request.query_params.get("reg_no") or "").strip().upper()
            if reg_no:
                queryset = queryset.filter(student__roll_no__iexact=reg_no)
            return queryset

        student = Student.objects.filter(user=user).first()
        if not student:
            return queryset.none()

        return queryset.filter(student=student)

    def list(self, request, *args, **kwargs):
        if not _is_discipline_staff(request.user):
            return super().list(request, *args, **kwargs)

        reg_no = (request.query_params.get("reg_no") or "").strip().upper()
        if not reg_no:
            return Response({"detail": "reg_no query param is required for staff search."}, status=400)

        student = Student.objects.select_related("block", "room", "user").filter(roll_no__iexact=reg_no).first()
        if not student:
            return Response(
                {
                    "student": None,
                    "history": [],
                    "active_confiscation": None,
                }
            )

        history_qs = self.queryset.filter(student=student)
        history = DisciplineCaseSerializer(history_qs, many=True).data

        active = history_qs.filter(id_card_confiscated=True, id_card_returned_at__isnull=True).order_by("-created_at").first()
        active_payload = DisciplineCaseSerializer(active).data if active else None

        return Response(
            {
                "student": {
                    "id": student.id,
                    "name": student.name,
                    "roll_no": student.roll_no,
                    "block_name": student.block.block_name if student.block else "",
                    "room_no": student.room_no,
                },
                "history": history,
                "active_confiscation": active_payload,
            }
        )

    def create(self, request, *args, **kwargs):
        if not _is_discipline_staff(request.user):
            return Response({"detail": "Only wardens/supervisors/admin/directors can create discipline records."}, status=403)

        validator = DisciplineCaseCreateSerializer(data=request.data)
        validator.is_valid(raise_exception=True)
        data = validator.validated_data

        case = DisciplineCase.objects.create(
            student=data["student"],
            violation_code=data["violation_code"],
            occurrence_number=data["occurrence_number"],
            action_taken=data["action_taken"],
            notes=data["notes"],
            created_by=request.user,
            id_card_confiscated=True,
        )

        payload = DisciplineCaseSerializer(case).data
        return Response(payload, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="return-id")
    def return_id(self, request, pk=None):
        if not _is_discipline_staff(request.user):
            return Response({"detail": "Only wardens/supervisors/admin/directors can return ID cards."}, status=403)

        case = self.get_object()
        if case.id_card_returned_at is not None:
            return Response({"detail": "ID card is already marked as returned."}, status=400)

        serializer = DisciplineReturnSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        case.id_card_returned_at = timezone.now()
        case.returned_by = request.user
        case.return_notes = serializer.validated_data.get("return_notes", "").strip()
        case.save(update_fields=["id_card_returned_at", "returned_by", "return_notes", "updated_at"])

        return Response(DisciplineCaseSerializer(case).data)

    @action(detail=False, methods=["get"], url_path="policies")
    def policies(self, request):
        if not _is_discipline_staff(request.user):
            return Response({"detail": "Only wardens/supervisors/admin/directors can view discipline policies."}, status=403)
        return Response(build_policy_payload())
