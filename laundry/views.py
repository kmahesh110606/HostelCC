import json
import re
from datetime import date, timedelta

from django.core.cache import cache
from django.http import HttpResponse
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from students.models import Student
from students.utils import resolve_student_for_user
from users.permissions import IsAdmin, IsLaundryPerson

from .models import LaundryEvent, LaundryHoliday, LaundryRoomRange, LaundrySchedule
from .qr_utils import build_qr_svg
from .serializers import (
    LaundryEventSerializer,
    LaundryHolidaySerializer,
    LaundryRoomRangeSerializer,
    LaundryScheduleSerializer,
)


def _normalize_upper(value: str | None) -> str:
    return (value or "").strip().upper()


def _room_number_as_int(value: str | None):
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

    room_text = _normalize_upper(room_no)
    from_text = _normalize_upper(room_from)
    to_text = _normalize_upper(room_to)
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


def _normalize_block_name(value: str | None) -> str:
        normalized = re.sub(r"[^A-Z0-9]", "", (value or "").strip().upper())
        return normalized


def _parse_tag_token_text(raw: str | None):
        text = (raw or "").strip().upper()
        if not text:
                return None
        match = re.fullmatch(r"CDLS-([A-Z0-9]+)-(\d{4})", text)
        if not match:
                return None
        block_name = match.group(1)
        token_no = int(match.group(2))
        if token_no < 1000 or token_no > 2000:
                return None
        return {
                "token_code": f"CDLS-{block_name}-{token_no:04d}",
                "block_name": block_name,
                "token_no": token_no,
        }


def _build_tags_printable_html(block_name: str, token_start: int, token_end: int) -> str:
        cards = []
        for token_no in range(token_start, token_end + 1):
                token_code = f"CDLS-{block_name}-{token_no:04d}"
                qr_svg = build_qr_svg(token_code, box_size=6, border=2)
                if not qr_svg:
                        continue
                cards.append(
                        """
                        <div class=\"card\">
                            <div class=\"qr\">{qr}</div>
                            <div class=\"token\">{token}</div>
                        </div>
                        """.format(
                                qr=qr_svg,
                                token=token_code,
                        )
                )

        cards_html = "\n".join(cards)
        return f"""<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
    <title>Laundry Token Tags - {block_name}</title>
    <style>
        @page {{ size: A4; margin: 10mm; }}
        * {{ box-sizing: border-box; }}
        body {{ font-family: Arial, sans-serif; margin: 0; color: #111; }}
        .header {{ margin-bottom: 8px; }}
        .title {{ font-size: 18px; font-weight: 700; }}
        .subtitle {{ font-size: 12px; color: #444; margin-top: 3px; }}
        .grid {{
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 8px;
        }}
        .card {{
            border: 1px solid #222;
            border-radius: 8px;
            padding: 8px;
            min-height: 170px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            page-break-inside: avoid;
        }}
        .qr svg {{ width: 112px; height: 112px; }}
        .token {{
            margin-top: 8px;
            font-size: 12px;
            font-weight: 700;
            text-align: center;
            word-break: break-word;
        }}
    </style>
</head>
<body>
    <div class=\"header\">
        <div class=\"title\">Laundry Bag QR Tags</div>
        <div class=\"subtitle\">Block: {block_name} | Tokens: {token_start:04d}-{token_end:04d}</div>
    </div>
    <div class=\"grid\">{cards_html}</div>
</body>
</html>
"""


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
        key=lambda rule: (
            rule.scheduled_date < timezone.localdate(),
            rule.scheduled_date,
        ),
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


def _get_or_create_schedule_for_student(student):
    if not student:
        return None

    schedule = (
        LaundrySchedule.objects.select_related("student", "student__block", "student__user")
        .filter(student=student)
        .first()
    )
    if schedule:
        return schedule

    # Try to infer day from room ranges; fallback to MON if no room ranges match
    inferred_day = _infer_student_day_from_room_ranges(student)
    if not inferred_day:
        inferred_day = LaundrySchedule.DayChoices.MON

    schedule, _ = LaundrySchedule.objects.get_or_create(
        student=student,
        defaults={"day_of_week": inferred_day},
    )
    return (
        LaundrySchedule.objects.select_related("student", "student__block", "student__user")
        .filter(id=schedule.id)
        .first()
    )


