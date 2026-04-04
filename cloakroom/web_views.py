import json
import logging

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db import DatabaseError, transaction
from django.db.models import Max, Q
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone
from django.views.decorators.http import require_http_methods

from hostels.models import HostelBlock
from laundry.models import LaundrySchedule
from students.models import Student
from students.utils import resolve_student_for_user

from .models import CloakroomEntry, CloakroomRoom
from .views import _parse_student_qr, _resolve_student_from_payload


logger = logging.getLogger(__name__)


REQUIRED_CLOAKROOM_ITEMS = (
    ("CHAIR", "Chair"),
    ("BUCKET", "Bucket"),
    ("CARTON", "Carton"),
    ("SUITCASE", "Suitcase"),
    ("MATTRESS", "Mattress"),
)

_ITEM_CODE_TO_LABEL = {code: label for code, label in REQUIRED_CLOAKROOM_ITEMS}

_ITEM_ALIASES = {
    "chair": "CHAIR",
    "bucket": "BUCKET",
    "carton": "CARTON",
    "cartonbox": "CARTON",
    "box": "CARTON",
    "suitcase": "SUITCASE",
    "bag": "SUITCASE",
    "bags": "SUITCASE",
    "bagssuitcase": "SUITCASE",
    "mattress": "MATTRESS",
    "matress": "MATTRESS",
}


def _append_note(existing: str, extra: str) -> str:
    left = (existing or "").strip()
    right = (extra or "").strip()
    if not right:
        return left
    if not left:
        return right
    return f"{left}\n{right}"


def _normalize_item_code(item_name: str) -> str | None:
    key = "".join(ch for ch in (item_name or "").strip().lower() if ch.isalnum())
    if not key:
        return None
    return _ITEM_ALIASES.get(key)


def _parse_storage_room_no(storage_room_no: str) -> tuple[str, str] | None:
    """Parse storage room number 'CR-D2-101' into ('D2', '101')."""
    cleaned = (storage_room_no or "").strip().upper()
    if not cleaned:
        return None

    parts = [part for part in cleaned.split("-") if part]
    if len(parts) >= 3 and parts[0] == "CR":
        return parts[1], "-".join(parts[2:])
    if len(parts) >= 2:
        return parts[0], "-".join(parts[1:])
    return None


def _next_token_no_for_item(item_code: str) -> int:
    item_label = _ITEM_CODE_TO_LABEL[item_code]
    max_token = (
        CloakroomEntry.objects.filter(item_name__iexact=item_label)
        .aggregate(max_token=Max("token_no"))
        .get("max_token")
    )
    return 1001 if max_token is None else max_token + 1


def _student_qr_payload_text(student, user) -> str:
    qr_token = ""
    try:
        schedule = LaundrySchedule.objects.only("student_id", "qr_token").filter(student_id=student.id).first()
        if schedule:
            qr_token = str(schedule.qr_token)
    except Exception:
        qr_token = ""

    return json.dumps(
        {
            "student_id": student.id,
            "qr_token": qr_token,
            "roll_no": student.roll_no,
            "email": (user.email or user.username or "").strip().lower(),
            "room_no": student.room_no,
            "block_name": student.block.block_name if student.block else "",
        },
        separators=(",", ":"),
    )


def _build_item_status_rows(entries):
    latest_by_code = {}
    for entry in entries:
        code = _normalize_item_code(entry.item_name)
        if not code:
            continue
        if code not in latest_by_code:
            latest_by_code[code] = entry

    rows = []
    for code, label in REQUIRED_CLOAKROOM_ITEMS:
        entry = latest_by_code.get(code)
        if not entry:
            rows.append(
                {
                    "label": label,
                    "status": "Not Submitted",
                    "token": "-",
                    "storage_room_no": "-",
                    "is_collected": False,
                    "is_pending": False,
                }
            )
            continue

        is_collected = entry.status == CloakroomEntry.Status.RETURNED
        rows.append(
            {
                "label": label,
                "status": "Collected" if is_collected else "Submitted",
                "token": "-" if is_collected else str(entry.token_no),
                "storage_room_no": entry.storage_room_no,
                "is_collected": is_collected,
                "is_pending": not is_collected,
            }
        )

    return rows


