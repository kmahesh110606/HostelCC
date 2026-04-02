from django.db import models

from hostels.models import HostelBlock
from mess.options import DEFAULT_MESS_TYPE, MESS_TYPE_CHOICES
from students.models import Student


class MessMenu(models.Model):
    class WeekDay(models.TextChoices):
        MON = "MON", "Monday"
        TUE = "TUE", "Tuesday"
        WED = "WED", "Wednesday"
        THU = "THU", "Thursday"
        FRI = "FRI", "Friday"
        SAT = "SAT", "Saturday"
        SUN = "SUN", "Sunday"

    mess_type = models.CharField(max_length=20, choices=MESS_TYPE_CHOICES, default=DEFAULT_MESS_TYPE, db_index=True)
    week_day = models.CharField(max_length=3, choices=WeekDay.choices, db_index=True)
    breakfast_items = models.TextField()
    lunch_items = models.TextField()
    snacks_items = models.TextField()
    dinner_items = models.TextField()

    class Meta:
        ordering = ["mess_type", "week_day"]
        unique_together = ("mess_type", "week_day")

    def __str__(self):
        return f"{self.get_mess_type_display()} - {self.get_week_day_display()}"


class Caterer(models.Model):
    name = models.CharField(max_length=120)
    meal_types = models.CharField(max_length=20, choices=MESS_TYPE_CHOICES)
    block = models.ForeignKey(HostelBlock, on_delete=models.CASCADE, related_name="caterers")

    class Meta:
        unique_together = ("name", "block", "meal_types")
        ordering = ["block__block_name", "meal_types", "name"]

    def __str__(self) -> str:
        return f"{self.name} ({self.block.block_name})"


class Feedback(models.Model):
    class MealTime(models.TextChoices):
        BREAKFAST = "BREAKFAST", "Breakfast"
        LUNCH = "LUNCH", "Lunch"
        SNACKS = "SNACKS", "Snacks"
        DINNER = "DINNER", "Dinner"

    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="mess_feedback")
    week_day = models.CharField(max_length=3, choices=MessMenu.WeekDay.choices, default=MessMenu.WeekDay.MON)
    meal_time = models.CharField(max_length=12, choices=MealTime.choices, default=MealTime.BREAKFAST)
    menu_item = models.CharField(max_length=120)
    rating = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True)
    month = models.CharField(max_length=7)
    manager_reply = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        unique_together = ("student", "menu_item", "month")
        indexes = [
            models.Index(fields=["month", "created_at"], name="mess_fb_month_ct_idx"),
            models.Index(fields=["student", "created_at"], name="mess_fb_student_ct_idx"),
            models.Index(fields=["menu_item"], name="mess_fb_item_idx"),
        ]


class MenuPollOption(models.Model):
    class PollType(models.TextChoices):
        ADD = "ADD", "Add Request"
        REMOVE = "REMOVE", "Dislike Existing"

    month = models.CharField(max_length=7)
    item_name = models.CharField(max_length=120)
    poll_type = models.CharField(max_length=10, choices=PollType.choices, default=PollType.ADD)

    class Meta:
        unique_together = ("month", "item_name", "poll_type")
        indexes = [
            models.Index(fields=["month", "poll_type"], name="mess_poll_month_ty_idx"),
        ]


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
