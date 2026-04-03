import calendar
import csv
import io
import json
import re
from datetime import date, datetime, time, timedelta

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.core.cache import cache
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import redirect, render
from django.utils.dateparse import parse_date
from django.utils import timezone

from .models import LaundryEvent, LaundryHoliday, LaundryRoomRange, LaundrySchedule
from .qr_utils import build_qr_svg
from students.models import Student
from students.utils import resolve_student_for_user


def _is_laundry_manager_or_admin(user) -> bool:
    return user.role in {"LAUNDRY_PERSON", "LAUNDRY_MANAGER", "ADMIN"}


def _is_admin(user) -> bool:
    return getattr(user, "role", "") == "ADMIN"


_LAUNDRY_ADMIN_CACHE_VERSION_KEY = "laundry:admin-data-version"


def _get_laundry_admin_cache_version() -> int:
    version = cache.get(_LAUNDRY_ADMIN_CACHE_VERSION_KEY, 1)
    try:
        return int(version)
    except (TypeError, ValueError):
        return 1


def _bump_laundry_admin_cache_version() -> None:
    cache.set(_LAUNDRY_ADMIN_CACHE_VERSION_KEY, _get_laundry_admin_cache_version() + 1, timeout=None)


def _normalize_block_name(value: str | None) -> str:
    return re.sub(r"[^A-Z0-9]", "", (value or "").strip().upper())


def _parse_token_code(value: str | None):
    text = (value or "").strip().upper()
    match = re.fullmatch(r"CDLS-([A-Z0-9]+)-(\d{4})", text)
    if not match:
        return None

    token_no = int(match.group(2))
    if token_no < 1000 or token_no > 2000:
        return None

    return {
        "token_code": f"CDLS-{match.group(1)}-{token_no:04d}",
        "block_name": match.group(1),
        "token_no": token_no,
    }


