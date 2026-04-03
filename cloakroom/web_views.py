import json

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Q
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone

from students.models import Student
from students.utils import resolve_student_for_user

from .models import CloakroomEntry
from .views import _parse_student_qr, _resolve_student_from_payload


def _append_note(existing: str, extra: str) -> str:
    left = (existing or "").strip()
    right = (extra or "").strip()
    if not right:
        return left
    if not left:
        return right
    return f"{left}\n{right}"


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
            item_name = (request.POST.get("item_name") or "").strip()
            storage_room_no = (request.POST.get("storage_room_no") or "").strip().upper()
            notes = (request.POST.get("notes") or "").strip()

            if not qr_text or not item_name or not storage_room_no:
                messages.error(request, "QR text, item name, and storage room are required.")
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

            last_token = CloakroomEntry.objects.order_by("-token_no").values_list("token_no", flat=True).first() or 1000
            entry = CloakroomEntry.objects.create(
                student=target_student,
                token_no=last_token + 1,
                item_name=item_name,
                storage_room_no=storage_room_no,
                notes=notes,
                status=CloakroomEntry.Status.SUBMITTED,
                submitted_by=request.user,
            )
            messages.success(request, f"Item submitted. Token #{entry.token_no}.")
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

            entry = None
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
                    entry = pending.filter(token_no=token_no).first()
                    if not entry:
                        messages.error(request, "No pending token found for this student.")
                        return redirect("cloakroom-portal")
                else:
                    count = pending.count()
                    if count == 0:
                        messages.error(request, "No pending cloak room item found for this student.")
                        return redirect("cloakroom-portal")
                    if count > 1:
                        tokens = ", ".join(str(token) for token in pending.values_list("token_no", flat=True)[:10])
                        messages.error(request, f"Multiple pending tokens: {tokens}. Please enter token no.")
                        return redirect("cloakroom-portal")
                    entry = pending.first()
            else:
                entry = CloakroomEntry.objects.filter(token_no=token_no).first()
                if not entry:
                    messages.error(request, "Token not found.")
                    return redirect("cloakroom-portal")

            if entry.status == CloakroomEntry.Status.RETURNED:
                messages.info(request, "This token is already marked as returned.")
                return redirect("cloakroom-portal")

            entry.status = CloakroomEntry.Status.RETURNED
            entry.returned_by = request.user
            entry.returned_at = timezone.now()
            if return_notes:
                entry.notes = _append_note(entry.notes, f"Return note: {return_notes}")
            entry.save(update_fields=["status", "returned_by", "returned_at", "notes"])
            messages.success(request, f"Token #{entry.token_no} marked as collected.")
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

            queryset = CloakroomEntry.objects.filter(status=CloakroomEntry.Status.SUBMITTED)
            if token_start is not None and token_end is not None:
                queryset = queryset.filter(token_no__gte=token_start, token_no__lte=token_end)
            if block_name:
                queryset = queryset.filter(student__block__block_name__iexact=block_name)
            if room_no:
                queryset = queryset.filter(student__room_no__iexact=room_no)

            entries = list(queryset.select_related("student", "student__block")[:500])
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

    if student:
        entries = list(CloakroomEntry.objects.filter(student=student)[:40])
    elif can_manage:
        entries = list(CloakroomEntry.objects.select_related("student", "student__block")[:80])
    else:
        entries = []

    return render(
        request,
        "cloakroom/portal.html",
        {
            "student": student,
            "cloakroom_unlocked": cloakroom_unlocked,
            "entries": entries,
            "can_manage_cloakroom": can_manage,
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
