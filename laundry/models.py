import uuid
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
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
        today = timezone.localdate(now)
        if self.last_submission_at and timezone.localdate(self.last_submission_at) == today:
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
        self.due_collection_by = None
        self.save(update_fields=["collection_status", "submission_status", "due_collection_by"])


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


class LaundryRoomRange(models.Model):
    block_name = models.CharField(max_length=10, db_index=True)
    day_of_week = models.CharField(max_length=3, choices=LaundrySchedule.DayChoices.choices, blank=True, null=True)
    scheduled_date = models.DateField(blank=True, null=True, db_index=True)
    room_from = models.CharField(max_length=10)
    room_to = models.CharField(max_length=10)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["block_name", "scheduled_date", "day_of_week", "room_from"]

    def clean(self):
        super().clean()
        if not self.scheduled_date and not self.day_of_week:
            raise ValidationError("Provide either scheduled_date or day_of_week for a room range.")

    @property
    def schedule_label(self) -> str:
        if self.scheduled_date:
            return self.scheduled_date.isoformat()
        if self.day_of_week:
            return self.get_day_of_week_display()
        return "-"

    def __str__(self):
        slot = self.scheduled_date.isoformat() if self.scheduled_date else self.day_of_week
        return f"{self.block_name} {slot}: {self.room_from}-{self.room_to}"


class LaundryHoliday(models.Model):
    holiday_date = models.DateField(unique=True, db_index=True)
    name = models.CharField(max_length=120, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["holiday_date"]

    def __str__(self):
        label = self.name.strip() if self.name else "Holiday"
        return f"{self.holiday_date.isoformat()} - {label}"
