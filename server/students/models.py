from django.conf import settings
from django.db import models

from hostels.models import HostelBlock, Room


class Student(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    name = models.CharField(max_length=150)
    roll_no = models.CharField(max_length=30, unique=True, db_index=True)
    block = models.ForeignKey(HostelBlock, on_delete=models.PROTECT, related_name="students")
    room = models.ForeignKey(Room, on_delete=models.SET_NULL, null=True, blank=True, related_name="occupants")
    room_no = models.CharField(max_length=10)
    points_balance = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    mess_allotment = models.CharField(max_length=100)

    class Meta:
        ordering = ["roll_no"]

    def __str__(self) -> str:
        return f"{self.roll_no} - {self.name}"
