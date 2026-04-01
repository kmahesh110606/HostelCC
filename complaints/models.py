from django.conf import settings
from django.db import models
from django.db.models import Count, Q

from students.models import Student


class Complaint(models.Model):
    class Category(models.TextChoices):
        CARPENTRY = "CARPENTRY", "Carpentry"
        PLUMBING = "PLUMBING", "Plumbing"
        AC = "AC", "AC"
        DRINKING_WATER = "DRINKING_WATER", "Drinking Water"
        UTILITY_WATER = "UTILITY_WATER", "Utility Water"
        DISCIPLINE = "DISCIPLINE", "Discipline"
        CIVIL_INFRA = "CIVIL_INFRA", "Civil/Infra"
        ELECTRICAL = "ELECTRICAL", "Electrical"
        GYM = "GYM", "Gym"
        CLEANING = "CLEANING", "Cleaning"
        SECURITY = "SECURITY", "Security"
        LAUNDRY = "LAUNDRY", "Laundry"
        MESS_ISSUES = "MESS_ISSUES", "Mess Issues"

    class MediaType(models.TextChoices):
        TEXT = "TEXT", "Text"
        IMAGE = "IMAGE", "Image"
        VIDEO = "VIDEO", "Video"

    class Status(models.TextChoices):
        OPEN = "OPEN", "Open"
        IN_PROGRESS = "IN_PROGRESS", "In Progress"
        CLOSED = "CLOSED", "Closed"

    student = models.ForeignKey(Student, on_delete=models.SET_NULL, null=True, blank=True, related_name="complaints")
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="community_posts",
    )
    category = models.CharField(max_length=30, choices=Category.choices)
    text = models.TextField()
    media = models.FileField(upload_to="complaints/media/", null=True, blank=True)
    media_type = models.CharField(max_length=10, choices=MediaType.choices, default=MediaType.TEXT)
    warden_tag = models.CharField(max_length=120, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.OPEN)
    upvotes = models.PositiveIntegerField(default=0)
    downvotes = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status"]),
            models.Index(fields=["category"]),
            models.Index(fields=["status", "created_at"]),
        ]

    @property
    def can_show_hostel_meta(self) -> bool:
        return bool(self.student)

    def refresh_vote_counts(self) -> None:
        counts = self.votes.aggregate(
            up=Count("id", filter=Q(value=ComplaintVote.Value.UPVOTE)),
            down=Count("id", filter=Q(value=ComplaintVote.Value.DOWNVOTE)),
        )
        self.upvotes = counts.get("up", 0) or 0
        self.downvotes = counts.get("down", 0) or 0
        self.save(update_fields=["upvotes", "downvotes"])

    @property
    def status_display_label(self) -> str:
        if self.status == Complaint.Status.OPEN:
            return "Active"
        if self.status == Complaint.Status.IN_PROGRESS:
            return "In Progress"
        return "Closed"


class ComplaintReply(models.Model):
    complaint = models.ForeignKey(Complaint, on_delete=models.CASCADE, related_name="replies")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    text = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]


class ComplaintVote(models.Model):
    class Value(models.IntegerChoices):
        DOWNVOTE = -1, "Downvote"
        UPVOTE = 1, "Upvote"

    complaint = models.ForeignKey(Complaint, on_delete=models.CASCADE, related_name="votes")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="complaint_votes")
    value = models.SmallIntegerField(choices=Value.choices)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("complaint", "user")
