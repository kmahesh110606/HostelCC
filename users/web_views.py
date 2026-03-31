import json

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate, get_user_model, login, logout
from django.contrib.auth.decorators import login_required
from django.core.mail import send_mail
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render

from hostels.models import HostelBlock, Room
from mess.options import (
    MESS_TYPES,
    build_block_mess_types_payload,
    canonical_mess_type,
    get_all_caterer_names,
    get_allowed_mess_types_for_block,
)
from mess.models import Caterer
from .models import AppNotification, OTPChallenge
from students.models import Student
from students.utils import resolve_student_for_user

User = get_user_model()


def _get_fixed_otp_code() -> str:
    if not getattr(settings, "DEBUG", False):
        return ""
    return getattr(settings, "DEFAULT_OTP_CODE", "").strip()


def _issue_otp(user) -> None:
    fixed_otp = _get_fixed_otp_code()
    challenge = OTPChallenge.create_for_user(user, code=fixed_otp or None)

    if fixed_otp:
        return

    if user.email:
        send_mail(
            subject="Hostel Management OTP",
            message=f"Your OTP is {challenge.otp_code}. It expires in 10 minutes.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
            fail_silently=False,
        )


def _is_allowed_signup_email(email: str) -> bool:
    lower = email.lower()
    return (
        lower.endswith("@vitstudent.ac.in")
        or lower.endswith("@vit.ac.in")
        or lower == "kmahesh110606@outlook.com"
    )


def _ensure_username(email: str, registration_number: str = "") -> str:
    if registration_number:
        candidate = registration_number.strip().upper()
    else:
        candidate = email.split("@")[0].replace(".", "_")

    username = candidate
    suffix = 1
    while User.objects.filter(username=username).exclude(email__iexact=email).exists():
        suffix += 1
        username = f"{candidate}{suffix}"
    return username


def _onboard_user_from_signup(request: HttpRequest, user) -> str:
    email = user.email.lower()
    name = request.POST.get("name", "").strip()
    phone_country_code = request.POST.get("phone_country_code", "+91").strip()
    phone_number = request.POST.get("phone_number", "").strip()

    if not name:
        return "Name is required."

    parts = name.split()
    user.first_name = parts[0]
    user.last_name = " ".join(parts[1:]) if len(parts) > 1 else ""
    user.phone_country_code = phone_country_code or "+91"
    user.phone_number = phone_number

    if email.endswith("@vitstudent.ac.in"):
        reg_no = request.POST.get("registration_no", "").strip().upper()
        block_name = request.POST.get("block", "").strip().upper()
        room_no = request.POST.get("room_no", "").strip().upper()
        mess_type = canonical_mess_type(request.POST.get("mess_type", ""))

        if not all([reg_no, block_name, room_no, mess_type]):
            return "Registration number, block, room number and mess type are required for students."

        block = HostelBlock.objects.filter(block_name=block_name).first()
        if not block:
            return "Invalid block selected."

        allowed_mess_types = get_allowed_mess_types_for_block(block_name)
        if mess_type not in allowed_mess_types:
            return f"Invalid mess type for block {block_name}. Allowed: {', '.join(allowed_mess_types)}."

        room, _ = Room.objects.get_or_create(block=block, room_no=room_no, defaults={"capacity": 1})
        user.role = User.Role.STUDENT
        user.username = _ensure_username(user.email, reg_no)
        user.job_title = ""
        user.department = ""
        user.assigned_mess_name = ""
        user.save(
            update_fields=[
                "first_name",
                "last_name",
                "phone_country_code",
                "phone_number",
                "role",
                "username",
                "job_title",
                "department",
                "assigned_mess_name",
            ]
        )

        Student.objects.update_or_create(
            roll_no=reg_no,
            defaults={
                "user": user,
                "name": name,
                "block": block,
                "room": room,
                "room_no": room_no,
                "mess_allotment": mess_type,
            },
        )
    else:
        role = request.POST.get("role", "").strip()
        job_title = request.POST.get("job_title", "").strip()
        department = request.POST.get("department", "").strip()
        assigned_mess_name = request.POST.get("assigned_mess_name", "").strip()

        if user.email.lower() == "kmahesh110606@outlook.com":
            role = User.Role.ADMIN
        elif role not in {
            User.Role.WARDEN,
            User.Role.MESS_MANAGER,
            User.Role.LAUNDRY_PERSON,
            User.Role.SUPERVISOR,
            User.Role.DIRECTOR,
        }:
            return "Please choose a valid staff role."

        if not job_title or not department:
            return "Job title and concerned department are required."

        if role == User.Role.MESS_MANAGER and not assigned_mess_name:
            return "Please choose a mess name for mess manager role."

        if role == User.Role.MESS_MANAGER and assigned_mess_name not in get_all_caterer_names():
            return "Please choose a valid mess name from available options."

        user.role = role
        user.username = _ensure_username(user.email)
        user.job_title = job_title
        user.department = department
        user.assigned_mess_name = assigned_mess_name if role == User.Role.MESS_MANAGER else ""
        user.save(
            update_fields=[
                "first_name",
                "last_name",
                "phone_country_code",
                "phone_number",
                "role",
                "username",
                "job_title",
                "department",
                "assigned_mess_name",
            ]
        )

    request.session["show_welcome"] = True
    return ""


