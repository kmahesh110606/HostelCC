import csv
import re

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import HttpResponse
from django.shortcuts import redirect, render

from students.models import Student

from .models import DisciplineCase
from .policies import VIOLATION_POLICIES, action_for_occurrence


DISCIPLINE_ALLOWED_ROLES = {"WARDEN", "SUPERVISOR", "ADMIN", "DIRECTOR"}


def _can_access(user) -> bool:
    return bool(user.is_authenticated and user.role in DISCIPLINE_ALLOWED_ROLES)


def _room_sort_key(room_no: str):
    value = (room_no or "").strip().upper()
    digits = re.findall(r"\d+", value)
    if not digits:
        return (1, value)
    return (0, int("".join(digits)), value)


def _base_students_queryset(block_filter: str = ""):
    queryset = Student.objects.select_related("block", "user", "mess_caterer")
    if block_filter:
        queryset = queryset.filter(block__block_name__iexact=block_filter)
    students = list(queryset)
    students.sort(key=lambda item: ((item.block.block_name if item.block else ""), _room_sort_key(item.room_no), item.roll_no))
    return students


@login_required
def export_student_master_csv(request):
    if not _can_access(request.user):
        messages.error(request, "Only wardens, supervisors, admins, and directors can export discipline data.")
        return redirect("dashboard-router")

    block_filter = (request.GET.get("block") or "").strip().upper()
    only_active = (request.GET.get("only_active") or "").strip().lower() == "true"

    students = _base_students_queryset(block_filter=block_filter)

    if only_active:
        active_student_ids = set(
            DisciplineCase.objects.filter(id_card_confiscated=True, id_card_returned_at__isnull=True).values_list(
                "student_id", flat=True
            )
        )
        students = [student for student in students if student.id in active_student_ids]

    response = HttpResponse(content_type="text/csv")
    filename = "students_master"
    if block_filter:
        filename += f"_{block_filter}"
    if only_active:
        filename += "_active_confiscation"
    response["Content-Disposition"] = f'attachment; filename="{filename}.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "block",
            "room_no",
            "roll_no",
            "student_name",
            "email",
            "phone_country_code",
            "phone_number",
            "mess_allotment",
            "mess_caterer",
            "discipline_total_cases",
            "discipline_active_confiscation",
            "latest_violation",
            "latest_action",
            "latest_case_created_at",
        ]
    )

    for student in students:
        student_cases = list(
            DisciplineCase.objects.filter(student=student)
            .order_by("-created_at")
            .only(
                "violation_code",
                "action_taken",
                "created_at",
                "id_card_confiscated",
                "id_card_returned_at",
            )
        )
        latest_case = student_cases[0] if student_cases else None
        active_confiscation = any(
            case.id_card_confiscated and case.id_card_returned_at is None for case in student_cases
        )

        writer.writerow(
            [
                student.block.block_name if student.block else "",
                student.room_no,
                student.roll_no,
                student.name,
                student.user.email if student.user else "",
                student.user.phone_country_code if student.user else "",
                student.user.phone_number if student.user else "",
                student.mess_allotment,
                student.mess_caterer.name if student.mess_caterer else "",
                len(student_cases),
                "YES" if active_confiscation else "NO",
                latest_case.get_violation_code_display() if latest_case else "",
                latest_case.action_taken if latest_case else "",
                latest_case.created_at.isoformat() if latest_case and latest_case.created_at else "",
            ]
        )

    return response


@login_required
def export_discipline_cases_csv(request):
    if not _can_access(request.user):
        messages.error(request, "Only wardens, supervisors, admins, and directors can export discipline data.")
        return redirect("dashboard-router")

    block_filter = (request.GET.get("block") or "").strip().upper()
    reg_no = (request.GET.get("reg_no") or "").strip().upper()

    cases = list(
        DisciplineCase.objects.select_related("student", "student__block", "created_by", "returned_by")
        .filter(
            **({"student__block__block_name__iexact": block_filter} if block_filter else {}),
            **({"student__roll_no__iexact": reg_no} if reg_no else {}),
        )
    )
    cases.sort(
        key=lambda item: (
            (item.student.block.block_name if item.student and item.student.block else ""),
            _room_sort_key(item.student.room_no if item.student else ""),
            item.student.roll_no if item.student else "",
            item.created_at,
        )
    )

    response = HttpResponse(content_type="text/csv")
    filename = "discipline_cases"
    if block_filter:
        filename += f"_{block_filter}"
    if reg_no:
        filename += f"_{reg_no}"
    response["Content-Disposition"] = f'attachment; filename="{filename}.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "block",
            "room_no",
            "roll_no",
            "student_name",
            "violation_code",
            "violation_title",
            "occurrence_number",
            "action_taken",
            "notes",
            "id_card_confiscated_at",
            "id_card_returned_at",
            "return_notes",
            "created_by",
            "returned_by",
            "created_at",
            "updated_at",
        ]
    )

    for case in cases:
        student = case.student
        writer.writerow(
            [
                student.block.block_name if student and student.block else "",
                student.room_no if student else "",
                student.roll_no if student else "",
                student.name if student else "",
                case.violation_code,
                case.get_violation_code_display(),
                case.occurrence_number,
                case.action_taken,
                case.notes,
                case.id_card_confiscated_at.isoformat() if case.id_card_confiscated_at else "",
                case.id_card_returned_at.isoformat() if case.id_card_returned_at else "",
                case.return_notes,
                case.created_by.get_full_name().strip() or case.created_by.username if case.created_by else "",
                case.returned_by.get_full_name().strip() or case.returned_by.username if case.returned_by else "",
                case.created_at.isoformat() if case.created_at else "",
                case.updated_at.isoformat() if case.updated_at else "",
            ]
        )

    return response


