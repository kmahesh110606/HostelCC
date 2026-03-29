from datetime import datetime

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Avg, Count, Q
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render

from students.models import Student
from mess.options import MESS_TYPES, canonical_mess_type

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessMenu


MEAL_SLOTS = ["breakfast", "lunch", "snacks", "dinner"]
WEEK_DAY_ORDER = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
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
        selected_mess_type = student.mess_allotment
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

            Feedback.objects.create(
                student=student,
                menu_item=menu_item,
                rating=rating,
                comment=comment,
                month=month,
            )
            messages.success(request, "Rating submitted.")
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

    menus = MessMenu.objects.filter(mess_type=selected_mess_type).order_by("week_day")
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
