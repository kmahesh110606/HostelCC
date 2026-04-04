import calendar
import logging
from datetime import date, datetime, time, timedelta

from django.core.exceptions import ObjectDoesNotExist
from rest_framework import serializers
from django.utils import timezone

from .models import LaundryEvent, LaundryHoliday, LaundryRoomRange, LaundrySchedule


logger = logging.getLogger(__name__)


def _safe_student_block_name(student) -> str:
    if not student:
        return ""
    try:
        block = student.block
    except ObjectDoesNotExist:
        return ""
    return (getattr(block, "block_name", "") or "").strip()


def _normalize_upper(value: str | None) -> str:
    return (value or "").strip().upper()


def _room_number_as_int(value: str | None):
    if not value:
        return None
    digits = "".join(ch for ch in str(value) if ch.isdigit())
    if not digits:
        return None
    return int(digits)


def _room_in_rule(room_no: str, room_from: str, room_to: str) -> bool:
    room_int = _room_number_as_int(room_no)
    from_int = _room_number_as_int(room_from)
    to_int = _room_number_as_int(room_to)
    if room_int is not None and from_int is not None and to_int is not None:
        low, high = sorted((from_int, to_int))
        return low <= room_int <= high

    room_text = _normalize_upper(room_no)
    from_text = _normalize_upper(room_from)
    to_text = _normalize_upper(room_to)
    low, high = sorted((from_text, to_text))
    return bool(room_text) and low <= room_text <= high


def _active_holiday_dates() -> list[date]:
    return list(
        LaundryHoliday.objects.filter(is_active=True)
        .order_by("holiday_date")
        .values_list("holiday_date", flat=True)
    )


def _shift_date_for_holidays(source_date: date, holiday_dates: list[date]) -> date:
    shifted = source_date
    while True:
        shift_days = sum(1 for holiday in holiday_dates if holiday <= shifted)
        next_date = source_date + timedelta(days=shift_days)
        if next_date == shifted:
            return shifted
        shifted = next_date


def _matching_room_rules_for_date(block_name: str, target_date: date):
    block_rules = list(LaundryRoomRange.objects.filter(is_active=True, block_name__iexact=block_name))
    holiday_dates = _active_holiday_dates()
    shifted_exact_rules = []
    for rule in block_rules:
        if not rule.scheduled_date:
            continue
        effective_date = _shift_date_for_holidays(rule.scheduled_date, holiday_dates)
        if effective_date == target_date:
            shifted_exact_rules.append(rule)
    if shifted_exact_rules:
        return shifted_exact_rules

    weekday_code = {
        0: LaundrySchedule.DayChoices.MON,
        1: LaundrySchedule.DayChoices.TUE,
        2: LaundrySchedule.DayChoices.WED,
        3: LaundrySchedule.DayChoices.THU,
        4: LaundrySchedule.DayChoices.FRI,
        5: LaundrySchedule.DayChoices.SAT,
        6: LaundrySchedule.DayChoices.SUN,
    }[target_date.weekday()]
    return [rule for rule in block_rules if rule.scheduled_date is None and rule.day_of_week == weekday_code]


def _is_submission_day(schedule: LaundrySchedule, target_date: date) -> bool:
    if not schedule or not schedule.student:
        return False

    student = schedule.student
    block_name = _safe_student_block_name(student)
    if block_name:
        matching_rules = _matching_room_rules_for_date(block_name, target_date)
        if matching_rules:
            return any(_room_in_rule(student.room_no, rule.room_from, rule.room_to) for rule in matching_rules)

    day_code = {
        0: LaundrySchedule.DayChoices.MON,
        1: LaundrySchedule.DayChoices.TUE,
        2: LaundrySchedule.DayChoices.WED,
        3: LaundrySchedule.DayChoices.THU,
        4: LaundrySchedule.DayChoices.FRI,
        5: LaundrySchedule.DayChoices.SAT,
        6: LaundrySchedule.DayChoices.SUN,
    }[target_date.weekday()]
    return schedule.day_of_week == day_code


def _next_submission_date(schedule: LaundrySchedule, start_date: date | None = None):
    from_date = start_date or timezone.localdate()
    for offset in range(0, 45):
        candidate = from_date + timedelta(days=offset)
        if _is_submission_day(schedule, candidate):
            return candidate
    return None