def _resolve_student_for_cloakroom_portal(user):
    if not user or not getattr(user, "is_authenticated", False):
        return None

    base_qs = Student.objects.select_related("block", "room").only(
        "id",
        "user_id",
        "name",
        "roll_no",
        "room_no",
        "block__id",
        "block__block_name",
        "room__id",
        "room__room_no",
    )

    try:
        direct = base_qs.filter(user=user).first()
    except Exception:
        return None

    if direct:
        return direct

    username = (user.username or "").strip()
    email = (user.email or "").strip().lower()
    email_local = email.split("@", 1)[0] if "@" in email else ""
    candidate_roll_nos = {value for value in (username, email_local) if value}
    if not candidate_roll_nos:
        return None

    lookup = Q()
    for roll_no in candidate_roll_nos:
        lookup |= Q(roll_no__iexact=roll_no)

    matches = list(base_qs.filter(lookup)[:2])
    if len(matches) != 1:
        return None

    student = matches[0]
    if student.user_id is None:
        try:
            student.user = user
            student.save(update_fields=["user"])
        except Exception:
            pass

    return student


def _can_manage_cloakroom_web(user) -> bool:
    return getattr(user, "role", "") in {"ADMIN", "SUPERVISOR", "WARDEN", "DIRECTOR", "LAUNDRY_PERSON"}


