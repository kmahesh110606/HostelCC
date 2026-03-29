from django.db.models import Count, Q
from django.http import HttpResponse
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from users.permissions import IsWarden
from students.models import Student

from .models import Complaint, ComplaintReply, ComplaintVote
from .serializers import ComplaintReplySerializer, ComplaintSerializer


def can_manage_complaint(user, complaint: Complaint) -> bool:
    if not user.is_authenticated:
        return False
    if user.role in {"ADMIN", "WARDEN"}:
        return True
    return user.role == "SUPERVISOR" and bool(user.department and user.department == complaint.category)


def log_status_activity(complaint: Complaint, actor, new_status: str) -> None:
    status_label = complaint.get_status_display()
    actor_name = actor.get_full_name().strip() or actor.username
    ComplaintReply.objects.create(
        complaint=complaint,
        author=actor,
        text=f"[Status Update] {actor_name} set status to {status_label}.",
    )


class ComplaintViewSet(viewsets.ModelViewSet):
    queryset = (
        Complaint.objects.select_related("student", "student__block", "author")
        .prefetch_related("replies", "votes")
        .all()
    )
    serializer_class = ComplaintSerializer
    permission_classes = [IsAuthenticated]
    throttle_scope = "complaints"
    throttle_classes = [ScopedRateThrottle]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_queryset(self):
        queryset = self.queryset

        q = self.request.query_params.get("q", "").strip()
        category = self.request.query_params.get("category", "").strip()
        media_type = self.request.query_params.get("media_type", "").strip()
        status_filter = self.request.query_params.get("status", "").strip().upper()
        block_filter = self.request.query_params.get("block", "").strip().upper()
        sort_by = self.request.query_params.get("sort", "newest").strip().lower()

        if q:
            queryset = queryset.filter(
                Q(text__icontains=q)
                | Q(author__username__icontains=q)
                | Q(author__first_name__icontains=q)
                | Q(author__last_name__icontains=q)
                | Q(student__name__icontains=q)
            )
        if category:
            queryset = queryset.filter(category=category)
        if media_type:
            queryset = queryset.filter(media_type=media_type)
        if block_filter:
            queryset = queryset.filter(student__block__block_name=block_filter)

        if self.request.user.role == "SUPERVISOR" and self.request.user.department:
            queryset = queryset.filter(category=self.request.user.department)

        if status_filter:
            queryset = queryset.filter(status=status_filter)

        if sort_by == "oldest":
            queryset = queryset.order_by("created_at")
        elif sort_by == "upvotes":
            queryset = queryset.order_by("-upvotes", "-created_at")
        else:
            queryset = queryset.order_by("-created_at")

        return queryset

    def perform_create(self, serializer):
        student = Student.objects.filter(user=self.request.user).first()
        media = self.request.FILES.get("media")
        media_type = Complaint.MediaType.TEXT
        if media:
            lowered = media.name.lower()
            if lowered.endswith((".png", ".jpg", ".jpeg", ".gif", ".webp")):
                media_type = Complaint.MediaType.IMAGE
            elif lowered.endswith((".mp4", ".mov", ".webm", ".mkv")):
                media_type = Complaint.MediaType.VIDEO

        serializer.save(author=self.request.user, student=student, media_type=media_type)

    def destroy(self, request, *args, **kwargs):
        complaint = self.get_object()
        is_owner = complaint.author_id == request.user.id or bool(
            complaint.student and complaint.student.user_id == request.user.id
        )
        if request.user.role != "ADMIN" and not is_owner:
            return Response({"detail": "You do not have permission to delete this post."}, status=403)
        return super().destroy(request, *args, **kwargs)

    @action(detail=True, methods=["post"])
    def reply(self, request, pk=None):
        complaint = self.get_object()
        serializer = ComplaintReplySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(complaint=complaint, author=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def close(self, request, pk=None):
        complaint = self.get_object()
        if not can_manage_complaint(request.user, complaint):
            return Response({"detail": "Only the concerned supervisor, warden, or admin can close this complaint."}, status=403)
        complaint.status = Complaint.Status.CLOSED
        complaint.save(update_fields=["status"])
        log_status_activity(complaint, request.user, Complaint.Status.CLOSED)
        return Response(ComplaintSerializer(complaint, context={"request": request}).data)

    @action(detail=True, methods=["post"], url_path="set-status")
    def set_status(self, request, pk=None):
        complaint = self.get_object()
        if not can_manage_complaint(request.user, complaint):
            return Response(
                {"detail": "Only the concerned supervisor, warden, or admin can change complaint status."},
                status=403,
            )

        requested_status = (request.data.get("status") or "").strip().upper()
        allowed_statuses = {choice[0] for choice in Complaint.Status.choices}
        if requested_status not in allowed_statuses:
            return Response({"detail": "Invalid status value."}, status=400)

        if complaint.status != requested_status:
            complaint.status = requested_status
            complaint.save(update_fields=["status"])
            log_status_activity(complaint, request.user, requested_status)

        return Response(ComplaintSerializer(complaint, context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def vote(self, request, pk=None):
        complaint = self.get_object()
        direction = request.data.get("direction", "").strip().lower()

        if direction not in {"up", "down"}:
            return Response({"detail": "direction must be 'up' or 'down'."}, status=400)

        vote_value = ComplaintVote.Value.UPVOTE if direction == "up" else ComplaintVote.Value.DOWNVOTE

        vote, created = ComplaintVote.objects.get_or_create(
            complaint=complaint,
            user=request.user,
            defaults={"value": vote_value},
        )

        if not created:
            if vote.value == vote_value:
                vote.delete()
            else:
                vote.value = vote_value
                vote.save(update_fields=["value", "updated_at"])

        complaint.refresh_vote_counts()
        return Response(ComplaintSerializer(complaint, context={"request": request}).data)

    @action(detail=False, methods=["get"], permission_classes=[IsWarden], url_path="unresolved-print")
    def unresolved_print(self, request):
        rows = (
            Complaint.objects.filter(status=Complaint.Status.OPEN)
            .values("category")
            .annotate(total=Count("id"))
            .order_by("category")
        )
        lines = ["Unresolved Complaints by Category"]
        lines.extend([f"{row['category']}: {row['total']}" for row in rows])
        content = "\n".join(lines)
        return HttpResponse(content, content_type="text/plain")
