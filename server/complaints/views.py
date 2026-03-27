from django.db.models import Count
from django.http import HttpResponse
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from users.permissions import IsWarden
from students.models import Student

from .models import Complaint, ComplaintReply, ComplaintVote
from .serializers import ComplaintReplySerializer, ComplaintSerializer


class ComplaintViewSet(viewsets.ModelViewSet):
    queryset = Complaint.objects.select_related("student", "student__block", "author").prefetch_related("replies").all()
    serializer_class = ComplaintSerializer
    permission_classes = [IsAuthenticated]
    throttle_scope = "complaints"
    throttle_classes = [ScopedRateThrottle]
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        queryset = self.queryset

        q = self.request.query_params.get("q", "").strip()
        category = self.request.query_params.get("category", "").strip()
        media_type = self.request.query_params.get("media_type", "").strip()

        if q:
            queryset = queryset.filter(text__icontains=q)
        if category:
            queryset = queryset.filter(category=category)
        if media_type:
            queryset = queryset.filter(media_type=media_type)

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
        complaint.status = Complaint.Status.CLOSED
        complaint.save(update_fields=["status"])
        return Response(ComplaintSerializer(complaint).data)

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