@login_required
def cloakroom_portal(request: HttpRequest) -> HttpResponse:
    student = None
    cloakroom_unlocked = False
    try:
        student = resolve_student_for_user(request.user)
        if student is not None:
            cloakroom_unlocked = bool(student.cloakroom_unlocked)
    except Exception:
        student = _resolve_student_for_cloakroom_portal(request.user)
        cloakroom_unlocked = False
    can_manage = _can_manage_cloakroom_web(request.user)

    if request.method == "POST":
        action = (request.POST.get("action") or "").strip()

        if action == "submit_item":
            if not can_manage:
                messages.error(request, "Only authorized staff can submit cloak room items.")
                return redirect("cloakroom-portal")

            qr_text = (request.POST.get("qr_text") or "").strip()
            basket_id = (request.POST.get("basket_id") or "").strip()
            item_name = (request.POST.get("item_name") or "").strip()
            storage_room_no = (request.POST.get("storage_room_no") or "").strip().upper()
            notes = (request.POST.get("notes") or "").strip()

            if not qr_text:
                messages.error(request, "QR text is required.")
                return redirect("cloakroom-portal")

            if not basket_id and not storage_room_no:
                messages.error(request, "Storage room number or basket is required.")
                return redirect("cloakroom-portal")

            parsed = _parse_student_qr(qr_text)
            if not parsed:
                messages.error(request, "Invalid student QR format.")
                return redirect("cloakroom-portal")

            target_student = _resolve_student_from_payload(parsed)
            if not target_student:
                messages.error(request, "Student could not be resolved from this QR.")
                return redirect("cloakroom-portal")
            if not target_student.cloakroom_unlocked:
                messages.error(request, "Cloak room service is locked for this student.")
                return redirect("cloakroom-portal")

            try:
                with transaction.atomic():
                    basket = None
                    if basket_id:
                        basket = (
                            CloakroomRoom.objects
                            .select_for_update()
                            .select_related("block")
                            .filter(id=basket_id, is_active=True)
                            .first()
                        )
                    if basket is None:
                        storage_parts = _parse_storage_room_no(storage_room_no)
                        if not storage_parts:
                            messages.error(request, "Use a valid storage room code like CR-D2-101.")
                            return redirect("cloakroom-portal")
                        block_name, room_no = storage_parts
                        basket = (
                            CloakroomRoom.objects
                            .select_for_update()
                            .select_related("block")
                            .filter(block__block_name__iexact=block_name, room_no__iexact=room_no, is_active=True)
                            .first()
                        )
                    if not basket:
                        messages.error(request, "Cloakroom basket not found for the selected room.")
                        return redirect("cloakroom-portal")

                    basket_item_name = (basket.item_name or "").strip()
                    if not item_name:
                        item_name = basket_item_name

                    item_code = _normalize_item_code(item_name) if item_name else None
                    if not item_code and basket_item_name:
                        item_code = _normalize_item_code(basket_item_name)
                    if not item_code:
                        allowed = ", ".join(label for _, label in REQUIRED_CLOAKROOM_ITEMS)
                        messages.error(request, f"Allowed items: {allowed}.")
                        return redirect("cloakroom-portal")

                    basket_item_code = _normalize_item_code(basket_item_name)
                    if basket_item_code and basket_item_code != item_code:
                        messages.error(request, "Selected item does not match the configured basket item.")
                        return redirect("cloakroom-portal")

                    item_label = _ITEM_CODE_TO_LABEL[item_code]
                    list(
                        CloakroomRoom.objects.select_for_update()
                        .filter(is_active=True, item_name__iexact=item_label)
                        .values_list("id", flat=True)
                    )

                    prior_item_names = list(CloakroomEntry.objects.filter(student=target_student).values_list("item_name", flat=True))
                    chair_submitted = any(_normalize_item_code(name) == "CHAIR" for name in prior_item_names)
                    if item_code != "CHAIR" and not chair_submitted:
                        messages.error(request, "Chair must be submitted first before other items.")
                        return redirect("cloakroom-portal")

                    pending_names = list(
                        CloakroomEntry.objects.filter(
                            student=target_student,
                            status=CloakroomEntry.Status.SUBMITTED,
                        ).values_list("item_name", flat=True)
                    )
                    if any(_normalize_item_code(name) == item_code for name in pending_names):
                        messages.error(request, "This item is already pending collection for this student.")
                        return redirect("cloakroom-portal")

                    basket_seq = basket.next_token_no
                    entry = CloakroomEntry.objects.create(
                        student=target_student,
                        basket_token_no=basket_seq,
                        token_no=_next_token_no_for_item(item_code),
                        item_name=item_label,
                        storage_room_no=storage_room_no or f"CR-{basket.block.block_name}-{basket.room_no}",
                        notes=notes,
                        status=CloakroomEntry.Status.SUBMITTED,
                        submitted_by=request.user,
                    )
                    basket.next_token_no = basket_seq + 1
                    if not basket.item_name.strip():
                        basket.item_name = item_label
                    basket.save(update_fields=["next_token_no", "item_name"])
            except DatabaseError:
                logger.exception("Cloakroom submit failed due to database error")
                messages.error(request, "Cloak room is temporarily unavailable. Please try again in a few minutes.")
                return redirect("cloakroom-portal")
            messages.success(request, f"Item submitted. Basket Token #{entry.basket_token_no}, Item Token #{entry.token_no}.")
            return redirect("cloakroom-portal")

        if action == "return_item":
            if not can_manage:
                messages.error(request, "Only authorized staff can mark returns.")
                return redirect("cloakroom-portal")

            raw_token = (request.POST.get("token_no") or "").strip()
            qr_text = (request.POST.get("qr_text") or "").strip()
            return_notes = (request.POST.get("return_notes") or "").strip()

            token_no = None
            if raw_token:
                if not raw_token.isdigit():
                    messages.error(request, "Please enter a valid token number.")
                    return redirect("cloakroom-portal")
                token_no = int(raw_token)

            if token_no is None and not qr_text:
                messages.error(request, "Provide token no or student QR text.")
                return redirect("cloakroom-portal")

            entries = []
            if qr_text:
                parsed = _parse_student_qr(qr_text)
                if not parsed:
                    messages.error(request, "Invalid student QR format.")
                    return redirect("cloakroom-portal")
                target_student = _resolve_student_from_payload(parsed)
                if not target_student:
                    messages.error(request, "Student could not be resolved from this QR.")
                    return redirect("cloakroom-portal")

                pending = CloakroomEntry.objects.filter(
                    student=target_student,
                    status=CloakroomEntry.Status.SUBMITTED,
                )
                if token_no is not None:
                    entries = list(pending.filter(token_no=token_no).order_by("submitted_at", "id"))
                    if not entries:
                        messages.error(request, "No pending token found for this student.")
                        return redirect("cloakroom-portal")
                else:
                    entries = list(pending.order_by("submitted_at", "id"))
                    if not entries:
                        messages.error(request, "No pending cloak room item found for this student.")
                        return redirect("cloakroom-portal")
            else:
                entries = list(
                    CloakroomEntry.objects.filter(token_no=token_no, status=CloakroomEntry.Status.SUBMITTED).order_by(
                        "submitted_at", "id"
                    )
                )
                if not entries:
                    messages.error(request, "Token not found.")
                    return redirect("cloakroom-portal")

            try:
                returned_count = 0
                first_entry = None
                for entry in entries:
                    if entry.status == CloakroomEntry.Status.RETURNED:
                        continue
                    if first_entry is None:
                        first_entry = entry
                    entry.status = CloakroomEntry.Status.RETURNED
                    entry.returned_by = request.user
                    entry.returned_at = timezone.now()
                    if return_notes:
                        entry.notes = _append_note(entry.notes, f"Return note: {return_notes}")
                    entry.save(update_fields=["status", "returned_by", "returned_at", "notes"])
                    returned_count += 1
            except DatabaseError:
                logger.exception("Cloakroom return failed due to database error")
                messages.error(request, "Cloak room is temporarily unavailable. Please try again in a few minutes.")
                return redirect("cloakroom-portal")
            if returned_count == 0:
                messages.info(request, "This token is already marked as returned.")
            elif returned_count == 1:
                messages.success(request, f"Token #{first_entry.token_no if first_entry else token_no} marked as collected.")
            else:
                messages.success(
                    request,
                    f"Token #{first_entry.token_no if first_entry else token_no} marked as collected for {returned_count} item(s).",
                )
            return redirect("cloakroom-portal")

        if action == "move_items":
            if not can_manage:
                messages.error(request, "Only authorized staff can move cloak room items.")
                return redirect("cloakroom-portal")

            target_storage = (request.POST.get("storage_room_no") or "").strip().upper()
            block_name = (request.POST.get("block_name") or "").strip()
            room_no = (request.POST.get("room_no") or "").strip()
            raw_start = (request.POST.get("token_start") or "").strip()
            raw_end = (request.POST.get("token_end") or "").strip()
            move_notes = (request.POST.get("move_notes") or "").strip()

            if not target_storage:
                messages.error(request, "Target storage room is required.")
                return redirect("cloakroom-portal")

            token_start = None
            token_end = None
            if bool(raw_start) != bool(raw_end):
                messages.error(request, "Provide both token start and token end for range moves.")
                return redirect("cloakroom-portal")
            if raw_start and raw_end:
                if not raw_start.isdigit() or not raw_end.isdigit():
                    messages.error(request, "Token range must be numeric.")
                    return redirect("cloakroom-portal")
                token_start = int(raw_start)
                token_end = int(raw_end)
                if token_start > token_end:
                    messages.error(request, "Token start must be less than or equal to token end.")
                    return redirect("cloakroom-portal")

            if token_start is None and not block_name and not room_no:
                messages.error(request, "Choose a filter: token range, block name, or room no.")
                return redirect("cloakroom-portal")

            try:
                queryset = CloakroomEntry.objects.filter(status=CloakroomEntry.Status.SUBMITTED)
                if token_start is not None and token_end is not None:
                    queryset = queryset.filter(token_no__gte=token_start, token_no__lte=token_end)
                if block_name:
                    queryset = queryset.filter(student__block__block_name__iexact=block_name)
                if room_no:
                    queryset = queryset.filter(student__room_no__iexact=room_no)

                entries = list(queryset.select_related("student", "student__block")[:500])
            except DatabaseError:
                logger.exception("Cloakroom move failed due to database error")
                messages.error(request, "Cloak room is temporarily unavailable. Please try again in a few minutes.")
                return redirect("cloakroom-portal")
            if not entries:
                messages.error(request, "No submitted items matched your move filters.")
                return redirect("cloakroom-portal")

            moved = 0
            stamp = timezone.localtime().strftime("%d %b %Y %I:%M %p")
            note_line = f"Moved to {target_storage} by {request.user.username} on {stamp}"
            if move_notes:
                note_line = f"{note_line}. Note: {move_notes}"

            for entry in entries:
                if entry.storage_room_no == target_storage and not move_notes:
                    continue
                entry.storage_room_no = target_storage
                entry.notes = _append_note(entry.notes, note_line)
                entry.save(update_fields=["storage_room_no", "notes"])
                moved += 1

            messages.success(request, f"Moved {moved} item(s) to {target_storage}.")
            return redirect("cloakroom-portal")

    try:
        if student:
            entries = list(CloakroomEntry.objects.filter(student=student)[:40])
        elif can_manage:
            entries = list(CloakroomEntry.objects.select_related("student", "student__block")[:80])
        else:
            entries = []
    except DatabaseError:
        logger.exception("Cloakroom portal list load failed due to database error")
        entries = []
        messages.error(request, "Cloak room data is temporarily unavailable. Please try again shortly.")

    student_qr_text = ""
    item_status_rows = []
    if student:
        try:
            student_qr_text = _student_qr_payload_text(student, request.user)
        except Exception:
            student_qr_text = ""
        item_status_rows = _build_item_status_rows(entries)

    # Get available cloakroom rooms and blocks for staff forms
    try:
        blocks = list(HostelBlock.objects.all().order_by("block_name")) if can_manage else []
        cloakroom_rooms = list(CloakroomRoom.objects.filter(is_active=True).select_related("block").order_by("block__block_name", "room_no")) if can_manage else []
    except DatabaseError:
        blocks = []
        cloakroom_rooms = []

    is_admin = getattr(request.user, "role", "") in {"ADMIN", "SUPERVISOR", "DIRECTOR"}

    return render(
        request,
        "cloakroom/portal.html",
        {
            "student": student,
            "cloakroom_unlocked": cloakroom_unlocked,
            "entries": entries,
            "can_manage_cloakroom": can_manage,
            "is_admin": is_admin,
            "required_item_choices": [label for _, label in REQUIRED_CLOAKROOM_ITEMS],
            "student_qr_text": student_qr_text,
            "item_status_rows": item_status_rows,
            "blocks": blocks,
            "cloakroom_rooms": cloakroom_rooms,
            "sample_qr": json.dumps(
                {
                    "roll_no": student.roll_no if student else "22BCE0001",
                    "email": request.user.email,
                    "room_no": student.room_no if student else "A-101",
                    "block_name": student.block.block_name if student and student.block else "D2",
                }
            ),
        },
    )


