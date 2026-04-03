import csv
from datetime import datetime

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Avg, Count, Q
from django.db import IntegrityError
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render

from students.models import Student
from mess.options import MESS_TYPES, canonical_mess_type

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessMenu, MessMenuArchive


MEAL_SLOTS = ["breakfast", "lunch", "snacks", "dinner"]
WEEK_DAY_ORDER = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
VEG_FALLBACK_TYPES = {"NON_VEG", "SPECIAL"}
WEEK_DAY_LABELS = {
    "MON": "Monday",
    "TUE": "Tuesday",
    "WED": "Wednesday",
    "THU": "Thursday",
    "FRI": "Friday",
    "SAT": "Saturday",
    "SUN": "Sunday",
}


def _split_items(raw: str) -> list[str]:
    return [part.strip() for part in raw.split(",") if part.strip()]


def _scoped_feedback_queryset_for_user(user):
    queryset = Feedback.objects.select_related("student", "student__block").all()
    role = getattr(user, "role", "")

    if role in {"MESS_MANAGER", "WARDEN"}:
        assigned_mess_name = (getattr(user, "assigned_mess_name", "") or "").strip()
        if not assigned_mess_name:
            return queryset.none()

        scope_pairs = list(
            Caterer.objects.filter(name__iexact=assigned_mess_name)
            .values_list("block_id", "meal_types")
            .distinct()
        )
        if not scope_pairs:
            return queryset.none()

        scope_filter = Q()
        for block_id, meal_type in scope_pairs:
            scope_filter |= Q(student__block_id=block_id, student__mess_allotment=meal_type)

        return queryset.filter(scope_filter)

    return queryset


def _parse_feedback_menu_item(menu_item: str):
    parts = [part.strip() for part in (menu_item or "").split(">") if part.strip()]
    day_code = parts[0] if len(parts) >= 1 else ""
    meal_code = parts[1] if len(parts) >= 2 else ""
    item_name = parts[2] if len(parts) >= 3 else (parts[-1] if parts else "")
    return day_code, meal_code, item_name


