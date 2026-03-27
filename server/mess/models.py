from django.db import models

from hostels.models import HostelBlock
from students.models import Student


class MessMenu(models.Model):
    class WeekDay(models.TextChoices):
        MON = "MON", "Monday"
        TUE = "TUE", "Tuesday"
        WED = "WED", "Wednesday"
        THU = "THU", "Thursday"
        FRI = "FRI", "Friday"

    week_day = models.CharField(max_length=3, choices=WeekDay.choices, unique=True, db_index=True)
    breakfast_items = models.TextField()
    lunch_items = models.TextField()
    snacks_items = models.TextField()
    dinner_items = models.TextField()

    def __str__(self):
        return self.get_week_day_display()


class Caterer(models.Model):
    name = models.CharField(max_length=120)
    meal_types = models.CharField(max_length=120, help_text="Comma separated values: veg, nonveg, special, foodpark")
    block = models.ForeignKey(HostelBlock, on_delete=models.CASCADE, related_name="caterers")

    class Meta:
        unique_together = ("name", "block")
        ordering = ["block__block_name", "name"]

    def __str__(self) -> str:
        return f"{self.name} ({self.block.block_name})"


class Feedback(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="mess_feedback")
    menu_item = models.CharField(max_length=120)
    rating = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True)
    month = models.CharField(max_length=7)
    manager_reply = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class MenuPollOption(models.Model):
    month = models.CharField(max_length=7)
    item_name = models.CharField(max_length=120)

    class Meta:
        unique_together = ("month", "item_name")


class MenuPollVote(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE)
    option = models.ForeignKey(MenuPollOption, on_delete=models.CASCADE, related_name="votes")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("student", "option")


class MessChangeRequest(models.Model):
    class Status(models.TextChoices):
        PENDING = "PENDING", "Pending"
        APPROVED = "APPROVED", "Approved"
        REJECTED = "REJECTED", "Rejected"

    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="mess_change_requests")
    requested_mess = models.CharField(max_length=120)
    month = models.CharField(max_length=7)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING)
    created_at = models.DateTimeField(auto_now_add=True)
