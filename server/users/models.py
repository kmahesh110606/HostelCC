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

    role = models.CharField(max_length=20, choices=Role.choices, default=Role.STUDENT)
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
