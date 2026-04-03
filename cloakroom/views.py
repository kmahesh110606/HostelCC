import json

from django.db.models import Max
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from students.models import Student
from students.utils import resolve_student_for_user

from .models import CloakroomEntry
from .serializers import CloakroomEntrySerializer


def _can_manage_cloakroom(user) -> bool:
    role = getattr(user, "role", "")
    return role in {"ADMIN", "SUPERVISOR", "WARDEN", "DIRECTOR", "LAUNDRY_PERSON"}


def _parse_student_qr(qr_text: str) -> dict[str, str] | None:
    text = (qr_text or "").strip()
    if not text:
        return None

    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = None

    if isinstance(payload, dict):
        parsed = {}
        for key in ("student_id", "roll_no", "email", "room_no", "block_name"):
            value = payload.get(key)
            if value is not None and str(value).strip():
                parsed[key] = str(value).strip()
        return parsed or None

    parts = [part.strip() for part in text.split("|")]
    if parts and parts[0]:
        return {
            "roll_no": parts[0],
            "email": parts[1] if len(parts) > 1 else "",
            "room_no": parts[2] if len(parts) > 2 else "",
            "block_name": parts[3] if len(parts) > 3 else "",
        }
    return None


def _resolve_student_from_payload(payload: dict[str, str]):
    student_id = (payload.get("student_id") or "").strip()
    if student_id.isdigit():
        student = Student.objects.select_related("block", "user").filter(id=int(student_id)).first()
        if student:
            return student

    roll_no = (payload.get("roll_no") or "").strip()
    if roll_no:
        student = Student.objects.select_related("block", "user").filter(roll_no__iexact=roll_no).first()
        if student:
            return student

    email = (payload.get("email") or "").strip().lower()
    if email:
        return Student.objects.select_related("block", "user").filter(user__email__iexact=email).first()

    return None


def _next_token_no() -> int:
    current = CloakroomEntry.objects.aggregate(max_token=Max("token_no")).get("max_token") or 1000
    return current + 1


class CloakroomEntryViewSet(viewsets.GenericViewSet):
    serializer_class = CloakroomEntrySerializer
    permission_classes = [IsAuthenticated]
    queryset = CloakroomEntry.objects.select_related("student", "student__block", "submitted_by", "returned_by").all()

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user

        if user.role == "STUDENT":
            student = resolve_student_for_user(user)
            if not student:
                return queryset.none()
            queryset = queryset.filter(student=student)
        elif _can_manage_cloakroom(user):
            queryset = queryset
        else:
            return queryset.none()

        status_filter = (self.request.query_params.get("status") or "").strip().upper()
        if status_filter in {CloakroomEntry.Status.SUBMITTED, CloakroomEntry.Status.RETURNED}:
            queryset = queryset.filter(status=status_filter)
        return queryset

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()[:120]
        return Response(self.get_serializer(queryset, many=True).data)

    @action(detail=False, methods=["post"], url_path="submit")
    def submit(self, request):
        if not _can_manage_cloakroom(request.user):
            raise PermissionDenied("Only hostel staff can submit cloakroom entries.")

        qr_text = (request.data.get("qr_text") or "").strip()
        item_name = (request.data.get("item_name") or "").strip()
        storage_room_no = (request.data.get("storage_room_no") or "").strip().upper()
        notes = (request.data.get("notes") or "").strip()

        if not qr_text:
            raise ValidationError({"qr_text": "QR text is required."})
        if not item_name:
            raise ValidationError({"item_name": "Item name is required."})
        if not storage_room_no:
            raise ValidationError({"storage_room_no": "Storage room number is required."})

        parsed = _parse_student_qr(qr_text)
        if not parsed:
            raise ValidationError({"qr_text": "Invalid student QR format."})

        student = _resolve_student_from_payload(parsed)
        if not student:
            raise ValidationError({"qr_text": "Student could not be resolved from this QR."})
        if not student.cloakroom_unlocked:
            raise ValidationError({"detail": "Cloak room service is locked for this student."})

        entry = CloakroomEntry.objects.create(
            student=student,
            token_no=_next_token_no(),
            item_name=item_name,
            storage_room_no=storage_room_no,
            notes=notes,
            status=CloakroomEntry.Status.SUBMITTED,
            submitted_by=request.user,
        )
        payload = self.get_serializer(entry).data
        payload["message"] = "Cloak room item submitted successfully."
        return Response(payload, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=["post"], url_path="return")
    def return_item(self, request):
        if not _can_manage_cloakroom(request.user):
            raise PermissionDenied("Only hostel staff can mark cloakroom return.")

        raw_token = (request.data.get("token_no") or "").strip()
        notes = (request.data.get("notes") or "").strip()

        try:
            token_no = int(raw_token)
        except (TypeError, ValueError):
            raise ValidationError({"token_no": "Token number must be a valid integer."})

        entry = CloakroomEntry.objects.select_related("student", "student__block", "submitted_by", "returned_by").filter(
            token_no=token_no
        ).first()
        if not entry:
            raise ValidationError({"token_no": "Token not found."})

        if entry.status == CloakroomEntry.Status.RETURNED:
            payload = self.get_serializer(entry).data
            payload["message"] = "Token already marked as returned."
            return Response(payload)

        entry.status = CloakroomEntry.Status.RETURNED
        entry.returned_at = timezone.now()
        entry.returned_by = request.user
        if notes:
            entry.notes = f"{entry.notes}\nReturn note: {notes}".strip()
        entry.save(update_fields=["status", "returned_at", "returned_by", "notes"])

        payload = self.get_serializer(entry).data
        payload["message"] = "Cloak room item marked as returned."
        return Response(payload)