def role_login(request: HttpRequest) -> HttpResponse:
    if request.user.is_authenticated:
        return redirect("dashboard-router")

    mode = request.GET.get("mode") or request.POST.get("mode") or "signin"
    stage = request.session.get("auth_stage", "signin")
    email = request.session.get("auth_email", "")
    error_message = ""
    next_url = request.GET.get("next") or request.POST.get("next") or ""

    if mode == "signin" and stage not in {"signin", "signup-otp", "signup-details"}:
        stage = "signin"
    if mode == "signup" and stage not in {"signup-email", "signup-otp", "signup-details"}:
        stage = "signup-email"

    if request.method == "POST":
        stage = request.POST.get("stage", "signin")
        posted_email = request.POST.get("email", "").strip()

        # Always update session and local email for signup-details stage
        if stage == "signup-details":
            if posted_email:
                email = posted_email
                request.session["auth_email"] = email
            elif not email:
                # fallback: try to get from session
                email = request.session.get("auth_email", "")

        if stage == "signin":
            email = posted_email
            user = User.objects.filter(email__iexact=email).first()
            password = request.POST.get("password", "")

            if not user:
                error_message = "No account exists with this email address. Please sign up first."
                mode = "signin"
            else:
                authenticated_user = authenticate(request, username=user.username, password=password)
                if authenticated_user is None:
                    error_message = "Invalid password."
                else:
                    login(request, authenticated_user)
                    request.session.pop("auth_stage", None)
                    request.session.pop("auth_email", None)
                    if next_url and next_url.startswith("/"):
                        return redirect(next_url)
                    if request.session.pop("show_welcome", False):
                        return redirect("welcome")
                    return redirect("dashboard-router")

        elif stage == "signup-email":
            mode = "signup"
            email = posted_email.lower()
            if not _is_allowed_signup_email(email):
                error_message = "Use @vitstudent.ac.in, @vit.ac.in, or the authorized admin email."
            elif User.objects.filter(email__iexact=email).exists():
                error_message = "Account already exists. Please sign in."
            else:
                user = User.objects.create(
                    email=email,
                    username=_ensure_username(email),
                    is_active=True,
                    must_change_password=True,
                    is_email_verified=False,
                )
                user.set_unusable_password()
                user.save(update_fields=["password"])
                _issue_otp(user)
                request.session["auth_email"] = email
                request.session["auth_stage"] = "signup-otp"
                stage = "signup-otp"

        elif stage == "signup-otp":
            mode = "signup"
            email = posted_email or email
            user = User.objects.filter(email__iexact=email).first()
            otp_code = request.POST.get("otp_code", "").strip()

            if not user:
                error_message = "Session expired. Enter email again."
                request.session.pop("auth_stage", None)
                request.session.pop("auth_email", None)
                stage = "signup-email"
            else:
                challenge = OTPChallenge.objects.filter(user=user, consumed=False).order_by("-created_at").first()
                if not challenge or not challenge.is_valid_code(otp_code):
                    error_message = "Invalid or expired OTP."
                else:
                    user.is_email_verified = True
                    user.save(update_fields=["is_email_verified"])

                    challenge.consumed = True
                    challenge.save(update_fields=["consumed"])
                    request.session["auth_stage"] = "signup-details"
                    stage = "signup-details"

        elif stage == "signup-details":
            mode = "signup"
            email = posted_email or email
            password = request.POST.get("password", "")
            confirm_password = request.POST.get("confirm_password", "")
            user = User.objects.filter(email__iexact=email).first()

            if not user:
                error_message = "Session expired. Start signup again."
                stage = "signup-email"
            elif len(password) < 8:
                error_message = "Password must be at least 8 characters."
            elif password != confirm_password:
                error_message = "Passwords do not match."
            else:
                detail_error = _onboard_user_from_signup(request, user)
                if detail_error:
                    error_message = detail_error
                else:
                    user.set_password(password)
                    user.must_change_password = False
                    user.save(update_fields=["password", "must_change_password"])

                    authenticated_user = authenticate(request, username=user.username, password=password)
                    if authenticated_user is None:
                        error_message = "Unable to complete signup. Please try sign in."
                    else:
                        login(request, authenticated_user)
                        request.session.pop("auth_stage", None)
                        request.session.pop("auth_email", None)
                        return redirect("welcome")

    return render(
        request,
        "auth/login.html",
        {
            "mode": mode,
            "stage": stage,
            "email": email,  # always set
            "error_message": error_message,
            "fixed_otp": _get_fixed_otp_code(),
            "next_url": next_url,
            "block_choices": HostelBlock.BlockName.choices,
            "staff_roles": [
                (User.Role.WARDEN, "Warden"),
                (User.Role.MESS_MANAGER, "Mess Manager"),
                (User.Role.LAUNDRY_PERSON, "Laundry Manager"),
                (User.Role.SUPERVISOR, "Supervisor"),
                (User.Role.DIRECTOR, "Director"),
            ],
            "department_choices": User.Department.choices,
            "country_codes": ["+91", "+1", "+44", "+65", "+971"],
            "mess_names": get_all_caterer_names(),
            "student_mess_types": list(MESS_TYPES.keys()),
            "block_mess_types_json": json.dumps(build_block_mess_types_payload()),
        },
    )


