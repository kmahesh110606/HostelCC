from django.core.cache import cache
from django.db.models import Avg, Count, Q
from django.db import IntegrityError
import logging
from django.utils import timezone
import json
from rest_framework.exceptions import PermissionDenied
from rest_framework.exceptions import ValidationError
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from users.permissions import IsMessManager
from students.models import Student
from students.utils import resolve_student_for_user
from mess.options import canonical_mess_type

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu, NightMessLog
from .serializers import (
    CatererSerializer,
    FeedbackSerializer,
    MenuPollOptionSerializer,
    MenuPollVoteSerializer,
    MessChangeRequestSerializer,
    MessMenuSerializer,
    NightMessLogSerializer,
)


logger = logging.getLogger(__name__)


def _parse_feedback_menu_item(menu_item: str):
    parts = [part.strip() for part in (menu_item or "").split(">") if part.strip()]
    day_code = parts[0] if len(parts) >= 1 else ""
    meal_code = parts[1] if len(parts) >= 2 else ""
    item_name = parts[2] if len(parts) >= 3 else (parts[-1] if parts else "")
    return day_code, meal_code, item_name


def _is_night_mess_staff(user) -> bool:
    role = getattr(user, "role", "")
    if role in {"WARDEN", "SUPERVISOR", "ADMIN"}:
        return True
    return getattr(user, "department", "") == "SECURITY"


def _parse_night_mess_qr(qr_text: str) -> dict[str, str] | None:
    text = (qr_text or "").strip()
    if not text:
        return None

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = None

    if isinstance(parsed, dict):
        payload: dict[str, str] = {}
        for key in ("roll_no", "email", "room_no", "block_name"):
            value = parsed.get(key)
            if value is not None and str(value).strip():
                payload[key] = str(value).strip()
        return payload or None

    parts = [part.strip() for part in text.split("|")]
    if len(parts) >= 1 and parts[0]:
        return {
            "roll_no": parts[0],
            "email": parts[1] if len(parts) > 1 else "",
            "room_no": parts[2] if len(parts) > 2 else "",
            "block_name": parts[3] if len(parts) > 3 else "",
        }
    return None


class MessMenuViewSet(viewsets.ModelViewSet):
    queryset = MessMenu.objects.all().order_by("mess_type", "week_day")
    serializer_class = MessMenuSerializer
    _veg_fallback_types = {"NON_VEG", "SPECIAL"}

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    def list(self, request, *args, **kwargs):
        requested_mess_type = canonical_mess_type(request.query_params.get("mess_type"))
        if request.user.role == "STUDENT":
            student = Student.objects.select_related("block").filter(user=request.user).first()
            if not student:
                return Response([])
            requested_mess_type = canonical_mess_type(student.mess_allotment)
            if not requested_mess_type:
                return Response([])

        if requested_mess_type == "FOODPARK":
            return Response([])

        cache_key = f"mess_menu_{requested_mess_type or 'all'}_{request.user.role}"
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)

        base_queryset = self.filter_queryset(self.get_queryset())
        queryset = base_queryset
        if requested_mess_type:
            queryset = queryset.filter(mess_type=requested_mess_type)
            if requested_mess_type in self._veg_fallback_types and not queryset.exists():
                queryset = base_queryset.filter(mess_type="VEG")
        elif request.user.role != "STUDENT":
            queryset = queryset.filter(mess_type="VEG")

        serializer = self.get_serializer(queryset, many=True)
        response = Response(serializer.data)
        cache.set(cache_key, response.data, timeout=300)
        return response


class CatererViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Caterer.objects.select_related("block").all()
    serializer_class = CatererSerializer

    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = super().get_queryset()

        block_name = (self.request.query_params.get("block") or "").strip().upper()
        mess_type = canonical_mess_type(self.request.query_params.get("mess_type"))

        if self.request.user.role == "STUDENT":
            student = resolve_student_for_user(self.request.user)
            if student:
                student_mess_type = canonical_mess_type(student.mess_allotment)
                if not student_mess_type:
                    return queryset.none()
                queryset = queryset.filter(block=student.block, meal_types=student_mess_type)
                return queryset
            return queryset.none()

        if block_name:
            queryset = queryset.filter(block__block_name=block_name)
        if mess_type:
            queryset = queryset.filter(meal_types=mess_type)

        return queryset


