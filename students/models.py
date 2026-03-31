from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from hostels.models import HostelBlock, Room
from mess.options import DEFAULT_MESS_TYPE, MESS_TYPE_CHOICES, canonical_mess_type


class Student(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    name = models.CharField(max_length=150)
    roll_no = models.CharField(max_length=30, unique=True, db_index=True)
    block = models.ForeignKey(HostelBlock, on_delete=models.PROTECT, related_name="students")
    room = models.ForeignKey(Room, on_delete=models.SET_NULL, null=True, blank=True, related_name="occupants")
    room_no = models.CharField(max_length=10)
    mess_caterer = models.ForeignKey(
        "mess.Caterer",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="students",
    )
    mess_allotment = models.CharField(max_length=20, choices=MESS_TYPE_CHOICES, default=DEFAULT_MESS_TYPE, db_index=True)
    mess_change_unlocked = models.BooleanField(default=False)

    class Meta:
        ordering = ["roll_no"]

    def __str__(self) -> str:
        return f"{self.roll_no} - {self.name}"

    def _get_default_caterer(self):
        if not self.block_id:
            return None

        from mess.models import Caterer

        normalized_mess_type = canonical_mess_type(self.mess_allotment) or DEFAULT_MESS_TYPE
        caterer = (
            Caterer.objects.filter(block_id=self.block_id, meal_types=normalized_mess_type)
            .order_by("name", "id")
            .first()
        )

        if caterer:
            return caterer

        return Caterer.objects.filter(block_id=self.block_id).order_by("name", "id").first()

    def clean(self):
        super().clean()
        normalized_mess_type = canonical_mess_type(self.mess_allotment) or DEFAULT_MESS_TYPE
        self.mess_allotment = normalized_mess_type

        if self.mess_caterer_id and self.block_id:
            if self.mess_caterer.block_id != self.block_id:
                raise ValidationError({"mess_caterer": "Selected caterer must belong to the student's block."})

    def save(self, *args, **kwargs):
        self.mess_allotment = canonical_mess_type(self.mess_allotment) or DEFAULT_MESS_TYPE

        if self.mess_caterer_id:
            if self.block_id and self.mess_caterer.block_id != self.block_id:
                raise ValidationError({"mess_caterer": "Selected caterer must belong to the student's block."})
            self.mess_allotment = self.mess_caterer.meal_types
        else:
            self.mess_caterer = self._get_default_caterer()
            if self.mess_caterer:
                self.mess_allotment = self.mess_caterer.meal_types

        super().save(*args, **kwargs)
