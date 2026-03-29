import calendar
import json
import re
from datetime import date

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render

from .models import LaundryRoomRange, LaundrySchedule
from students.utils import resolve_student_for_user


def _is_laundry_manager_or_admin(user) -> bool:
    return user.role in {"LAUNDRY_PERSON", "LAUNDRY_MANAGER", "ADMIN"}


def _room_number_as_int(value: str):
    if not value:
        return None
    digits = re.findall(r"\d+", str(value))
    if not digits:
        return None
    return int("".join(digits))


def _room_in_rule(room_no: str, room_from: str, room_to: str) -> bool:
    room_int = _room_number_as_int(room_no)
    from_int = _room_number_as_int(room_from)
    to_int = _room_number_as_int(room_to)
    if room_int is not None and from_int is not None and to_int is not None:
        low, high = sorted((from_int, to_int))
        return low <= room_int <= high
    room_text = (room_no or "").strip().upper()
    from_text = (room_from or "").strip().upper()
    to_text = (room_to or "").strip().upper()
    low, high = sorted((from_text, to_text))
    return bool(room_text) and low <= room_text <= high


_DAY_SORT_ORDER = {
    LaundrySchedule.DayChoices.MON: 0,
    LaundrySchedule.DayChoices.TUE: 1,
    LaundrySchedule.DayChoices.WED: 2,
    LaundrySchedule.DayChoices.THU: 3,
    LaundrySchedule.DayChoices.FRI: 4,
    LaundrySchedule.DayChoices.SAT: 5,
    LaundrySchedule.DayChoices.SUN: 6,
}


def _infer_student_day_from_room_ranges(student):
    if not student or not student.block:
        return None

    rules = LaundryRoomRange.objects.filter(is_active=True, block_name__iexact=student.block.block_name)
    matching_days = {
        rule.day_of_week
        for rule in rules
        if _room_in_rule(student.room_no, rule.room_from, rule.room_to)
    }
    if not matching_days:
        return None

    return sorted(matching_days, key=lambda code: _DAY_SORT_ORDER.get(code, 99))[0]


def _get_or_create_schedule_for_student(student):
    if not student:
        return None

    schedule = (
        LaundrySchedule.objects.select_related("student", "student__block")
        .filter(student=student)
        .first()
    )
    if schedule:
        return schedule

    inferred_day = _infer_student_day_from_room_ranges(student)
    if not inferred_day:
        return None

    schedule, _ = LaundrySchedule.objects.get_or_create(
        student=student,
        defaults={"day_of_week": inferred_day},
    )
    return (
        LaundrySchedule.objects.select_related("student", "student__block")
        .filter(id=schedule.id)
        .first()
    )


def _build_student_month_days(student_schedule, room_rules):
    if not student_schedule:
        return [], "", 0

    today = date.today()
    year = today.year
    month = today.month
    month_name = today.strftime("%B")
    _, last_day = calendar.monthrange(year, month)

    day_code_map = {
        0: LaundrySchedule.DayChoices.MON,
        1: LaundrySchedule.DayChoices.TUE,
        2: LaundrySchedule.DayChoices.WED,
        3: LaundrySchedule.DayChoices.THU,
        4: LaundrySchedule.DayChoices.FRI,
        5: LaundrySchedule.DayChoices.SAT,
        6: LaundrySchedule.DayChoices.SUN,
    }

    highlight_days = set()
    if room_rules:
        room_no = student_schedule.student.room_no
        for day in range(1, last_day + 1):
            current = date(year, month, day)
            code = day_code_map[current.weekday()]
            for rule in room_rules:
                if rule.day_of_week == code and _room_in_rule(room_no, rule.room_from, rule.room_to):
                    highlight_days.add(day)
                    break
    else:
        for day in range(1, last_day + 1):
            current = date(year, month, day)
            code = day_code_map[current.weekday()]
            if code == student_schedule.day_of_week:
                highlight_days.add(day)

    days = []
    start_weekday = date(year, month, 1).weekday()
    for _ in range(start_weekday):
        days.append({"day": "", "highlighted": False, "today": False})

    for day in range(1, last_day + 1):
        days.append({"day": day, "highlighted": day in highlight_days, "today": day == today.day})

    while len(days) % 7 != 0:
        days.append({"day": "", "highlighted": False, "today": False})

    return days, month_name, year


