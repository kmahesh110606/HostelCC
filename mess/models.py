from datetime import datetime, time, timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

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


class MessMenuArchive(models.Model):
    archived_month = models.CharField(max_length=7, db_index=True)
    mess_type = models.CharField(max_length=20, choices=MESS_TYPE_CHOICES, default=DEFAULT_MESS_TYPE, db_index=True)
    week_day = models.CharField(max_length=3, choices=MessMenu.WeekDay.choices, db_index=True)
    breakfast_items = models.TextField()
    lunch_items = models.TextField()
    snacks_items = models.TextField()
    dinner_items = models.TextField()
    archived_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-archived_month", "mess_type", "week_day"]
        unique_together = ("archived_month", "mess_type", "week_day")

    def __str__(self) -> str:
        return f"{self.archived_month} - {self.get_mess_type_display()} - {self.get_week_day_display()}"


class MessMonthlyArchive(models.Model):
    class Kind(models.TextChoices):
        FEEDBACK = "FEEDBACK", "Feedback Trends"
        POLL = "POLL", "Poll Snapshot"

    month = models.CharField(max_length=7, db_index=True)
    kind = models.CharField(max_length=20, choices=Kind.choices, db_index=True)
    payload = models.JSONField(default=dict)
    archived_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-month", "kind", "-archived_at"]
        unique_together = ("month", "kind")

    def __str__(self) -> str:
        return f"{self.month} - {self.get_kind_display()}"


class Caterer(models.Model):
    name = models.CharField(max_length=120)
    meal_types = models.CharField(max_length=20, choices=MESS_TYPE_CHOICES)
    block = models.ForeignKey(HostelBlock, on_delete=models.CASCADE, related_name="caterers")
    student_capacity = models.PositiveIntegerField(null=True, blank=True)

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


class NightMessLog(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="night_mess_logs")
    checked_out_at = models.DateTimeField(auto_now_add=True, db_index=True)
    checked_out_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="night_mess_checkout_logs",
    )
    returned_at = models.DateTimeField(null=True, blank=True, db_index=True)
    returned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="night_mess_return_logs",
    )

    class Meta:
        ordering = ["-checked_out_at"]
        indexes = [
            models.Index(fields=["student", "-checked_out_at"], name="night_mess_student_ct_idx"),
            models.Index(fields=["returned_at", "-checked_out_at"], name="night_mess_return_ct_idx"),
        ]

    @property
    def deadline_at(self):
        local_checkout = timezone.localtime(self.checked_out_at)
        deadline_date = local_checkout.date() + timedelta(days=1)
        naive_deadline = datetime.combine(deadline_date, time(hour=1, minute=0))
        return timezone.make_aware(naive_deadline, timezone.get_current_timezone())

    @property
    def is_overdue(self) -> bool:
        return self.returned_at is None and timezone.now() > self.deadline_at

    def __str__(self) -> str:
        return f"{self.student.roll_no} @ {self.checked_out_at.isoformat()}"