def forgot_password(request: HttpRequest) -> HttpResponse:
    fixed_otp = _get_fixed_otp_code()
    stage = request.session.get("forgot_stage", "email")
    email = request.session.get("forgot_email", "")
    error_message = ""

    if request.method == "POST":
        stage = request.POST.get("stage", "email")
        posted_email = request.POST.get("email", "").strip()

        if stage == "email":
            if not posted_email:
                error_message = "Please enter your email address."
                stage = "email"
            else:
                user = User.objects.filter(email__iexact=posted_email).first()
                if not user:
                    error_message = "No account exists with this email address."
                    stage = "email"
                else:
                    email = user.email
                    request.session["forgot_email"] = email
                    request.session["forgot_stage"] = "otp"
                    _issue_otp(user)
                    stage = "otp"
        else:
            email = posted_email or email
            user = User.objects.filter(email__iexact=email).first()
            otp_code = request.POST.get("otp_code", "").strip()
            new_password = request.POST.get("new_password", "")

            if not user:
                error_message = "Session expired. Enter email again."
                request.session.pop("forgot_stage", None)
                request.session.pop("forgot_email", None)
                stage = "email"
            else:
                challenge = OTPChallenge.objects.filter(user=user, consumed=False).order_by("-created_at").first()
                if not challenge or not challenge.is_valid_code(otp_code):
                    error_message = "Invalid or expired OTP."
                elif len(new_password) < 8:
                    error_message = "Password must be at least 8 characters."
                else:
                    user.set_password(new_password)
                    user.must_change_password = False
                    user.is_email_verified = True
                    user.save(update_fields=["password", "must_change_password", "is_email_verified"])

                    challenge.consumed = True
                    challenge.save(update_fields=["consumed"])

                    request.session.pop("forgot_stage", None)
                    request.session.pop("forgot_email", None)
                    messages.success(request, "Password reset successful. Please login.")
                    return redirect("login")

    return render(
        request,
        "auth/forgot_password.html",
        {
            "stage": stage,
            "email": email,
            "error_message": error_message,
            "fixed_otp": fixed_otp,
        },
    )


def web_logout(request: HttpRequest) -> HttpResponse:
    logout(request)
    request.session.pop("login_stage", None)
    request.session.pop("login_email", None)
    request.session.pop("forgot_stage", None)
    request.session.pop("forgot_email", None)
    return redirect("login")


