from django.conf import settings
from django.db import models


class CloakroomEntry(models.Model):
    class Status(models.TextChoices):
        SUBMITTED = "SUBMITTED", "Submitted"
        RETURNED = "RETURNED", "Returned"

    student = models.ForeignKey("students.Student", on_delete=models.CASCADE, related_name="cloakroom_entries")
    token_no = models.PositiveIntegerField(unique=True, db_index=True)
    item_name = models.CharField(max_length=180)
    storage_room_no = models.CharField(max_length=20)
    notes = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.SUBMITTED, db_index=True)
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="cloakroom_submissions",
    )
    returned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="cloakroom_returns",
    )
    submitted_at = models.DateTimeField(auto_now_add=True)
    returned_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-submitted_at", "-id"]

    def __str__(self) -> str:
        return f"Token {self.token_no} - {self.student.roll_no}"