def _next_date_for_day_code(day_code: str, start_date: date | None = None):
    base = start_date or timezone.localdate()
    day_to_idx = {
        LaundrySchedule.DayChoices.MON: 0,
        LaundrySchedule.DayChoices.TUE: 1,
        LaundrySchedule.DayChoices.WED: 2,
        LaundrySchedule.DayChoices.THU: 3,
        LaundrySchedule.DayChoices.FRI: 4,
        LaundrySchedule.DayChoices.SAT: 5,
        LaundrySchedule.DayChoices.SUN: 6,
    }
    target = day_to_idx.get(day_code)
    if target is None:
        return None
    delta = (target - base.weekday()) % 7
    return base + timedelta(days=delta)


def _get_submission_days_for_month(schedule: LaundrySchedule, target_date: date | None = None) -> list[int]:
    """Get list of day numbers in the given month that are submission days for this student."""
    if not schedule:
        return []

    target = target_date or timezone.localdate()
    year, month = target.year, target.month
    _, last_day = calendar.monthrange(year, month)

    submission_days = []
    for day in range(1, last_day + 1):
        current_date = date(year, month, day)
        if _is_submission_day(schedule, current_date):
            submission_days.append(day)

    return submission_days


def _today_status(schedule: LaundrySchedule) -> dict[str, str]:
    today = timezone.localdate()
    tz = timezone.get_current_timezone()
    day_start = timezone.make_aware(datetime.combine(today, time.min), tz)
    day_end = day_start + timedelta(days=1)

    events_today = list(
        LaundryEvent.objects.filter(
            schedule=schedule,
            created_at__gte=day_start,
            created_at__lt=day_end,
        )
    )
    submitted_today = any(event.event_type == LaundryEvent.EventType.SUBMISSION for event in events_today)
    collected_today = any(event.event_type == LaundryEvent.EventType.COLLECTION for event in events_today)

    if collected_today:
        return {"code": "collected", "label": "Collected"}
    if schedule.laundry_done_at and schedule.submission_status:
        return {"code": "ready_for_collection", "label": "Ready for Collection"}
    if schedule.submission_status and not schedule.collection_status:
        return {"code": "in_progress", "label": "In Progress"}
    if _is_submission_day(schedule, today) and not submitted_today:
        return {"code": "ready", "label": "Ready to Submit"}
    if submitted_today and not collected_today:
        return {"code": "in_progress", "label": "In Progress"}
    return {"code": "not_today", "label": "No Laundry Action Today"}


