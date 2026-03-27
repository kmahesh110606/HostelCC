import uuid
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from students.models import Student


class LaundrySchedule(models.Model):
    class DayChoices(models.TextChoices):
        MON = "MON", "Monday"
        TUE = "TUE", "Tuesday"
        WED = "WED", "Wednesday"
        THU = "THU", "Thursday"
        FRI = "FRI", "Friday"
        SAT = "SAT", "Saturday"
        SUN = "SUN", "Sunday"

    student = models.OneToOneField(Student, on_delete=models.CASCADE, related_name="laundry_schedule")
    day_of_week = models.CharField(max_length=3, choices=DayChoices.choices)
    holidays = models.JSONField(default=list, blank=True)
    qr_token = models.CharField(max_length=100, default=uuid.uuid4, editable=False)
    submission_status = models.BooleanField(default=False)
    collection_status = models.BooleanField(default=False)
    last_submission_at = models.DateTimeField(null=True, blank=True)
    due_collection_by = models.DateTimeField(null=True, blank=True)

    def mark_submission(self):
        now = timezone.now()
        if self.last_submission_at and self.last_submission_at.date() == now.date():
            raise ValueError("Student already submitted laundry today.")
        self.submission_status = True
        self.collection_status = False
        self.last_submission_at = now
        self.due_collection_by = now + timedelta(days=7)
        self.save(update_fields=["submission_status", "collection_status", "last_submission_at", "due_collection_by"])

    def mark_collection(self):
        now = timezone.now()
        if not self.submission_status:
            raise ValueError("No submission record found.")
        if self.due_collection_by and now > self.due_collection_by:
            raise ValueError("Collection window exceeded 1 week.")
        self.collection_status = True
        self.submission_status = False
        self.save(update_fields=["collection_status", "submission_status"])


class LaundryEvent(models.Model):
    class EventType(models.TextChoices):
        SUBMISSION = "SUBMISSION", "Submission"
        COLLECTION = "COLLECTION", "Collection"

    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="laundry_events")
    schedule = models.ForeignKey(LaundrySchedule, on_delete=models.CASCADE, related_name="events")
    event_type = models.CharField(max_length=12, choices=EventType.choices)
    scanned_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
