import random
from datetime import timedelta

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class User(AbstractUser):
    class Role(models.TextChoices):
        ADMIN = "ADMIN", "Admin"
        STUDENT = "STUDENT", "Student"
        WARDEN = "WARDEN", "Warden"
        MESS_MANAGER = "MESS_MANAGER", "Mess Manager"
        LAUNDRY_PERSON = "LAUNDRY_PERSON", "Laundry Person"
        SUPERVISOR = "SUPERVISOR", "Supervisor"
        DIRECTOR = "DIRECTOR", "Director"

    class Department(models.TextChoices):
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
        MESS_MANAGEMENT = "MESS_MANAGEMENT", "Mess Management"
        HOSTEL_ADMIN = "HOSTEL_ADMIN", "Hostel Administration"

    role = models.CharField(max_length=20, choices=Role.choices, default=Role.STUDENT)
    phone_country_code = models.CharField(max_length=6, default="+91")
    phone_number = models.CharField(max_length=20, blank=True)
    job_title = models.CharField(max_length=120, blank=True)
    department = models.CharField(max_length=30, choices=Department.choices, blank=True)
    assigned_mess_name = models.CharField(max_length=120, blank=True)
    must_change_password = models.BooleanField(default=True)
    is_email_verified = models.BooleanField(default=False)

    def __str__(self) -> str:
        return f"{self.username} ({self.role})"


class OTPChallenge(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="otp_challenges")
    otp_code = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    consumed = models.BooleanField(default=False)

    class Meta:
        indexes = [models.Index(fields=["user", "expires_at"])]
        ordering = ["-created_at"]

    @classmethod
    def create_for_user(cls, user: User, code: str | None = None) -> "OTPChallenge":
        otp_code = code or f"{random.randint(100000, 999999)}"
        return cls.objects.create(
            user=user,
            otp_code=otp_code,
            expires_at=timezone.now() + timedelta(minutes=10),
        )

    def is_valid_code(self, code: str) -> bool:
        return (not self.consumed) and timezone.now() <= self.expires_at and self.otp_code == code


class AppNotification(models.Model):
    class Audience(models.TextChoices):
        ALL = "ALL", "All"
        STUDENT = "STUDENT", "Student"
        WARDEN = "WARDEN", "Warden"
        MESS_MANAGER = "MESS_MANAGER", "Mess Manager"
        LAUNDRY_PERSON = "LAUNDRY_PERSON", "Laundry Manager"
        ADMIN = "ADMIN", "Admin"

    class Level(models.TextChoices):
        INFO = "INFO", "Info"
        WARNING = "WARNING", "Warning"
        URGENT = "URGENT", "Urgent"

    title = models.CharField(max_length=140)
    message = models.TextField()
    poster = models.FileField(upload_to="notification_posters/", blank=True)
    level = models.CharField(max_length=10, choices=Level.choices, default=Level.INFO)
    audience = models.CharField(max_length=20, choices=Audience.choices, default=Audience.ALL)
    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_notifications",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["is_active", "audience", "-created_at"], name="notif_active_aud_ct_idx"),
            models.Index(fields=["audience", "-created_at"], name="notif_aud_ct_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.title} ({self.audience})"