def _build_token_tag_download_html(block_name: str, token_start: int, token_end: int) -> str:
    tag_cards = []
    for token_no in range(token_start, token_end + 1):
        token_code = f"CDLS-{block_name}-{token_no:04d}"
        qr_svg = build_qr_svg(token_code, box_size=6, border=2)
        if not qr_svg:
            continue

        tag_cards.append(
            f"""
            <div class="tag-card">
              <div class="tag-qr">{qr_svg}</div>
              <div class="tag-code">{token_code}</div>
            </div>
            """
        )

    cards_html = "\n".join(tag_cards)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Laundry Token Tags - {block_name}</title>
  <style>
    @page {{ size: A4; margin: 10mm; }}
    body {{ font-family: Arial, sans-serif; margin: 0; color: #111; }}
    .page-header {{ margin-bottom: 10px; }}
    .page-title {{ font-size: 20px; font-weight: 700; margin: 0; }}
    .page-subtitle {{ font-size: 12px; color: #444; margin: 4px 0 0; }}
    .tag-grid {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }}
    .tag-card {{ border: 1px solid #222; border-radius: 10px; padding: 10px; min-height: 175px; display: flex; flex-direction: column; align-items: center; justify-content: center; page-break-inside: avoid; }}
    .tag-qr svg {{ width: 118px; height: 118px; }}
    .tag-code {{ margin-top: 8px; font-size: 12px; font-weight: 700; text-align: center; word-break: break-word; }}
  </style>
</head>
<body>
  <div class="page-header">
    <h1 class="page-title">Laundry Token Tags</h1>
    <p class="page-subtitle">Block: {block_name} | Tokens: {token_start:04d}-{token_end:04d}</p>
  </div>
  <div class="tag-grid">
    {cards_html}
  </div>
</body>
</html>"""


def _get_token_assignment_rows(block_filter: str = ""):
    queryset = (
        LaundrySchedule.objects.select_related("student", "student__block", "student__user")
        .filter(submission_status=True)
        .exclude(assigned_token_code="")
        .order_by("student__block__block_name", "student__room_no", "student__roll_no")
    )
    if block_filter:
        queryset = queryset.filter(student__block__block_name__iexact=block_filter)

    rows = []
    for schedule in queryset:
        student = schedule.student
        rows.append(
            {
                "token_code": schedule.assigned_token_code,
                "student_roll_no": student.roll_no if student else "",
                "student_name": student.name if student else "",
                "block_name": student.block.block_name if student and student.block else "",
                "room_no": student.room_no if student else "",
                "assigned_at": timezone.localtime(schedule.token_assigned_at) if schedule.token_assigned_at else None,
                "ready_at": timezone.localtime(schedule.laundry_done_at) if schedule.laundry_done_at else None,
            }
        )
    return rows


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


def _local_today() -> date:
    return timezone.localdate()


def _local_day_bounds(target_date: date):
    tz = timezone.get_current_timezone()
    start = timezone.make_aware(datetime.combine(target_date, time.min), tz)
    end = start + timedelta(days=1)
    return start, end


def _local_date_from_dt(value):
    if not value:
        return None
    return timezone.localtime(value).date()


def _infer_student_day_from_room_ranges(student):
    if not student or not student.block:
        return None

    rules = LaundryRoomRange.objects.filter(
        is_active=True,
        block_name__iexact=student.block.block_name,
    )
    matching_rules = [rule for rule in rules if _room_in_rule(student.room_no, rule.room_from, rule.room_to)]
    if not matching_rules:
        return None

    matching_days = {
        rule.day_of_week
        for rule in matching_rules
        if rule.day_of_week
    }
    if matching_days:
        return sorted(matching_days, key=lambda code: _DAY_SORT_ORDER.get(code, 99))[0]

    dated_rules = sorted(
        [rule for rule in matching_rules if rule.scheduled_date],
        key=lambda rule: (rule.scheduled_date < _local_today(), rule.scheduled_date),
    )
    if not dated_rules:
        return None

    weekday_code = {
        0: LaundrySchedule.DayChoices.MON,
        1: LaundrySchedule.DayChoices.TUE,
        2: LaundrySchedule.DayChoices.WED,
        3: LaundrySchedule.DayChoices.THU,
        4: LaundrySchedule.DayChoices.FRI,
        5: LaundrySchedule.DayChoices.SAT,
        6: LaundrySchedule.DayChoices.SUN,
    }
    return weekday_code[dated_rules[0].scheduled_date.weekday()]


def _active_holiday_dates(cache: list | None = None):
    """Get active holiday dates, using provided cache if available."""
    if cache is not None:
        return cache
    return list(
        LaundryHoliday.objects.filter(is_active=True)
        .order_by("holiday_date")
        .values_list("holiday_date", flat=True)
    )


def _shift_date_for_holidays(source_date: date, holiday_dates):
    shifted = source_date
    while True:
        shift_days = sum(1 for holiday in holiday_dates if holiday <= shifted)
        next_date = source_date + timedelta(days=shift_days)
        if next_date == shifted:
            return shifted
        shifted = next_date


def _matching_room_rules_for_date(block_name: str, target_date: date, preloaded_rules=None, holiday_cache=None):
    """Match room rules for a specific date, supporting holiday caching."""
    if preloaded_rules is None:
        block_rules = list(LaundryRoomRange.objects.filter(is_active=True, block_name__iexact=block_name))
    else:
        block_rules = list(preloaded_rules)

    holiday_dates = _active_holiday_dates(cache=holiday_cache)
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


def _build_admin_month_calendar(room_ranges, holidays, year: int, month: int, block_filter: str = ""):
    _, last_day = calendar.monthrange(year, month)
    holiday_set = set(holidays)

    ranges_by_block = {}
    for rule in room_ranges:
        block_key = (rule.block_name or "").strip().upper()
        if not block_key:
            continue
        ranges_by_block.setdefault(block_key, []).append(rule)

    blocks = sorted(ranges_by_block.keys())
    cells = []
    for day in range(1, last_day + 1):
        current = date(year, month, day)
        slots = []
        if block_filter:
            selected_blocks = [block_filter] if block_filter in ranges_by_block else []
        else:
            selected_blocks = blocks

        for block in selected_blocks:
            matching_rules = _matching_room_rules_for_date(
                block,
                current,
                preloaded_rules=ranges_by_block.get(block, []),
                holiday_cache=holidays,
            )
            for rule in matching_rules:
                slots.append(
                    {
                        "block": block,
                        "room_from": rule.room_from,
                        "room_to": rule.room_to,
                    }
                )

        cells.append(
            {
                "day": day,
                "date_iso": current.isoformat(),
                "is_today": current == _local_today(),
                "is_holiday": current in holiday_set,
                "slots": slots,
            }
        )

    start_weekday = date(year, month, 1).weekday()
    for _ in range(start_weekday):
        cells.insert(0, {"day": "", "is_blank": True})
    while len(cells) % 7 != 0:
        cells.append({"day": "", "is_blank": True})

    return cells


def _parse_day_code(raw_value: str | None):
    value = (raw_value or "").strip().upper()
    if not value:
        return None
    valid_days = {choice[0] for choice in LaundrySchedule.DayChoices.choices}
    if value in valid_days:
        return value
    return None


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


def _build_student_month_days(student_schedule, room_rules, holiday_cache=None):
    if not student_schedule:
        return [], "", 0

    today = _local_today()
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
    room_no = student_schedule.student.room_no
    if room_rules:
        block_name = student_schedule.student.block.block_name if student_schedule.student.block else ""
        for day in range(1, last_day + 1):
            current = date(year, month, day)
            matching_rules = _matching_room_rules_for_date(block_name, current, preloaded_rules=room_rules, holiday_cache=holiday_cache)
            if any(_room_in_rule(room_no, rule.room_from, rule.room_to) for rule in matching_rules):
                highlight_days.add(day)
    else:
        for day in range(1, last_day + 1):
            current = date(year, month, day)
            code = day_code_map[current.weekday()]
            if code == student_schedule.day_of_week:
                highlight_days.add(day)

    month_start = date(year, month, 1)
    month_end = date(year, month, last_day)

    events = list(
        LaundryEvent.objects.filter(schedule=student_schedule)
        .order_by("created_at")
    )
    submitted_days = set()
    pending_submission_dates = []
    for event in events:
        event_day = _local_date_from_dt(event.created_at)
        if not event_day or event_day > month_end:
            continue
        if event.event_type == LaundryEvent.EventType.SUBMISSION:
            pending_submission_dates.append(event_day)
            if month_start <= event_day <= month_end:
                submitted_days.add(event_day.day)
        elif event.event_type == LaundryEvent.EventType.COLLECTION and pending_submission_dates:
            pending_submission_dates.pop(0)

    pending_days = {
        submitted_date.day
        for submitted_date in pending_submission_dates
        if month_start <= submitted_date <= month_end
    }

    days = []
    start_weekday = date(year, month, 1).weekday()
    for _ in range(start_weekday):
        days.append({"day": "", "highlighted": False, "today": False, "status": "blank"})

    for day in range(1, last_day + 1):
        current = date(year, month, day)
        is_scheduled = day in highlight_days
        status = "none"
        if is_scheduled:
            if day in pending_days:
                status = "pending_collection"
            elif day in submitted_days:
                status = "submitted"
            elif current < today:
                status = "skipped"
            else:
                status = "scheduled"

        days.append(
            {
                "day": day,
                "highlighted": is_scheduled,
                "today": day == today.day,
                "status": status,
            }
        )

    while len(days) % 7 != 0:
        days.append({"day": "", "highlighted": False, "today": False, "status": "blank"})

    return days, month_name, year


def _is_student_submission_day(student_schedule, target_date: date, room_rules, holiday_cache=None) -> bool:
    if not student_schedule:
        return False

    room_no = student_schedule.student.room_no
    block_name = student_schedule.student.block.block_name if student_schedule.student.block else ""
    if room_rules and block_name:
        matching_rules = _matching_room_rules_for_date(
            block_name,
            target_date,
            preloaded_rules=room_rules,
            holiday_cache=holiday_cache,
        )
        return any(_room_in_rule(room_no, rule.room_from, rule.room_to) for rule in matching_rules)

    weekday_code = {
        0: LaundrySchedule.DayChoices.MON,
        1: LaundrySchedule.DayChoices.TUE,
        2: LaundrySchedule.DayChoices.WED,
        3: LaundrySchedule.DayChoices.THU,
        4: LaundrySchedule.DayChoices.FRI,
        5: LaundrySchedule.DayChoices.SAT,
        6: LaundrySchedule.DayChoices.SUN,
    }[target_date.weekday()]
    return student_schedule.day_of_week == weekday_code


def _next_submission_date(student_schedule, room_rules, holiday_cache=None, start_date: date | None = None):
    if not student_schedule:
        return None

    from_date = start_date or _local_today()
    for offset in range(0, 45):
        candidate = from_date + timedelta(days=offset)
        if _is_student_submission_day(student_schedule, candidate, room_rules, holiday_cache=holiday_cache):
            return candidate
    return None


def _student_today_status(student_schedule, room_rules, holiday_cache=None):
    if not student_schedule:
        return {"code": "none", "label": "No schedule", "dot": "dot-red"}

    today = _local_today()
    today_start, today_end = _local_day_bounds(today)
    events_today = list(
        LaundryEvent.objects.filter(
            schedule=student_schedule,
            created_at__gte=today_start,
            created_at__lt=today_end,
        ).order_by("created_at")
    )

    submitted_today = any(event.event_type == LaundryEvent.EventType.SUBMISSION for event in events_today)
    collected_today = any(event.event_type == LaundryEvent.EventType.COLLECTION for event in events_today)
    is_submission_day = _is_student_submission_day(student_schedule, today, room_rules, holiday_cache=holiday_cache)

    if collected_today:
        return {"code": "collected", "label": "Collected", "dot": "dot-green"}
    if student_schedule.submission_status and not student_schedule.collection_status:
        return {"code": "in_progress", "label": "In Progress", "dot": "dot-yellow"}
    if is_submission_day and not submitted_today:
        return {"code": "ready", "label": "Ready to Submit", "dot": "dot-blue"}
    if submitted_today and not collected_today:
        return {"code": "in_progress", "label": "In Progress", "dot": "dot-yellow"}
    return {"code": "not_today", "label": "No Laundry Action Today", "dot": "dot-red"}


def _build_manager_block_ranges_for_today(
    *,
    block_filter: str,
    status_filter: str,
    room_rules_by_block: dict,
    holiday_dates: list,
):
    today = _local_today()

    if block_filter:
        candidate_blocks = [block_filter]
    else:
        candidate_blocks = sorted(room_rules_by_block.keys())

    if not candidate_blocks:
        return []

    students = list(
        Student.objects.select_related("block")
        .filter(block__block_name__in=candidate_blocks)
        .order_by("block__block_name", "room_no", "roll_no")
    )
    students_by_block = {}
    for student in students:
        block_name = (student.block.block_name if student.block else "").strip().upper()
        if not block_name:
            continue
        students_by_block.setdefault(block_name, []).append(student)

    schedules = list(
        LaundrySchedule.objects.select_related("student", "student__block")
        .filter(student__block__block_name__in=candidate_blocks)
    )
    schedule_by_student_id = {schedule.student_id: schedule for schedule in schedules}

    manager_blocks = []
    for block_name in candidate_blocks:
        block_rules = room_rules_by_block.get(block_name, [])
        today_rules = _matching_room_rules_for_date(
            block_name,
            today,
            preloaded_rules=block_rules,
            holiday_cache=holiday_dates,
        )
        if not today_rules:
            continue

        range_rows = []
        block_students = students_by_block.get(block_name, [])
        for rule in sorted(today_rules, key=lambda item: (_room_number_as_int(item.room_from) or 0, item.room_from)):
            students_in_range = []
            for student in block_students:
                if not _room_in_rule(student.room_no, rule.room_from, rule.room_to):
                    continue

                schedule = schedule_by_student_id.get(student.id)
                if schedule:
                    status = _student_today_status(schedule, block_rules, holiday_cache=holiday_dates)
                    if status["code"] in {"ready", "not_today", "none"}:
                        status = {"code": status["code"], "label": status["label"], "dot": "dot-red"}
                else:
                    status = {"code": "none", "label": "No Schedule", "dot": "dot-red"}

                if status_filter == "submitted" and status["code"] not in {"in_progress", "collected"}:
                    continue
                if status_filter == "not_submitted" and status["code"] in {"in_progress", "collected"}:
                    continue

                students_in_range.append(
                    {
                        "roll_no": student.roll_no,
                        "name": student.name,
                        "room_no": student.room_no,
                        "status": status,
                    }
                )

            range_rows.append(
                {
                    "range_label": f"{rule.room_from} - {rule.room_to}",
                    "room_from": rule.room_from,
                    "room_to": rule.room_to,
                    "student_count": len(students_in_range),
                    "students": students_in_range,
                }
            )

        manager_blocks.append(
            {
                "block": block_name,
                "date": today,
                "ranges": range_rows,
                "range_count": len(range_rows),
            }
        )

    return manager_blocks


@login_required
def laundry_portal(request: HttpRequest) -> HttpResponse:
    student_schedule = None
    if request.user.role == "STUDENT":
        student = resolve_student_for_user(request.user)
        if student:
            student_schedule = _get_or_create_schedule_for_student(student)

    is_laundry_manager = _is_laundry_manager_or_admin(request.user)
    is_admin = _is_admin(request.user)

    if request.method == "POST":
        action = request.POST.get("action", "").strip()
        if action == "add_room_range" and is_laundry_manager:
            block_name = request.POST.get("block_name", "").strip().upper()
            scheduled_date_text = request.POST.get("scheduled_date", "").strip()
            scheduled_date = parse_date(scheduled_date_text) if scheduled_date_text else None
            day_of_week = request.POST.get("day_of_week", "").strip().upper() or None
            room_from = request.POST.get("room_from", "").strip().upper()
            room_to = request.POST.get("room_to", "").strip().upper()

            valid_days = {choice[0] for choice in LaundrySchedule.DayChoices.choices}
            if day_of_week and day_of_week not in valid_days:
                messages.error(request, "Invalid weekday selected.")
            elif not block_name or not room_from or not room_to:
                messages.error(request, "Please provide block and both room limits.")
            elif not scheduled_date and not day_of_week:
                messages.error(request, "Please provide either an exact date or a weekday.")
            else:
                LaundryRoomRange.objects.create(
                    block_name=block_name,
                    day_of_week=day_of_week,
                    scheduled_date=scheduled_date,
                    room_from=room_from,
                    room_to=room_to,
                    is_active=True,
                )
                _bump_laundry_admin_cache_version()
                if scheduled_date:
                    messages.success(request, "Date-wise room range schedule added.")
                else:
                    messages.success(request, "Weekday room range schedule added.")
            return redirect("laundry-portal")

        if action == "bulk_upload_room_ranges" and is_laundry_manager:
            uploaded = request.FILES.get("room_ranges_csv")
            default_block = request.POST.get("default_block_name", "").strip().upper()
            if not uploaded:
                messages.error(request, "Please upload a CSV file.")
                return redirect("laundry-portal")

            try:
                content = uploaded.read().decode("utf-8-sig")
            except UnicodeDecodeError:
                messages.error(request, "CSV must be UTF-8 encoded.")
                return redirect("laundry-portal")

            reader = csv.DictReader(io.StringIO(content))
            if not reader.fieldnames:
                messages.error(request, "CSV is missing headers.")
                return redirect("laundry-portal")

            created_count = 0
            error_rows = []
            for row_index, row in enumerate(reader, start=2):
                block_name = (row.get("block_name") or default_block or "").strip().upper()
                room_from = (row.get("room_from") or "").strip().upper()
                room_to = (row.get("room_to") or "").strip().upper()
                scheduled_date_text = (row.get("scheduled_date") or row.get("date") or "").strip()
                scheduled_date = parse_date(scheduled_date_text) if scheduled_date_text else None
                day_of_week = _parse_day_code(row.get("day_of_week"))

                if not block_name or not room_from or not room_to:
                    error_rows.append(f"Row {row_index}: block_name/room_from/room_to required.")
                    continue
                if not scheduled_date and not day_of_week:
                    error_rows.append(f"Row {row_index}: provide scheduled_date (or date) or day_of_week.")
                    continue

                LaundryRoomRange.objects.create(
                    block_name=block_name,
                    scheduled_date=scheduled_date,
                    day_of_week=day_of_week,
                    room_from=room_from,
                    room_to=room_to,
                    is_active=True,
                )
                created_count += 1

            if created_count:
                _bump_laundry_admin_cache_version()
                messages.success(request, f"Bulk upload complete. Added {created_count} room-range slots.")
            if error_rows:
                preview = " ".join(error_rows[:5])
                messages.error(request, f"Some rows were skipped. {preview}")
            return redirect("laundry-portal")

        if action == "delete_room_range" and is_laundry_manager:
            range_id = request.POST.get("room_range_id", "").strip()
            if range_id.isdigit():
                deleted_count, _ = LaundryRoomRange.objects.filter(id=int(range_id)).delete()
                if deleted_count:
                    _bump_laundry_admin_cache_version()
                    if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                        return JsonResponse({"success": True, "deleted_count": deleted_count})
                    messages.success(request, "Room range schedule removed.")
                else:
                    if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                        return JsonResponse({"success": False, "error": "Room range not found."}, status=404)
                    messages.error(request, "Room range not found.")
            else:
                if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                    return JsonResponse({"success": False, "error": "Invalid room range selected."}, status=400)
                messages.error(request, "Invalid room range selected.")
            return redirect("laundry-portal")

        if action == "delete_all_room_ranges" and is_laundry_manager:
            visible_room_ranges = LaundryRoomRange.objects.filter(is_active=True)
            current_block_filter = request.GET.get("block", "").strip().upper()
            if current_block_filter:
                visible_room_ranges = visible_room_ranges.filter(block_name=current_block_filter)

            deleted_count = visible_room_ranges.count()
            visible_room_ranges.delete()
            if deleted_count:
                _bump_laundry_admin_cache_version()

            if request.headers.get("X-Requested-With") == "XMLHttpRequest":
                return JsonResponse({"success": True, "deleted_count": deleted_count})

            if deleted_count:
                messages.success(request, f"Removed {deleted_count} room ranges.")
            else:
                messages.info(request, "No room ranges matched the current view.")
            return redirect("laundry-portal")

        if action == "add_holiday" and is_laundry_manager:
            holiday_date_text = request.POST.get("holiday_date", "").strip()
            holiday_name = request.POST.get("holiday_name", "").strip()
            holiday_date = parse_date(holiday_date_text) if holiday_date_text else None
            if not holiday_date:
                messages.error(request, "Please provide a valid holiday date.")
            else:
                LaundryHoliday.objects.update_or_create(
                    holiday_date=holiday_date,
                    defaults={"name": holiday_name, "is_active": True},
                )
                _bump_laundry_admin_cache_version()
                messages.success(request, "Holiday declared. Date-wise laundry schedule will auto-shift.")
            return redirect("laundry-portal")

        if action == "delete_holiday" and is_laundry_manager:
            holiday_id = request.POST.get("holiday_id", "").strip()
            if holiday_id.isdigit():
                deleted_count, _ = LaundryHoliday.objects.filter(id=int(holiday_id)).delete()
                if deleted_count:
                    _bump_laundry_admin_cache_version()
                    messages.success(request, "Holiday removed.")
                else:
                    messages.error(request, "Holiday not found.")
            else:
                messages.error(request, "Invalid holiday selected.")
            return redirect("laundry-portal")

    block_filter = request.GET.get("block", "").strip().upper()
    status_filter = request.GET.get("status", "").strip().lower()
    sort_by = request.GET.get("sort", "day").strip().lower()
    selected_month = request.GET.get("month", "").strip()
    selected_year = request.GET.get("year", "").strip()

    manager_schedules = []

    all_room_ranges = LaundryRoomRange.objects.filter(is_active=True)
    room_ranges = all_room_ranges
    if block_filter:
        room_ranges = room_ranges.filter(block_name=block_filter)
    room_ranges = room_ranges.order_by("block_name", "scheduled_date", "day_of_week", "room_from")
    holidays = LaundryHoliday.objects.filter(is_active=True).order_by("holiday_date")
    holiday_dates = list(holidays.values_list("holiday_date", flat=True))
    all_room_ranges_list = list(all_room_ranges)

    room_rules_by_block = {}
    for rule in all_room_ranges_list:
        block_key = (rule.block_name or "").strip().upper()
        if not block_key:
            continue
        room_rules_by_block.setdefault(block_key, []).append(rule)

    manager_block_ranges_today = []
    if is_laundry_manager:
        manager_block_ranges_today = _build_manager_block_ranges_for_today(
            block_filter=block_filter,
            status_filter=status_filter,
            room_rules_by_block=room_rules_by_block,
            holiday_dates=holiday_dates,
        )

    token_assignment_rows = _get_token_assignment_rows(block_filter=block_filter) if is_laundry_manager else []

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

    calendar_days, schedule_month_name, schedule_year = _build_student_month_days(student_schedule, student_room_rules, holiday_cache=holiday_dates)

    student_today_status = _student_today_status(student_schedule, student_room_rules, holiday_cache=holiday_dates)
    next_submission_date = _next_submission_date(student_schedule, student_room_rules, holiday_cache=holiday_dates)
    last_submission_local = timezone.localtime(student_schedule.last_submission_at) if student_schedule and student_schedule.last_submission_at else None
    due_collection_local = (
        timezone.localtime(student_schedule.due_collection_by)
        if student_schedule and student_schedule.due_collection_by and student_schedule.submission_status and not student_schedule.collection_status
        else None
    )

    today = _local_today()
    try:
        calendar_month = int(selected_month) if selected_month else today.month
    except ValueError:
        calendar_month = today.month
    try:
        calendar_year = int(selected_year) if selected_year else today.year
    except ValueError:
        calendar_year = today.year
    if calendar_month < 1 or calendar_month > 12:
        calendar_month = today.month

    admin_calendar_cells = []
    if is_laundry_manager:
        cache_version = _get_laundry_admin_cache_version()
        calendar_cache_key = f"laundry:admin-calendar:v{cache_version}:{calendar_year}:{calendar_month}:{block_filter or 'ALL'}"
        admin_calendar_cells = cache.get(calendar_cache_key)
        if admin_calendar_cells is None:
            admin_calendar_cells = _build_admin_month_calendar(
                room_ranges=all_room_ranges_list,
                holidays=holiday_dates,
                year=calendar_year,
                month=calendar_month,
                block_filter=block_filter,
            )
            cache.set(calendar_cache_key, admin_calendar_cells, timeout=120)

    block_choices_cache_key = f"laundry:block-choices:v{_get_laundry_admin_cache_version()}"
    block_choices = cache.get(block_choices_cache_key)
    if block_choices is None:
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
        block_choices = sorted(schedule_blocks.union(range_blocks))
        cache.set(block_choices_cache_key, block_choices, timeout=300)

    return render(
        request,
        "laundry/portal.html",
        {
            "student_schedule": student_schedule,
            "student_qr_text": student_qr_text,
            "is_laundry_manager": is_laundry_manager,
            "is_admin": is_admin,
            "manager_schedules": manager_schedules,
            "manager_block_ranges_today": manager_block_ranges_today,
            "token_assignment_rows": token_assignment_rows,
            "block_filter": block_filter,
            "status_filter": status_filter,
            "sort_by": sort_by,
            "room_ranges": room_ranges if is_laundry_manager else [],
            "day_choices": LaundrySchedule.DayChoices.choices,
            "block_choices": block_choices,
            "calendar_days": calendar_days,
            "schedule_month_name": schedule_month_name,
            "schedule_year": schedule_year,
            "student_today_status": student_today_status,
            "next_submission_date": next_submission_date,
            "last_submission_local": last_submission_local,
            "due_collection_local": due_collection_local,
            "holidays": holidays,
            "admin_calendar_cells": admin_calendar_cells if is_laundry_manager else [],
            "admin_calendar_month": calendar_month,
            "admin_calendar_year": calendar_year,
        },
    )


@login_required
def download_laundry_token_tags(request: HttpRequest) -> HttpResponse:
    if not _is_admin(request.user):
        messages.error(request, "Only admin can download token tags.")
        return redirect("laundry-portal")

    block_name = _normalize_block_name(request.GET.get("block_name"))
    token_start_raw = (request.GET.get("start") or "1000").strip()
    token_end_raw = (request.GET.get("end") or "2000").strip()

    if not block_name:
        messages.error(request, "Please choose a block before downloading token tags.")
        return redirect("laundry-portal")

    try:
        token_start = int(token_start_raw)
        token_end = int(token_end_raw)
    except ValueError:
        messages.error(request, "Token range must be numeric.")
        return redirect("laundry-portal")

    if token_start < 1000 or token_end > 2000 or token_start > token_end:
        messages.error(request, "Token range must stay within 1000-2000.")
        return redirect("laundry-portal")

    html = _build_token_tag_download_html(block_name, token_start, token_end)
    response = HttpResponse(html, content_type="text/html; charset=utf-8")
    response["Content-Disposition"] = (
        f'attachment; filename="laundry-token-tags-{block_name}-{token_start:04d}-{token_end:04d}.html"'
    )
    return response


@login_required
def download_laundry_logs_csv(request: HttpRequest) -> HttpResponse:
    if not _is_admin(request.user):
        messages.error(request, "Only admin can download laundry logs.")
        return redirect("dashboard-router")

    logs = (
        LaundryEvent.objects.select_related(
            "student",
            "student__block",
            "schedule",
            "scanned_by",
        )
        .all()
        .order_by("-created_at")
    )

    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="laundry_logs_{_local_today().isoformat()}.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "event_id",
            "event_type",
            "event_created_at",
            "student_id",
            "student_roll_no",
            "student_name",
            "student_block",
            "student_room_no",
            "schedule_day",
            "schedule_submission_status",
            "schedule_collection_status",
            "schedule_last_submission_at",
            "schedule_due_collection_by",
            "schedule_qr_token",
            "scanned_by_username",
            "scanned_by_email",
            "scanned_by_role",
        ]
    )

    for item in logs:
        student = item.student
        schedule = item.schedule
        scanned_by = item.scanned_by
        writer.writerow(
            [
                item.id,
                item.event_type,
                timezone.localtime(item.created_at).isoformat() if item.created_at else "",
                student.id if student else "",
                student.roll_no if student else "",
                student.name if student else "",
                student.block.block_name if student and student.block else "",
                student.room_no if student else "",
                schedule.get_day_of_week_display() if schedule else "",
                schedule.submission_status if schedule else "",
                schedule.collection_status if schedule else "",
                timezone.localtime(schedule.last_submission_at).isoformat() if schedule and schedule.last_submission_at else "",
                timezone.localtime(schedule.due_collection_by).isoformat() if schedule and schedule.due_collection_by else "",
                schedule.qr_token if schedule else "",
                scanned_by.username if scanned_by else "",
                scanned_by.email if scanned_by else "",
                scanned_by.role if scanned_by else "",
            ]
        )

    return response


@login_required
def download_laundry_schedule_csv(request: HttpRequest) -> HttpResponse:
    if not _is_admin(request.user):
        messages.error(request, "Only admin can download laundry schedules.")
        return redirect("dashboard-router")

    schedules = (
        LaundrySchedule.objects.select_related("student", "student__block", "student__user")
        .all()
        .order_by("day_of_week", "student__roll_no")
    )

    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="laundry_day_wise_schedule_{_local_today().isoformat()}.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "schedule_id",
            "day_code",
            "day_label",
            "student_id",
            "student_roll_no",
            "student_name",
            "student_block",
            "student_room_no",
            "student_email",
            "submission_status",
            "collection_status",
            "last_submission_at",
            "due_collection_by",
            "holidays",
            "qr_token",
        ]
    )

    for item in schedules:
        student = item.student
        student_user = student.user if student else None
        writer.writerow(
            [
                item.id,
                item.day_of_week,
                item.get_day_of_week_display(),
                student.id if student else "",
                student.roll_no if student else "",
                student.name if student else "",
                student.block.block_name if student and student.block else "",
                student.room_no if student else "",
                student_user.email if student_user else "",
                item.submission_status,
                item.collection_status,
                timezone.localtime(item.last_submission_at).isoformat() if item.last_submission_at else "",
                timezone.localtime(item.due_collection_by).isoformat() if item.due_collection_by else "",
                json.dumps(item.holidays or []),
                item.qr_token,
            ]
        )

    return response
