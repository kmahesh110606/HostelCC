import json

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render

from students.models import Student
from students.utils import resolve_student_for_user

from .models import CloakroomEntry
from .views import _parse_student_qr, _resolve_student_from_payload


def _can_manage_cloakroom_web(user) -> bool:
    return getattr(user, "role", "") in {"ADMIN", "SUPERVISOR", "WARDEN", "DIRECTOR", "LAUNDRY_PERSON"}


@login_required
def cloakroom_portal(request: HttpRequest) -> HttpResponse:
    student = resolve_student_for_user(request.user)
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
            return_notes = (request.POST.get("return_notes") or "").strip()
            if not raw_token.isdigit():
                messages.error(request, "Please enter a valid token number.")
                return redirect("cloakroom-portal")

            entry = CloakroomEntry.objects.filter(token_no=int(raw_token)).first()
            if not entry:
                messages.error(request, "Token not found.")
                return redirect("cloakroom-portal")

            if entry.status == CloakroomEntry.Status.RETURNED:
                messages.info(request, "This token is already marked as returned.")
                return redirect("cloakroom-portal")

            entry.status = CloakroomEntry.Status.RETURNED
            entry.returned_by = request.user
            from django.utils import timezone

            entry.returned_at = timezone.now()
            if return_notes:
                entry.notes = f"{entry.notes}\nReturn note: {return_notes}".strip()
            entry.save(update_fields=["status", "returned_by", "returned_at", "notes"])
            messages.success(request, f"Token #{entry.token_no} marked as returned.")
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