@login_required
def mess_portal(request: HttpRequest) -> HttpResponse:
    student = Student.objects.filter(user=request.user).first()
    month = datetime.now().strftime("%Y-%m")
    selected_mess_type = "VEG"
    if student:
        selected_mess_type = canonical_mess_type(student.mess_allotment) or "VEG"
    else:
        selected_mess_type = canonical_mess_type(request.GET.get("mess_type")) or "VEG"

    if request.method == "POST":
        action = request.POST.get("action", "")

        if action == "rate_item":
            if not student:
                messages.error(request, "Only student accounts can submit menu ratings.")
                return redirect("mess-portal")

            week_day = request.POST.get("week_day", "")
            meal_slot = request.POST.get("meal_slot", "")
            item_name = request.POST.get("item_name", "").strip()
            rating = int(request.POST.get("rating", "0") or "0")
            comment = request.POST.get("comment", "").strip()

            if rating < 1 or rating > 5:
                messages.error(request, "Please choose a rating between 1 and 5.")
                return redirect("mess-portal")

            menu_item = f"{week_day}>{meal_slot.upper()}"
            if item_name:
                menu_item = f"{menu_item}>{item_name}"

            try:
                Feedback.objects.create(
                    student=student,
                    menu_item=menu_item,
                    rating=rating,
                    comment=comment,
                    month=month,
                )
                messages.success(request, "Rating submitted.")
            except IntegrityError:
                messages.warning(request, "You have already rated this menu item this month. Your previous rating was not updated.")
            return redirect("mess-portal")

        if action == "create_poll":
            if request.user.role not in {"ADMIN", "MESS_MANAGER"}:
                messages.error(request, "Only admins and mess managers can create polls.")
                return redirect("mess-portal")

            poll_type = request.POST.get("poll_type", "ADD")
            item_name = request.POST.get("poll_item", "").strip()
            if poll_type not in {"ADD", "REMOVE"} or not item_name:
                messages.error(request, "Provide a valid poll type and menu item.")
                return redirect("mess-portal")

            MenuPollOption.objects.get_or_create(
                month=month,
                item_name=item_name,
                poll_type=poll_type,
            )
            messages.success(request, "Poll option created.")
            return redirect("mess-portal")

        if action == "vote_poll":
            if not student:
                messages.error(request, "Only student accounts can vote in menu polls.")
                return redirect("mess-portal")

            option = get_object_or_404(MenuPollOption, id=request.POST.get("option_id"))
            if MenuPollVote.objects.filter(student=student, option=option).exists():
                messages.info(request, "You already voted for this option.")
            else:
                MenuPollVote.objects.create(student=student, option=option)
                messages.success(request, "Vote submitted.")
            return redirect("mess-portal")

    if selected_mess_type == "FOODPARK":
        menus = MessMenu.objects.none()
    else:
        menus = MessMenu.objects.filter(mess_type=selected_mess_type).order_by("week_day")
        if selected_mess_type in VEG_FALLBACK_TYPES and not menus.exists():
            menus = MessMenu.objects.filter(mess_type="VEG").order_by("week_day")
    menu_map = {
        menu.week_day: {
            "breakfast": _split_items(menu.breakfast_items),
            "lunch": _split_items(menu.lunch_items),
            "snacks": _split_items(menu.snacks_items),
            "dinner": _split_items(menu.dinner_items),
        }
        for menu in menus
    }
    menu_cards = [
        {
            "code": code,
            "label": WEEK_DAY_LABELS[code],
            "meal_map": menu_map.get(code, {slot: [] for slot in MEAL_SLOTS}),
            "has_menu": code in menu_map,
        }
        for code in WEEK_DAY_ORDER
    ]

    scoped_feedback = _scoped_feedback_queryset_for_user(request.user)

    least_rated = (
        scoped_feedback.values("menu_item")
        .annotate(avg_rating=Avg("rating"), total=Count("id"))
        .order_by("avg_rating", "-total")[:10]
    )

    can_view_staff_feedback = request.user.role in {"MESS_MANAGER", "WARDEN"}
    staff_feedback = []
    if can_view_staff_feedback:
        for feedback in scoped_feedback.order_by("-created_at")[:25]:
            day_code, meal_code, item_name = _parse_feedback_menu_item(feedback.menu_item)
            staff_feedback.append(
                {
                    "item_name": item_name or feedback.menu_item,
                    "day_label": WEEK_DAY_LABELS.get(day_code, day_code or "-") ,
                    "meal_label": (meal_code or feedback.meal_time or "-").replace("_", " ").title(),
                    "rating": feedback.rating,
                    "comment": feedback.comment,
                    "manager_reply": feedback.manager_reply,
                    "student_roll_no": feedback.student.roll_no if feedback.student else "",
                    "student_name": feedback.student.name if feedback.student else "",
                    "created_at": feedback.created_at,
                }
            )

    add_options = MenuPollOption.objects.filter(month=month, poll_type=MenuPollOption.PollType.ADD).annotate(
        total_votes=Count("votes")
    )
    remove_options = MenuPollOption.objects.filter(month=month, poll_type=MenuPollOption.PollType.REMOVE).annotate(
        total_votes=Count("votes")
    )

    current_week_day = WEEK_DAY_ORDER[min(datetime.now().weekday(), len(WEEK_DAY_ORDER) - 1)]
    poll_is_active = add_options.exists() or remove_options.exists()

    return render(
        request,
        "mess/portal.html",
        {
            "menu_cards": menu_cards,
            "least_rated": least_rated,
            "add_options": add_options,
            "remove_options": remove_options,
            "month": month,
            "can_manage_polls": request.user.role in {"ADMIN", "MESS_MANAGER"},
            "student": student,
            "rating_choices": [1, 2, 3, 4, 5],
            "meal_slots": MEAL_SLOTS,
            "current_week_day": current_week_day,
            "poll_is_active": poll_is_active,
            "selected_mess_type": selected_mess_type,
            "available_mess_types": list(MESS_TYPES.keys()),
            "can_view_staff_feedback": can_view_staff_feedback,
            "staff_feedback": staff_feedback,
        },
    )


