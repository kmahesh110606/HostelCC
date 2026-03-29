from django.core.cache import cache
from django.db.models import Avg, Count, Q
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied
from rest_framework.exceptions import ValidationError
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from users.permissions import IsMessManager
from students.models import Student
from mess.options import canonical_mess_type

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu
from .serializers import (
    CatererSerializer,
    FeedbackSerializer,
    MenuPollOptionSerializer,
    MenuPollVoteSerializer,
    MessChangeRequestSerializer,
    MessMenuSerializer,
)


def _parse_feedback_menu_item(menu_item: str):
    parts = [part.strip() for part in (menu_item or "").split(">") if part.strip()]
    day_code = parts[0] if len(parts) >= 1 else ""
    meal_code = parts[1] if len(parts) >= 2 else ""
    item_name = parts[2] if len(parts) >= 3 else (parts[-1] if parts else "")
    return day_code, meal_code, item_name


class MessMenuViewSet(viewsets.ModelViewSet):
    queryset = MessMenu.objects.all().order_by("mess_type", "week_day")
    serializer_class = MessMenuSerializer

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
            requested_mess_type = student.mess_allotment if student else ""

        cache_key = f"mess_menu_{requested_mess_type or 'all'}_{request.user.role}"
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)

        queryset = self.filter_queryset(self.get_queryset())
        if requested_mess_type:
            queryset = queryset.filter(mess_type=requested_mess_type)
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
            student = Student.objects.select_related("block").filter(user=self.request.user).first()
            if student:
                queryset = queryset.filter(block=student.block, meal_types=student.mess_allotment)
                return queryset

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
            return queryset.filter(student=student)

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
        serializer.save(student=student, month=timezone.now().strftime("%Y-%m"))

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
            serializer = MenuPollVoteSerializer(existing_vote)
            return Response(serializer.data, status=status.HTTP_200_OK)

        serializer = MenuPollVoteSerializer(data={"student": student.id, "option": option_id})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class MessChangeRequestViewSet(viewsets.ModelViewSet):
    queryset = MessChangeRequest.objects.select_related("student").all().order_by("-created_at")
    serializer_class = MessChangeRequestSerializer

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
