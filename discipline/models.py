from django.conf import settings
from django.db import models
from django.utils import timezone

from students.models import Student

from .policies import VIOLATION_CHOICES


class DisciplineCase(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="discipline_cases")
    violation_code = models.CharField(max_length=80, choices=VIOLATION_CHOICES)
    occurrence_number = models.PositiveIntegerField(default=1)
    action_taken = models.CharField(max_length=255, blank=True)
    notes = models.TextField(blank=True)

    id_card_confiscated = models.BooleanField(default=True)
    id_card_confiscated_at = models.DateTimeField(default=timezone.now)
    id_card_returned_at = models.DateTimeField(null=True, blank=True)
    return_notes = models.TextField(blank=True)

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="discipline_cases_created",
    )
    returned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="discipline_cases_returned",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["student", "violation_code"], name="disc_student_violation_idx"),
            models.Index(fields=["student", "id_card_returned_at"], name="disc_student_return_idx"),
            models.Index(fields=["-created_at"], name="disc_created_desc_idx"),
        ]

    @property
    def is_id_card_active_confiscation(self) -> bool:
        return self.id_card_confiscated and self.id_card_returned_at is None

    def __str__(self) -> str:
        return f"{self.student.roll_no} - {self.violation_code} (#{self.occurrence_number})"