@login_required
def laundry_portal(request: HttpRequest) -> HttpResponse:
    student_schedule = None
    if request.user.role == "STUDENT":
        student = resolve_student_for_user(request.user)
        if student:
            student_schedule = _get_or_create_schedule_for_student(student)

    is_laundry_manager = _is_laundry_manager_or_admin(request.user)

    if request.method == "POST":
        action = request.POST.get("action", "").strip()
        if action == "add_room_range" and is_laundry_manager:
            block_name = request.POST.get("block_name", "").strip().upper()
            day_of_week = request.POST.get("day_of_week", "").strip().upper()
            room_from = request.POST.get("room_from", "").strip().upper()
            room_to = request.POST.get("room_to", "").strip().upper()

            valid_days = {choice[0] for choice in LaundrySchedule.DayChoices.choices}
            if not block_name or day_of_week not in valid_days or not room_from or not room_to:
                messages.error(request, "Please provide block, day, and both room limits.")
            else:
                LaundryRoomRange.objects.create(
                    block_name=block_name,
                    day_of_week=day_of_week,
                    room_from=room_from,
                    room_to=room_to,
                    is_active=True,
                )
                messages.success(request, "Room range schedule added.")
            return redirect("laundry-portal")

        if action == "delete_room_range" and is_laundry_manager:
            range_id = request.POST.get("room_range_id", "").strip()
            if range_id.isdigit():
                LaundryRoomRange.objects.filter(id=int(range_id)).delete()
                messages.success(request, "Room range schedule removed.")
            else:
                messages.error(request, "Invalid room range selected.")
            return redirect("laundry-portal")

    block_filter = request.GET.get("block", "").strip().upper()
    status_filter = request.GET.get("status", "").strip().lower()
    sort_by = request.GET.get("sort", "day").strip().lower()

    manager_schedules = LaundrySchedule.objects.select_related("student", "student__block").all()
    if block_filter:
        manager_schedules = manager_schedules.filter(student__block__block_name=block_filter)
    if status_filter == "submitted":
        manager_schedules = manager_schedules.filter(submission_status=True)
    elif status_filter == "not_submitted":
        manager_schedules = manager_schedules.filter(submission_status=False)

    if sort_by == "student":
        manager_schedules = manager_schedules.order_by("student__roll_no")
    elif sort_by == "recent":
        manager_schedules = manager_schedules.order_by("-last_submission_at", "student__roll_no")
    else:
        manager_schedules = manager_schedules.order_by("day_of_week", "student__roll_no")

    all_room_ranges = LaundryRoomRange.objects.filter(is_active=True)
    room_ranges = all_room_ranges
    if block_filter:
        room_ranges = room_ranges.filter(block_name=block_filter)
    room_ranges = room_ranges.order_by("block_name", "day_of_week", "room_from")

    student_qr_text = ""
    if student_schedule:
        student_email = (request.user.email or request.user.username or "").strip().lower()
        block_name = student_schedule.student.block.block_name if student_schedule.student.block else ""
        room_no = student_schedule.student.room_no
        student_qr_text = json.dumps(
            {
                "student_id": student_schedule.student_id,
                "qr_token": str(student_schedule.qr_token),
                "roll_no": student_schedule.student.roll_no,
                "email": student_email,
                "room_no": room_no,
                "block_name": block_name,
            },
            separators=(",", ":"),
        )

    student_room_rules = []
    if student_schedule and student_schedule.student and student_schedule.student.block:
        student_block = student_schedule.student.block.block_name
        student_room_rules = list(all_room_ranges.filter(block_name__iexact=student_block))

    calendar_days, schedule_month_name, schedule_year = _build_student_month_days(student_schedule, student_room_rules)

    schedule_blocks = {
        choice
        for choice in LaundrySchedule.objects.values_list("student__block__block_name", flat=True).distinct()
        if choice
    }
    range_blocks = {
        choice
        for choice in LaundryRoomRange.objects.values_list("block_name", flat=True).distinct()
        if choice
    }

    return render(
        request,
        "laundry/portal.html",
        {
            "student_schedule": student_schedule,
            "student_qr_text": student_qr_text,
            "is_laundry_manager": is_laundry_manager,
            "manager_schedules": manager_schedules[:200] if is_laundry_manager else [],
            "block_filter": block_filter,
            "status_filter": status_filter,
            "sort_by": sort_by,
            "room_ranges": room_ranges if is_laundry_manager else [],
            "day_choices": LaundrySchedule.DayChoices.choices,
            "block_choices": sorted(schedule_blocks.union(range_blocks)),
            "calendar_days": calendar_days,
            "schedule_month_name": schedule_month_name,
            "schedule_year": schedule_year,
        },
    )