class FeedbackViewSet(viewsets.ModelViewSet):
    queryset = Feedback.objects.select_related("student", "student__block").all()
    serializer_class = FeedbackSerializer
    throttle_scope = "feedback"
    throttle_classes = [ScopedRateThrottle]

    def _scoped_feedback_queryset(self):
        queryset = Feedback.objects.select_related("student", "student__block").all()
        role = getattr(self.request.user, "role", "")

        if role == "STUDENT":
            student = Student.objects.filter(user=self.request.user).first()
            if not student:
                return queryset.none()
            mess_type = canonical_mess_type(student.mess_allotment)
            if not mess_type:
                return queryset.none()
            return queryset.filter(student__mess_allotment=mess_type)

        if role in {"MESS_MANAGER", "WARDEN"}:
            assigned_mess_name = (getattr(self.request.user, "assigned_mess_name", "") or "").strip()
            if not assigned_mess_name:
                return queryset.none()

            scope_pairs = list(
                Caterer.objects.filter(name__iexact=assigned_mess_name)
                .values_list("block_id", "meal_types")
                .distinct()
            )
            if not scope_pairs:
                return queryset.none()

            scope_filter = Q()
            for block_id, meal_type in scope_pairs:
                scope_filter |= Q(student__block_id=block_id, student__mess_allotment=meal_type)
            return queryset.filter(scope_filter)

        return queryset

    def get_queryset(self):
        return self._scoped_feedback_queryset()

    def get_permissions(self):
        if self.action in ["reply"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    def perform_create(self, serializer):
        student = Student.objects.filter(user=self.request.user).first()
        if not student:
            raise PermissionDenied("Only mapped students can submit mess feedback.")
        
        month = timezone.now().strftime("%Y-%m")
        menu_item = serializer.validated_data.get("menu_item", "")
        
        # Check if student already rated this menu item this month
        if Feedback.objects.filter(student=student, menu_item=menu_item, month=month).exists():
            raise ValidationError(
                "You have already rated this menu item this month. "
                "You can only rate each menu item once per month."
            )
        
        try:
            serializer.save(student=student, month=month)
        except IntegrityError:
            raise ValidationError(
                "You have already rated this menu item this month. "
                "You can only rate each menu item once per month."
            )
        except Exception:
            logger.exception(
                "Unexpected error while creating feedback for user_id=%s student_id=%s",
                getattr(self.request.user, "id", None),
                getattr(student, "id", None),
            )
            raise ValidationError(
                "Unable to submit feedback right now. Please verify your input and try again."
            )

    @action(detail=True, methods=["post"])
    def reply(self, request, pk=None):
        feedback = self.get_object()
        feedback.manager_reply = request.data.get("manager_reply", "")
        feedback.save(update_fields=["manager_reply"])
        return Response(FeedbackSerializer(feedback).data)

    @action(detail=False, methods=["get"], url_path="least-rated")
    def least_rated(self, request):
        raw_limit = request.query_params.get("limit", "10")
        try:
            limit = int(raw_limit)
        except (TypeError, ValueError):
            raise ValidationError({"limit": "Limit must be an integer."})

        if limit < 1 or limit > 50:
            raise ValidationError({"limit": "Limit must be between 1 and 50."})

        rows = (
            self._scoped_feedback_queryset()
            .values("menu_item")
            .annotate(avg_rating=Avg("rating"), total=Count("id"))
            .order_by("avg_rating", "-total")[:limit]
        )

        payload = []
        for row in rows:
            menu_item = row.get("menu_item", "")
            day_code, meal_code, item_name = _parse_feedback_menu_item(menu_item)
            payload.append(
                {
                    "menu_item": menu_item,
                    "item_name": item_name,
                    "week_day": day_code,
                    "meal_time": meal_code,
                    "avg_rating": float(row.get("avg_rating") or 0),
                    "total": int(row.get("total") or 0),
                }
            )

        return Response(payload)


class PollViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    queryset = MenuPollOption.objects.all().order_by("month", "item_name")
    serializer_class = MenuPollOptionSerializer
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action in ["create"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    def get_queryset(self):
        queryset = super().get_queryset()
        month = (self.request.query_params.get("month") or "").strip()
        if month:
            queryset = queryset.filter(month=month)
        return queryset

    @action(detail=False, methods=["post"], url_path="vote")
    def vote(self, request):
        student = Student.objects.filter(user=request.user).first()
        if not student:
            raise PermissionDenied("Only mapped students can vote in mess polls.")

        option_id = request.data.get("option")
        if not option_id:
            raise ValidationError({"option": "Option is required."})

        existing_vote = MenuPollVote.objects.filter(student=student, option_id=option_id).first()
        if existing_vote:
            return Response(
                {"detail": "You have already voted for this option."},
                status=status.HTTP_200_OK
            )

        try:
            serializer = MenuPollVoteSerializer(data={"student": student.id, "option": option_id})
            serializer.is_valid(raise_exception=True)
            serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        except IntegrityError:
            return Response(
                {"detail": "You have already voted for this option."},
                status=status.HTTP_200_OK
            )


class MessChangeRequestViewSet(viewsets.ModelViewSet):
    queryset = MessChangeRequest.objects.select_related("student").all().order_by("-created_at")
    serializer_class = MessChangeRequestSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.request.user.role == "STUDENT":
            student = resolve_student_for_user(self.request.user)
            if not student:
                return queryset.none()
            return queryset.filter(student=student)
        return queryset

    def perform_create(self, serializer):
        if self.request.user.role != "STUDENT":
            raise PermissionDenied("Only students can request mess change.")

        student = resolve_student_for_user(self.request.user)
        if not student:
            raise PermissionDenied("Only mapped students can request mess change.")
        if not student.mess_change_unlocked:
            raise ValidationError({"detail": "Mess change is currently locked."})

        requested_caterer_id = serializer.validated_data.get("requested_caterer_id")
        selected_caterer = Caterer.objects.filter(
            id=requested_caterer_id,
            block_id=student.block_id,
            meal_types=student.mess_allotment,
        ).first()
        if not selected_caterer:
            raise ValidationError({"detail": "Selected caterer is not available for your block and mess type."})

        student.mess_caterer = selected_caterer
        student.mess_allotment = selected_caterer.meal_types
        student.mess_change_unlocked = False
        student.save(update_fields=["mess_caterer", "mess_allotment", "mess_change_unlocked"])

        serializer.save(
            student=student,
            status=MessChangeRequest.Status.APPROVED,
            requested_mess=selected_caterer.name,
        )

    def get_permissions(self):
        if self.action in ["approve", "reject"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    @action(detail=True, methods=["post"])
    def approve(self, request, pk=None):
        change_request = self.get_object()
        change_request.status = MessChangeRequest.Status.APPROVED
        change_request.save(update_fields=["status"])
        return Response(self.get_serializer(change_request).data)

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        change_request = self.get_object()
        change_request.status = MessChangeRequest.Status.REJECTED
        change_request.save(update_fields=["status"])
        return Response(self.get_serializer(change_request).data)


class NightMessLogViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    queryset = NightMessLog.objects.select_related(
        "student",
        "student__block",
        "student__user",
        "checked_out_by",
        "returned_by",
    ).all()
    serializer_class = NightMessLogSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        if user.role == "STUDENT":
            student = resolve_student_for_user(user)
            if not student:
                return queryset.none()
            return queryset.filter(student=student)

        if _is_night_mess_staff(user):
            return queryset

        return queryset.none()

    @action(detail=False, methods=["get"], url_path="status")
    def status(self, request):
        user = request.user
        if user.role != "STUDENT":
            raise PermissionDenied("Night mess status is only available for student accounts.")

        student = resolve_student_for_user(user)
        if not student:
            return Response({"in_night_mess": False, "message": "Student profile not found."})

        active_log = (
            NightMessLog.objects.filter(student=student, returned_at__isnull=True)
            .order_by("-checked_out_at")
            .first()
        )
        if active_log:
            return Response(
                {
                    "in_night_mess": True,
                    "message": "You are in Night Mess now. Scan again before returning.",
                    "active_log": self.get_serializer(active_log).data,
                }
            )

        return Response(
            {
                "in_night_mess": False,
                "message": "You are not marked in Night Mess.",
                "active_log": None,
            }
        )

    @action(detail=False, methods=["get"], url_path=r"qr/(?P<student_id>[^/.]+)")
    def qr_for_student(self, request, student_id=None):
        student = Student.objects.select_related("block", "user").filter(id=student_id).first()
        if not student:
            return Response({"detail": "Student not found."}, status=status.HTTP_404_NOT_FOUND)

        if request.user.role == "STUDENT":
            own_student = resolve_student_for_user(request.user)
            if not own_student or own_student.id != student.id:
                raise PermissionDenied("You can only access your own Night Mess QR.")
        elif not _is_night_mess_staff(request.user):
            raise PermissionDenied("Not allowed to access Night Mess QR data.")

        student_email = (
            (student.user.email if student.user else "") or (student.user.username if student.user else "") or ""
        )
        payload = {
            "type": "night_mess",
            "roll_no": student.roll_no,
            "email": student_email.strip().lower(),
            "room_no": student.room_no,
            "block_name": student.block.block_name if student.block else "",
        }
        qr_text = json.dumps(payload, separators=(",", ":"))

        return Response(
            {
                "student_id": student.id,
                "roll_no": student.roll_no,
                "room_no": student.room_no,
                "block_name": student.block.block_name if student.block else "",
                "qr_text": qr_text,
            }
        )

    @action(detail=False, methods=["post"], url_path="scan")
    def scan(self, request):
        if not _is_night_mess_staff(request.user):
            raise PermissionDenied("Only wardens, supervisors, admins, and security staff can scan Night Mess QR.")

        parsed = _parse_night_mess_qr((request.data.get("qr_text") or "").strip())
        if not parsed:
            return Response({"detail": "Invalid qr_text payload."}, status=status.HTTP_400_BAD_REQUEST)

        roll_no = (parsed.get("roll_no") or "").strip().upper()
        if not roll_no:
            return Response({"detail": "roll_no is required in QR payload."}, status=status.HTTP_400_BAD_REQUEST)

        student = Student.objects.select_related("block", "user").filter(roll_no=roll_no).first()
        if not student:
            return Response({"detail": f"Student {roll_no} not found."}, status=status.HTTP_404_NOT_FOUND)

        qr_room = (parsed.get("room_no") or "").strip().upper()
        if qr_room and student.room_no.strip().upper() != qr_room:
            return Response({"detail": f"Room mismatch. Expected {student.room_no}, got {qr_room}."}, status=status.HTTP_400_BAD_REQUEST)

        qr_block = (parsed.get("block_name") or "").strip().upper()
        student_block = (student.block.block_name if student.block else "").strip().upper()
        if qr_block and student_block != qr_block:
            return Response({"detail": f"Block mismatch. Expected {student_block}, got {qr_block}."}, status=status.HTTP_400_BAD_REQUEST)

        qr_email = (parsed.get("email") or "").strip().lower()
        student_email = ((student.user.email if student.user else "") or "").strip().lower()
        if qr_email and student_email and qr_email != student_email:
            return Response({"detail": "Email mismatch in QR payload."}, status=status.HTTP_400_BAD_REQUEST)

        active_log = (
            NightMessLog.objects.filter(student=student, returned_at__isnull=True)
            .order_by("-checked_out_at")
            .first()
        )

        if active_log:
            active_log.returned_at = timezone.now()
            active_log.returned_by = request.user
            active_log.save(update_fields=["returned_at", "returned_by"])
            return Response(
                {
                    "status": "returned",
                    "message": "Night Mess return marked successfully.",
                    "in_night_mess": False,
                    "student_name": student.name,
                    "student_roll_no": student.roll_no,
                    "room_no": student.room_no,
                    "block_name": student.block.block_name if student.block else "",
                    "log": self.get_serializer(active_log).data,
                }
            )

        created_log = NightMessLog.objects.create(
            student=student,
            checked_out_by=request.user,
        )
        return Response(
            {
                "status": "checked_out",
                "message": "Night Mess out-time marked successfully.",
                "in_night_mess": True,
                "student_name": student.name,
                "student_roll_no": student.roll_no,
                "room_no": student.room_no,
                "block_name": student.block.block_name if student.block else "",
                "log": self.get_serializer(created_log).data,
            },
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=["get"], url_path="overdue")
    def overdue(self, request):
        if not _is_night_mess_staff(request.user):
            raise PermissionDenied("Only staff can view overdue Night Mess entries.")

        queryset = self.get_queryset().filter(returned_at__isnull=True)
        overdue_logs = [log for log in queryset if log.is_overdue]
        serialized = self.get_serializer(overdue_logs, many=True)
        return Response(serialized.data)
