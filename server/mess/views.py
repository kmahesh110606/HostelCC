from django.core.cache import cache
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from users.permissions import IsAdmin, IsMessManager

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu
from .serializers import (
    CatererSerializer,
    FeedbackSerializer,
    MenuPollOptionSerializer,
    MenuPollVoteSerializer,
    MessChangeRequestSerializer,
    MessMenuSerializer,
)


class MessMenuViewSet(viewsets.ModelViewSet):
    queryset = MessMenu.objects.all().order_by("week_day")
    serializer_class = MessMenuSerializer

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    def list(self, request, *args, **kwargs):
        cache_key = "mess_menu_all"
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)

        response = super().list(request, *args, **kwargs)
        cache.set(cache_key, response.data, timeout=300)
        return response


class CatererViewSet(viewsets.ModelViewSet):
    queryset = Caterer.objects.select_related("block").all()
    serializer_class = CatererSerializer

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]


class FeedbackViewSet(viewsets.ModelViewSet):
    queryset = Feedback.objects.select_related("student").all()
    serializer_class = FeedbackSerializer
    throttle_scope = "feedback"
    throttle_classes = [ScopedRateThrottle]

    def get_permissions(self):
        if self.action in ["reply"]:
            permission_classes = [IsMessManager]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    @action(detail=True, methods=["post"])
    def reply(self, request, pk=None):
        feedback = self.get_object()
        feedback.manager_reply = request.data.get("manager_reply", "")
        feedback.save(update_fields=["manager_reply"])
        return Response(FeedbackSerializer(feedback).data)


class PollViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    queryset = MenuPollOption.objects.all().order_by("month", "item_name")
    serializer_class = MenuPollOptionSerializer
    permission_classes = [IsAuthenticated]

    @action(detail=False, methods=["post"], url_path="vote")
    def vote(self, request):
        serializer = MenuPollVoteSerializer(data=request.data)
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