@login_required
def discipline_portal(request):
    if not _can_access(request.user):
        messages.error(request, "Only wardens, supervisors, admins, and directors can access discipline.")
        return redirect("dashboard-router")

    reg_no = (request.GET.get("reg_no") or request.POST.get("reg_no") or "").strip().upper()
    student_name = (request.GET.get("student_name") or request.POST.get("student_name") or "").strip()
    student = None
    matched_students = []
    history = []
    active_confiscation = None

    if reg_no:
        student = Student.objects.select_related("block").filter(roll_no__iexact=reg_no).first()
    elif student_name:
        matched_students = list(
            Student.objects.select_related("block")
            .filter(name__icontains=student_name)
            .order_by("name", "roll_no")[:50]
        )
        if len(matched_students) == 1:
            student = matched_students[0]

    if student:
        history = list(
            DisciplineCase.objects.select_related("created_by", "returned_by")
            .filter(student=student)
            .order_by("-created_at")
        )
        active_confiscation = next((item for item in history if item.is_id_card_active_confiscation), None)

    if request.method == "POST":
        action = (request.POST.get("action") or "").strip()

        if action == "confiscate":
            violation_code = (request.POST.get("violation_code") or "").strip().upper()
            notes = (request.POST.get("notes") or "").strip()

            if not student:
                messages.error(request, "Student not found for this registration number.")
                return redirect(f"{request.path}?reg_no={reg_no}&student_name={student_name}")

            policy_codes = {item["code"] for item in VIOLATION_POLICIES}
            if violation_code not in policy_codes:
                messages.error(request, "Please select a valid violation.")
                return redirect(f"{request.path}?reg_no={reg_no}&student_name={student_name}")

            occurrence_number = (
                DisciplineCase.objects.filter(student=student, violation_code=violation_code).count() + 1
            )
            action_taken = action_for_occurrence(violation_code, occurrence_number)

            DisciplineCase.objects.create(
                student=student,
                violation_code=violation_code,
                occurrence_number=occurrence_number,
                action_taken=action_taken,
                notes=notes,
                created_by=request.user,
                id_card_confiscated=True,
            )
            messages.success(request, "ID card confiscation record created.")
            return redirect(f"{request.path}?reg_no={reg_no}&student_name={student_name}")

        if action == "return_id":
            case_id = (request.POST.get("case_id") or "").strip()
            return_notes = (request.POST.get("return_notes") or "").strip()

            case = DisciplineCase.objects.filter(id=case_id).first()
            if not case:
                messages.error(request, "Discipline record not found.")
                return redirect(f"{request.path}?reg_no={reg_no}&student_name={student_name}")
            if case.id_card_returned_at is not None:
                messages.error(request, "ID card already marked as returned.")
                return redirect(f"{request.path}?reg_no={reg_no}&student_name={student_name}")

            from django.utils import timezone

            case.id_card_returned_at = timezone.now()
            case.return_notes = return_notes
            case.returned_by = request.user
            case.save(update_fields=["id_card_returned_at", "return_notes", "returned_by", "updated_at"])
            messages.success(request, "ID card marked as returned.")
            return redirect(f"{request.path}?reg_no={reg_no}&student_name={student_name}")

    return render(
        request,
        "discipline/portal.html",
        {
            "reg_no": reg_no,
            "student_name": student_name,
            "student": student,
            "matched_students": matched_students,
            "history": history,
            "active_confiscation": active_confiscation,
            "violation_policies": VIOLATION_POLICIES,
        },
    )