@login_required
def profile_page(request: HttpRequest) -> HttpResponse:
    student = resolve_student_for_user(request.user)

    if request.method == "POST":
        action = request.POST.get("action", "").strip()

        if action == "update_mess_choice":
            if not student:
                messages.error(request, "Only students can update mess choice.")
                return redirect("profile")
            if not student.mess_change_unlocked:
                messages.error(request, "Mess change is currently locked. Contact admin.")
                return redirect("profile")

            raw_caterer_id = (request.POST.get("requested_caterer_id") or "").strip()
            if not raw_caterer_id:
                messages.error(request, "Please select a caterer.")
                return redirect("profile")

            try:
                requested_caterer_id = int(raw_caterer_id)
            except ValueError:
                messages.error(request, "Invalid caterer selection.")
                return redirect("profile")

            selected_caterer = Caterer.objects.filter(
                id=requested_caterer_id,
                block_id=student.block_id,
                meal_types=student.mess_allotment,
            ).first()
            if not selected_caterer:
                messages.error(request, "Selected caterer is not available for your block and mess type.")
                return redirect("profile")

            student.mess_caterer = selected_caterer
            student.mess_allotment = selected_caterer.meal_types
            student.mess_change_unlocked = False
            student.save(update_fields=["mess_caterer", "mess_allotment", "mess_change_unlocked"])
            messages.success(request, "Mess caterer updated successfully.")
            return redirect("profile")

        if action == "set_mess_unlock":
            if request.user.role != User.Role.ADMIN:
                messages.error(request, "Only admin can unlock mess changes.")
                return redirect("profile")

            student_id = request.POST.get("student_id", "").strip()
            can_edit = request.POST.get("mess_change_unlocked") == "on"
            target = Student.objects.filter(id=student_id).first()

            if not target:
                messages.error(request, "Student not found.")
                return redirect("profile")

            target.mess_change_unlocked = can_edit
            target.save(update_fields=["mess_change_unlocked"])
            if can_edit:
                messages.success(request, f"Unlocked mess change for {target.roll_no}.")
            else:
                messages.success(request, f"Locked mess change for {target.roll_no}.")
            return redirect("profile")

    available_mess_caterers = []
    if student:
        available_mess_caterers = list(
            Caterer.objects.filter(block_id=student.block_id, meal_types=student.mess_allotment).order_by(
                "name", "id"
            )
        )

    students_for_admin = []
    if request.user.role == User.Role.ADMIN:
        students_for_admin = Student.objects.select_related("block").order_by("roll_no")[:300]

    return render(
        request,
        "profile/detail.html",
        {
            "student": student,
            "available_mess_caterers": available_mess_caterers,
            "students_for_admin": students_for_admin,
        },
    )


@login_required
def welcome_page(request: HttpRequest) -> HttpResponse:
    return render(request, "auth/welcome.html")


def home(request: HttpRequest) -> HttpResponse:
    if request.user.is_authenticated:
        return redirect("dashboard-router")
    return redirect("login")


@login_required
def dashboard_router(request: HttpRequest) -> HttpResponse:
    role_to_template = {
        "STUDENT": "dashboard/student.html",
        "WARDEN": "dashboard/warden.html",
        "MESS_MANAGER": "dashboard/mess_manager.html",
        "LAUNDRY_PERSON": "dashboard/laundry_person.html",
        "ADMIN": "dashboard/admin.html",
    }
    template = role_to_template.get(request.user.role, "dashboard/student.html")
    notifications = AppNotification.objects.filter(is_active=True).filter(
        audience__in=[AppNotification.Audience.ALL, request.user.role]
    )[:6]
    context = {"notifications": notifications}
    if request.user.role == User.Role.ADMIN:
        context["mess_names"] = get_all_caterer_names()
        context["mess_types"] = list(MESS_TYPES.keys())

    return render(request, template, context)


@login_required
def notification_panel(request: HttpRequest) -> HttpResponse:
    if request.method == "POST":
        if request.user.role != User.Role.ADMIN:
            messages.error(request, "Only admin can manage notifications.")
            return redirect("notification-panel")

        if request.POST.get("action") == "delete":
            notification_id = request.POST.get("notification_id", "").strip()
            target = AppNotification.objects.filter(id=notification_id).first()
            if not target:
                messages.error(request, "Notification not found.")
            else:
                target.delete()
                messages.success(request, "Notification deleted.")
            return redirect("notification-panel")

        title = request.POST.get("title", "").strip()
        message = request.POST.get("message", "").strip()
        audience = request.POST.get("audience", AppNotification.Audience.ALL).strip()
        level = request.POST.get("level", AppNotification.Level.INFO).strip()
        is_active = request.POST.get("is_active") == "on"
        poster = request.FILES.get("poster")

        if not title or not message:
            messages.error(request, "Title and message are required.")
        else:
            if poster:
                lower_name = poster.name.lower()
                if not (lower_name.endswith(".png") or lower_name.endswith(".jpg") or lower_name.endswith(".jpeg") or lower_name.endswith(".pdf")):
                    messages.error(request, "Poster must be PNG, JPG, JPEG, or PDF.")
                    return redirect("notification-panel")

            AppNotification.objects.create(
                title=title,
                message=message,
                audience=audience,
                level=level,
                is_active=is_active,
                poster=poster,
                created_by=request.user,
            )
            messages.success(request, "Notification published.")
        return redirect("notification-panel")

    if request.user.role == User.Role.ADMIN:
        notifications = AppNotification.objects.all()[:30]
    else:
        notifications = AppNotification.objects.filter(is_active=True).filter(
            audience__in=[AppNotification.Audience.ALL, request.user.role]
        )[:20]

    return render(
        request,
        "notifications/panel.html",
        {
            "notifications": notifications,
            "is_admin": request.user.role == User.Role.ADMIN,
            "audience_choices": AppNotification.Audience.choices,
            "level_choices": AppNotification.Level.choices,
        },
    )