def _today_day_code() -> str:
    day_map = {
        0: LaundrySchedule.DayChoices.MON,
        1: LaundrySchedule.DayChoices.TUE,
        2: LaundrySchedule.DayChoices.WED,
        3: LaundrySchedule.DayChoices.THU,
        4: LaundrySchedule.DayChoices.FRI,
        5: LaundrySchedule.DayChoices.SAT,
        6: LaundrySchedule.DayChoices.SUN,
    }
    return day_map[timezone.localdate().weekday()]


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


def _parse_qr_text_payload(qr_text: str) -> dict[str, str] | None:
    text = (qr_text or "").strip()
    if not text:
        return None

    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = None

    if isinstance(payload, dict):
        parsed: dict[str, str] = {}
        for key in ("student_id", "qr_token", "roll_no", "email", "room_no", "block_name"):
            value = payload.get(key)
            if value is not None and str(value).strip():
                parsed[key] = str(value).strip()

        for key, aliases in {
            "roll_no": ("reg_no", "regno", "registration_no"),
            "email": ("mail",),
            "room_no": ("room",),
            "block_name": ("block",),
        }.items():
            if key in parsed:
                continue
            for alias in aliases:
                value = payload.get(alias)
                if value is not None and str(value).strip():
                    parsed[key] = str(value).strip()
                    break

        return parsed or None

    parts = [part.strip() for part in text.split("|")]
    if len(parts) == 4:
        roll_no, email, room_no, block_name = parts
        return {
            "roll_no": roll_no,
            "email": email,
            "room_no": room_no,
            "block_name": block_name,
        }
    if len(parts) == 2 and parts[0].isdigit():
        return {"student_id": parts[0], "qr_token": parts[1]}
    return None


def _is_submission_allowed_for_today(schedule: LaundrySchedule) -> tuple[bool, str]:
    today_code = _today_day_code()
    today_date = timezone.localdate()
    student = schedule.student
    student_room = _normalize_upper(student.room_no)
    student_block = _normalize_upper(student.block.block_name if student.block else "")

    if student_block:
        block_rules_qs = LaundryRoomRange.objects.filter(is_active=True, block_name__iexact=student_block)
        if block_rules_qs.exists():
            today_rules = _matching_room_rules_for_date(student_block, today_date)
            if not today_rules:
                return (
                    False,
                    (
                        "Submission not allowed. No laundry slot is configured for "
                        f"block {student_block} on {today_date.isoformat()}."
                    ),
                )
            for rule in today_rules:
                if _room_in_rule(student_room, rule.room_from, rule.room_to):
                    return True, ""
            return (
                False,
                (
                    "Submission not allowed for room "
                    f"{student.room_no} in block {student_block} on {today_date.isoformat()}."
                ),
            )

    if schedule.day_of_week != today_code:
        return False, f"Submission not allowed. Your day is {schedule.day_of_week}, today is {today_code}."

    return True, ""