class LaundryScheduleSerializer(serializers.ModelSerializer):
    student_roll_no = serializers.SerializerMethodField()
    block_name = serializers.SerializerMethodField()
    room_no = serializers.SerializerMethodField()
    last_submission_at = serializers.DateTimeField(read_only=True, default_timezone=timezone.get_current_timezone())
    due_collection_by = serializers.DateTimeField(read_only=True, default_timezone=timezone.get_current_timezone())
    laundry_done_at = serializers.DateTimeField(read_only=True, default_timezone=timezone.get_current_timezone())
    token_assigned_at = serializers.DateTimeField(read_only=True, default_timezone=timezone.get_current_timezone())
    today_status_code = serializers.SerializerMethodField()
    today_status_label = serializers.SerializerMethodField()
    next_submission_date = serializers.SerializerMethodField()
    server_today_ist = serializers.SerializerMethodField()
    month_submission_days = serializers.SerializerMethodField()

    def _status_cache_key(self, obj: LaundrySchedule) -> str:
        return f"_cached_today_status_{obj.id}"

    def _next_date_cache_key(self, obj: LaundrySchedule) -> str:
        return f"_cached_next_submission_date_{obj.id}"

    def _get_cached_today_status(self, obj: LaundrySchedule) -> dict[str, str]:
        key = self._status_cache_key(obj)
        cached = getattr(self, key, None)
        if cached is not None:
            return cached

        request = self.context.get("request")
        role = getattr(getattr(request, "user", None), "role", "") if request else ""
        try:
            if role == "STUDENT":
                computed = _today_status(obj)
            else:
                # Lightweight status for large manager/admin lists to avoid timeout.
                if obj.collection_status and not obj.submission_status:
                    computed = {"code": "collected", "label": "Collected"}
                elif obj.laundry_done_at and obj.submission_status:
                    computed = {"code": "ready_for_collection", "label": "Ready for Collection"}
                elif obj.submission_status and not obj.collection_status:
                    computed = {"code": "in_progress", "label": "In Progress"}
                else:
                    computed = {"code": "ready", "label": "Ready to Submit"}
        except Exception:
            logger.exception("Failed to compute today_status for laundry schedule id=%s", getattr(obj, "id", None))
            computed = {"code": "ready", "label": "Ready to Submit"}

        setattr(self, key, computed)
        return computed

    def _get_cached_next_submission_date(self, obj: LaundrySchedule):
        key = self._next_date_cache_key(obj)
        cached = getattr(self, key, None)
        if cached is not None:
            return cached

        request = self.context.get("request")
        role = getattr(getattr(request, "user", None), "role", "") if request else ""
        try:
            if role == "STUDENT":
                computed = _next_submission_date(obj)
            else:
                computed = _next_date_for_day_code(obj.day_of_week)
        except Exception:
            logger.exception(
                "Failed to compute next_submission_date for laundry schedule id=%s",
                getattr(obj, "id", None),
            )
            computed = None

        setattr(self, key, computed)
        return computed

    def get_today_status_code(self, obj: LaundrySchedule) -> str:
        return self._get_cached_today_status(obj)["code"]

    def get_today_status_label(self, obj: LaundrySchedule) -> str:
        return self._get_cached_today_status(obj)["label"]

    def get_student_roll_no(self, obj: LaundrySchedule) -> str:
        student = getattr(obj, "student", None)
        return (getattr(student, "roll_no", "") or "").strip()

    def get_room_no(self, obj: LaundrySchedule) -> str:
        student = getattr(obj, "student", None)
        return (getattr(student, "room_no", "") or "").strip()

    def get_block_name(self, obj: LaundrySchedule) -> str:
        student = getattr(obj, "student", None)
        return _safe_student_block_name(student)

    def get_next_submission_date(self, obj: LaundrySchedule):
        next_date = self._get_cached_next_submission_date(obj)
        return next_date.isoformat() if next_date else None

    def get_server_today_ist(self, obj: LaundrySchedule) -> str:
        return timezone.localdate().isoformat()

    def get_month_submission_days(self, obj: LaundrySchedule) -> list[int]:
        """Return list of day numbers in current month that are submission days for this student."""
        try:
            return _get_submission_days_for_month(obj)
        except Exception:
            logger.exception(
                "Failed to compute month_submission_days for laundry schedule id=%s",
                getattr(obj, "id", None),
            )
            return []

    class Meta:
        model = LaundrySchedule
        fields = [
            "id",
            "student",
            "student_roll_no",
            "block_name",
            "room_no",
            "day_of_week",
            "holidays",
            "qr_token",
            "submission_status",
            "collection_status",
            "assigned_token_code",
            "last_submission_at",
            "laundry_done_at",
            "token_assigned_at",
            "due_collection_by",
            "today_status_code",
            "today_status_label",
            "next_submission_date",
            "server_today_ist",
            "month_submission_days",
        ]


class LaundryEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = LaundryEvent
        fields = ["id", "student", "schedule", "event_type", "scanned_by", "created_at"]
        read_only_fields = ["scanned_by", "created_at"]


class LaundryRoomRangeSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        day_of_week = attrs.get("day_of_week", getattr(self.instance, "day_of_week", None))
        scheduled_date = attrs.get("scheduled_date", getattr(self.instance, "scheduled_date", None))
        if not day_of_week and not scheduled_date:
            raise serializers.ValidationError("Provide either scheduled_date or day_of_week.")
        return attrs

    class Meta:
        model = LaundryRoomRange
        fields = [
            "id",
            "block_name",
            "day_of_week",
            "scheduled_date",
            "room_from",
            "room_to",
            "is_active",
            "created_at",
        ]
        read_only_fields = ["created_at"]


class LaundryHolidaySerializer(serializers.ModelSerializer):
    class Meta:
        model = LaundryHoliday
        fields = ["id", "holiday_date", "name", "is_active", "created_at"]
        read_only_fields = ["created_at"]