def _can_admin_cloakroom(user) -> bool:
    """Check if user can access cloakroom admin pages."""
    return getattr(user, "role", "") in {"ADMIN", "SUPERVISOR", "DIRECTOR"}


@login_required
@require_http_methods(["GET", "POST"])
def cloakroom_admin(request: HttpRequest) -> HttpResponse:
    """Admin page for cloakroom management: rooms and student unlock/lock."""
    if not _can_admin_cloakroom(request.user):
        messages.error(request, "You don't have permission to access cloakroom admin.")
        return redirect("cloakroom-portal")

    if request.method == "POST":
        action = (request.POST.get("action") or "").strip()

        if action == "add_room":
            block_id = request.POST.get("block_id", "").strip()
            room_no = request.POST.get("room_no", "").strip()
            item_name = request.POST.get("item_name", "").strip()

            if not block_id or not room_no or not item_name:
                messages.error(request, "Block, room number, and item name are required.")
                return redirect("cloakroom-admin")

            item_code = _normalize_item_code(item_name)
            if not item_code:
                allowed = ", ".join(label for _, label in REQUIRED_CLOAKROOM_ITEMS)
                messages.error(request, f"Allowed items: {allowed}.")
                return redirect("cloakroom-admin")

            try:
                block = HostelBlock.objects.get(id=int(block_id))
            except (HostelBlock.DoesNotExist, ValueError):
                messages.error(request, "Invalid block selected.")
                return redirect("cloakroom-admin")

            room_no = room_no.upper()
            basket, created = CloakroomRoom.objects.get_or_create(
                block=block,
                room_no=room_no,
                defaults={"item_name": _ITEM_CODE_TO_LABEL[item_code]},
            )
            updates = ["is_active"]
            if not basket.item_name.strip():
                basket.item_name = _ITEM_CODE_TO_LABEL[item_code]
                updates.append("item_name")
            elif _normalize_item_code(basket.item_name) != item_code:
                basket.item_name = _ITEM_CODE_TO_LABEL[item_code]
                updates.append("item_name")
            basket.is_active = True
            basket.save(update_fields=list(dict.fromkeys(updates)))
            if created:
                messages.success(request, f"Added cloakroom basket {basket.item_name} @ {block.block_name}-{room_no}.")
            else:
                messages.info(request, f"Reactivated cloakroom basket {basket.item_name} @ {block.block_name}-{room_no}.")
            return redirect("cloakroom-admin")

        elif action == "delete_room":
            room_id = request.POST.get("room_id", "").strip()
            try:
                room = CloakroomRoom.objects.get(id=int(room_id))
                block_name = room.block.block_name
                room_no = room.room_no
                room.is_active = False
                room.save(update_fields=["is_active"])
                messages.success(request, f"Deactivated cloakroom room {block_name}-{room_no}.")
            except (CloakroomRoom.DoesNotExist, ValueError):
                messages.error(request, "Invalid room selected.")
            return redirect("cloakroom-admin")

        elif action == "toggle_student_unlock":
            student_id = request.POST.get("student_id", "").strip()
            try:
                student = Student.objects.get(id=int(student_id))
                student.cloakroom_unlocked = not student.cloakroom_unlocked
                student.save(update_fields=["cloakroom_unlocked"])
                status = "unlocked" if student.cloakroom_unlocked else "locked"
                messages.success(request, f"Cloakroom service {status} for {student.roll_no}.")
            except (Student.DoesNotExist, ValueError):
                messages.error(request, "Invalid student selected.")
            return redirect("cloakroom-admin")

    try:
        blocks = list(HostelBlock.objects.all().order_by("block_name"))
        cloakroom_rooms = list(CloakroomRoom.objects.select_related("block").order_by("block__block_name", "room_no"))
        all_students = list(Student.objects.select_related("block").order_by("roll_no")[:500])
    except DatabaseError:
        logger.exception("Cloakroom admin load failed")
        blocks = []
        cloakroom_rooms = []
        all_students = []
        messages.error(request, "Cloakroom data is temporarily unavailable.")

    return render(
        request,
        "cloakroom/admin.html",
        {
            "blocks": blocks,
            "cloakroom_rooms": cloakroom_rooms,
            "students": all_students,
            "required_item_choices": [label for _, label in REQUIRED_CLOAKROOM_ITEMS],
        },
    )