class LaundryScheduleViewSet(viewsets.ModelViewSet):
    queryset = LaundrySchedule.objects.select_related("student", "student__block", "student__user").all()
    serializer_class = LaundryScheduleSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        if user.is_authenticated and user.role == "STUDENT":
            student = resolve_student_for_user(user)
            if not student:
                return queryset.none()
            _get_or_create_schedule_for_student(student)
            return queryset.filter(student_id=student.id)
        return queryset

    def get_permissions(self):
        if self.action in [
            "create",
            "update",
            "partial_update",
            "destroy",
            "mark_submission",
            "mark_collection",
            "scan_qr_payload",
            "export_token_tags",
        ]:
            permission_classes = [IsLaundryPerson]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    @action(detail=False, methods=["get"], url_path=r"qr/(?P<student_id>[^/.]+)")
    def qr_for_student(self, request, student_id=None):
        schedule = self.get_queryset().filter(student_id=student_id).first()
        if not schedule:
            student = Student.objects.select_related("block", "user").filter(id=student_id).first()
            schedule = _get_or_create_schedule_for_student(student)
        if not schedule:
            return Response({"detail": "Laundry schedule not found for student."}, status=status.HTTP_404_NOT_FOUND)

        allowed_roles = {"STUDENT", "LAUNDRY_PERSON", "LAUNDRY_MANAGER", "ADMIN"}
        if request.user.role not in allowed_roles:
            return Response({"detail": "Not allowed to view student QR data."}, status=status.HTTP_403_FORBIDDEN)
        if request.user.role == "STUDENT":
            student = resolve_student_for_user(request.user)
            if not student or student.id != schedule.student_id:
                return Response({"detail": "You can only access your own QR."}, status=status.HTTP_403_FORBIDDEN)

        cache_key = f"laundry_qr_{schedule.student_id}_{schedule.qr_token}"
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)

        block_name = schedule.student.block.block_name if schedule.student.block else ""
        student_email = (
            (schedule.student.user.email if schedule.student.user else "")
            or (schedule.student.user.username if schedule.student.user else "")
            or ""
        )

        qr_payload = {
            "student_id": schedule.student_id,
            "qr_token": str(schedule.qr_token),
            "roll_no": schedule.student.roll_no,
            "email": student_email.strip().lower(),
            "room_no": schedule.student.room_no,
            "block_name": block_name,
        }

        payload = {
            "student_id": schedule.student_id,
            "qr_token": str(schedule.qr_token),
            "day_of_week": schedule.day_of_week,
            "roll_no": schedule.student.roll_no,
            "room_no": schedule.student.room_no,
            "block_name": block_name,
            "qr_text": json.dumps(qr_payload, separators=(",", ":")),
        }
        cache.set(cache_key, payload, timeout=300)
        return Response(payload)

    @action(detail=True, methods=["post"], url_path="submission")
    def mark_submission(self, request, pk=None):
        schedule = self.get_object()
        try:
            schedule.mark_submission()
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        LaundryEvent.objects.create(
            student=schedule.student,
            schedule=schedule,
            event_type=LaundryEvent.EventType.SUBMISSION,
            scanned_by=request.user,
        )
        return Response({"status": "submission_marked", "color": "orange"})

    @action(detail=True, methods=["post"], url_path="collection")
    def mark_collection(self, request, pk=None):
        schedule = self.get_object()
        try:
            schedule.mark_collection()
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        LaundryEvent.objects.create(
            student=schedule.student,
            schedule=schedule,
            event_type=LaundryEvent.EventType.COLLECTION,
            scanned_by=request.user,
        )
        return Response({"status": "collection_marked", "color": "green"})

    @action(detail=False, methods=["post"], url_path="scan")
    def scan_qr_payload(self, request):
        """
        Scan QR and process laundry event. Accepts two formats:
        1. Token-based (legacy): student_id + qr_token
        2. Text payload (new): JSON payload or "regno|mail|room|block"

        For submission, managers should pass both student qr_text and tag token text as token_qr_text.
        """
        qr_text = (request.data.get("qr_text") or "").strip()
        token_qr_text = (request.data.get("token_qr_text") or "").strip()
        student_id = request.data.get("student_id")
        qr_token = (request.data.get("qr_token") or "").strip()
        event_type = (request.data.get("event_type") or LaundryEvent.EventType.SUBMISSION).strip().upper()

        if event_type not in {
            LaundryEvent.EventType.SUBMISSION,
            LaundryEvent.EventType.COMPLETE,
            LaundryEvent.EventType.COLLECTION,
        }:
            return Response(
                {"detail": f"Unknown event type: {event_type}", "color": "red"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if event_type == LaundryEvent.EventType.COMPLETE:
            parsed_token = _parse_tag_token_text(token_qr_text or qr_text)
            if not parsed_token:
                return Response(
                    {
                        "detail": "Invalid laundry tag token. Expected format CDLS-<BLOCK>-<1000-2000>.",
                        "color": "red",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            schedule = (
                LaundrySchedule.objects.select_related("student", "student__block", "student__user")
                .filter(submission_status=True, assigned_token_code=parsed_token["token_code"])
                .first()
            )
            if not schedule:
                return Response(
                    {"detail": "This token is not mapped to an active laundry submission.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if schedule.laundry_done_at:
                return Response(
                    {"detail": "Laundry already marked as done for this token.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            schedule.mark_done()
            LaundryEvent.objects.create(
                student=schedule.student,
                schedule=schedule,
                event_type=LaundryEvent.EventType.COMPLETE,
                scanned_by=request.user,
            )

            return Response(
                {
                    "status": "ok",
                    "message": "Laundry marked ready for collection.",
                    "event_type": LaundryEvent.EventType.COMPLETE,
                    "color": "green",
                    "student_id": schedule.student_id,
                    "schedule_id": schedule.id,
                    "student_name": schedule.student.name,
                    "student_roll_no": schedule.student.roll_no,
                    "room_no": schedule.student.room_no,
                    "block_name": schedule.student.block.block_name if schedule.student.block else "",
                    "assigned_token_code": schedule.assigned_token_code,
                }
            )

        parsed_qr = None
        if qr_text and event_type != LaundryEvent.EventType.COMPLETE:
            parsed_qr = _parse_qr_text_payload(qr_text)
            if not parsed_qr:
                return Response(
                    {
                        "detail": (
                            "Invalid qr_text payload. Use JSON with student_id/qr_token or roll_no/email/room_no/block_name, "
                            "or pipe format regno|mail|room|block."
                        ),
                        "color": "red",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if parsed_qr.get("student_id") and not student_id:
                student_id = parsed_qr["student_id"]
            if parsed_qr.get("qr_token") and not qr_token:
                qr_token = parsed_qr["qr_token"]

        if student_id is not None:
            student_id = str(student_id).strip()

        schedule = None
        if student_id and qr_token:
            schedule = (
                LaundrySchedule.objects.select_related("student", "student__block", "student__user")
                .filter(student_id=student_id)
                .first()
            )
            if not schedule:
                student = Student.objects.select_related("block", "user").filter(id=student_id).first()
                schedule = _get_or_create_schedule_for_student(student)
            if not schedule:
                return Response(
                    {"detail": "Laundry schedule not found for student.", "color": "red"},
                    status=status.HTTP_404_NOT_FOUND,
                )
            if str(schedule.qr_token).strip() != qr_token:
                return Response(
                    {"detail": "Invalid QR token.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        else:
            parsed_qr = parsed_qr or {}
            roll_no = (parsed_qr.get("roll_no") or "").strip()
            if not roll_no:
                return Response(
                    {"detail": "Either qr_text or (student_id + qr_token) is required.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            student = Student.objects.select_related("block", "user").filter(roll_no=roll_no).first()
            if not student:
                return Response(
                    {"detail": f"Student {roll_no} not found.", "color": "red"},
                    status=status.HTTP_404_NOT_FOUND,
                )

            qr_room = _normalize_upper(parsed_qr.get("room_no"))
            student_room = _normalize_upper(student.room_no)
            if qr_room and qr_room != student_room:
                return Response(
                    {"detail": f"Room mismatch. Expected {student.room_no}, got {qr_room}.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            qr_block = _normalize_upper(parsed_qr.get("block_name"))
            student_block = _normalize_upper(student.block.block_name if student.block else "")
            if qr_block and qr_block != student_block:
                return Response(
                    {"detail": f"Block mismatch. Expected {student_block}, got {qr_block}.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            qr_email = (parsed_qr.get("email") or "").strip().lower()
            student_email = ((student.user.email if student.user else "") or "").strip().lower()
            if qr_email and student_email and qr_email != student_email:
                return Response(
                    {"detail": "Email mismatch in QR payload.", "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            schedule = (
                LaundrySchedule.objects.select_related("student", "student__block", "student__user")
                .filter(student=student)
                .first()
            )
            if not schedule:
                schedule = _get_or_create_schedule_for_student(student)

        if not schedule:
            return Response(
                {"detail": "Laundry schedule not found.", "color": "red"},
                status=status.HTTP_404_NOT_FOUND,
            )

        if event_type == LaundryEvent.EventType.SUBMISSION:
            is_allowed, reason = _is_submission_allowed_for_today(schedule)
            if not is_allowed:
                return Response(
                    {
                        "detail": reason,
                        "color": "red",
                        "student_id": schedule.student_id,
                        "schedule_id": schedule.id,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if schedule.submission_status and not schedule.collection_status:
                return Response(
                    {
                        "detail": "Previous laundry not yet collected. Please collect before submitting new laundry.",
                        "color": "red",
                        "student_id": schedule.student_id,
                        "schedule_id": schedule.id,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            
            try:
                parsed_token = _parse_tag_token_text(token_qr_text)
                if not parsed_token:
                    return Response(
                        {
                            "detail": "Token tag QR is required for submission and must match CDLS-<BLOCK>-<1000-2000>.",
                            "color": "red",
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                student_block = _normalize_block_name(schedule.student.block.block_name if schedule.student.block else "")
                if student_block and parsed_token["block_name"] != student_block:
                    return Response(
                        {
                            "detail": f"Token block mismatch. Expected {student_block}, got {parsed_token['block_name']}.",
                            "color": "red",
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                token_in_use = (
                    LaundrySchedule.objects.filter(
                        submission_status=True,
                        assigned_token_code=parsed_token["token_code"],
                    )
                    .exclude(id=schedule.id)
                    .exists()
                )
                if token_in_use:
                    return Response(
                        {"detail": "Token is already assigned to another active laundry bag.", "color": "red"},
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                schedule.mark_submission()
                schedule.assigned_token_code = parsed_token["token_code"]
                schedule.token_assigned_at = timezone.now()
                schedule.save(update_fields=["assigned_token_code", "token_assigned_at"])
                action = LaundryEvent.EventType.SUBMISSION
                color = "orange"
                result_msg = "Laundry submission registered."
            except ValueError as exc:
                return Response(
                    {"detail": str(exc), "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        elif event_type == LaundryEvent.EventType.COLLECTION:
            if not schedule.submission_status:
                return Response(
                    {
                        "detail": "No pending laundry to collect.",
                        "color": "red",
                        "student_id": schedule.student_id,
                        "schedule_id": schedule.id,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if not schedule.laundry_done_at:
                return Response(
                    {
                        "detail": "Laundry is not marked done yet. Scan token at completion first.",
                        "color": "red",
                        "student_id": schedule.student_id,
                        "schedule_id": schedule.id,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            
            try:
                token_before_collection = schedule.assigned_token_code
                schedule.mark_collection()
                action = LaundryEvent.EventType.COLLECTION
                color = "green"
                result_msg = "Laundry collection registered."
            except ValueError as exc:
                return Response(
                    {"detail": str(exc), "color": "red"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        LaundryEvent.objects.create(
            student=schedule.student,
            schedule=schedule,
            event_type=action,
            scanned_by=request.user,
        )

        return Response(
            {
                "status": "ok",
                "message": result_msg,
                "event_type": action,
                "color": color,
                "student_id": schedule.student_id,
                "schedule_id": schedule.id,
                "student_name": schedule.student.name,
                "student_roll_no": schedule.student.roll_no,
                "room_no": schedule.student.room_no,
                "block_name": schedule.student.block.block_name if schedule.student.block else "",
                "assigned_token_code": token_before_collection if event_type == LaundryEvent.EventType.COLLECTION else schedule.assigned_token_code,
            }
        )

    @action(detail=False, methods=["get"], url_path="export-token-tags")
    def export_token_tags(self, request):
        block_name = _normalize_block_name(request.query_params.get("block_name"))
        token_start_raw = (request.query_params.get("start") or "1000").strip()
        token_end_raw = (request.query_params.get("end") or "2000").strip()

        if not block_name:
            return Response(
                {"detail": "block_name is required.", "color": "red"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            token_start = int(token_start_raw)
            token_end = int(token_end_raw)
        except ValueError:
            return Response(
                {"detail": "start and end must be integers.", "color": "red"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if token_start < 1000 or token_end > 2000 or token_start > token_end:
            return Response(
                {
                    "detail": "Token range must be within 1000-2000 and start must be <= end.",
                    "color": "red",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        html = _build_tags_printable_html(block_name, token_start, token_end)
        response = HttpResponse(html, content_type="text/html; charset=utf-8")
        response["Content-Disposition"] = (
            f'attachment; filename="laundry-tags-{block_name}-{token_start:04d}-{token_end:04d}.html"'
        )
        return response


class LaundryEventViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = LaundryEvent.objects.select_related("student", "schedule", "scanned_by").all()
    serializer_class = LaundryEventSerializer
    permission_classes = [IsAdmin]


class LaundryRoomRangeViewSet(viewsets.ModelViewSet):
    queryset = LaundryRoomRange.objects.all()
    serializer_class = LaundryRoomRangeSerializer

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            permission_classes = [IsLaundryPerson]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]


class LaundryHolidayViewSet(viewsets.ModelViewSet):
    queryset = LaundryHoliday.objects.all().order_by("holiday_date")
    serializer_class = LaundryHolidaySerializer

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            permission_classes = [IsLaundryPerson]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]