@login_required
def download_mess_students_csv(request: HttpRequest) -> HttpResponse:
    if request.user.role != "ADMIN":
        messages.error(request, "Only admin can download mess student reports.")
        return redirect("dashboard-router")

    mess_name_filter = (
        request.GET.get("caterer")
        or request.GET.get("mess_name")
        or request.GET.get("mess")
        or ""
    ).strip()
    mess_type_filter = canonical_mess_type(
        request.GET.get("mess_type") or request.GET.get("meal_type") or request.GET.get("type")
    )

    students = Student.objects.select_related("block", "room", "user", "mess_caterer", "mess_caterer__block").all()
    if mess_name_filter:
        students = students.filter(mess_caterer__name__iexact=mess_name_filter)
    if mess_type_filter:
        students = students.filter(mess_allotment=mess_type_filter)

    students = students.order_by("mess_allotment", "mess_caterer__name", "roll_no")

    file_parts = ["mess_students"]
    if mess_name_filter:
        safe_name = "_".join(mess_name_filter.split())
        file_parts.append(safe_name)
    if mess_type_filter:
        file_parts.append(mess_type_filter.lower())
    file_parts.append(datetime.now().strftime("%Y-%m-%d"))

    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="{"_".join(file_parts)}.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "student_id",
            "roll_no",
            "name",
            "block",
            "room_no",
            "room_id",
            "mess_type",
            "mess_type_label",
            "mess_name",
            "mess_block",
            "mess_change_unlocked",
            "user_id",
            "username",
            "email",
            "phone_country_code",
            "phone_number",
        ]
    )

    for student in students:
        user = student.user
        caterer = student.mess_caterer
        writer.writerow(
            [
                student.id,
                student.roll_no,
                student.name,
                student.block.block_name if student.block else "",
                student.room_no,
                student.room_id or "",
                student.mess_allotment,
                student.get_mess_allotment_display(),
                caterer.name if caterer else "",
                caterer.block.block_name if caterer and caterer.block else "",
                student.mess_change_unlocked,
                user.id if user else "",
                user.username if user else "",
                user.email if user else "",
                user.phone_country_code if user else "",
                user.phone_number if user else "",
            ]
        )

    return response


@login_required
def download_mess_menu_csv(request: HttpRequest) -> HttpResponse:
    if request.user.role not in {"ADMIN", "SUPERVISOR"}:
        messages.error(request, "Only admin and supervisor can download mess menu reports.")
        return redirect("dashboard-router")

    mess_type_filter = canonical_mess_type(request.GET.get("mess_type") or request.GET.get("type"))
    archive_month = (request.GET.get("month") or request.GET.get("archive_month") or "").strip()

    if archive_month:
        menus = MessMenuArchive.objects.filter(archived_month=archive_month)
    else:
        menus = MessMenu.objects.all()

    if mess_type_filter:
        menus = menus.filter(mess_type=mess_type_filter)

    menus = menus.order_by("mess_type", "week_day")

    file_parts = ["mess_menu"]
    if mess_type_filter:
        file_parts.append(mess_type_filter.lower())
    if archive_month:
        file_parts.append(archive_month)
    file_parts.append(datetime.now().strftime("%Y-%m-%d"))

    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="{"_".join(file_parts)}.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "month",
            "mess_type",
            "mess_type_label",
            "week_day",
            "week_day_label",
            "breakfast_items",
            "lunch_items",
            "snacks_items",
            "dinner_items",
            "source",
        ]
    )

    for menu in menus:
        month_value = getattr(menu, "archived_month", "") if archive_month else ""
        writer.writerow(
            [
                month_value,
                menu.mess_type,
                menu.get_mess_type_display(),
                menu.week_day,
                menu.get_week_day_display(),
                menu.breakfast_items,
                menu.lunch_items,
                menu.snacks_items,
                menu.dinner_items,
                "archive" if archive_month else "current",
            ]
        )

    return response
