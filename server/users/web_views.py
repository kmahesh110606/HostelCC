from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate, get_user_model, login, logout
from django.contrib.auth.decorators import login_required
from django.core.mail import send_mail
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render

from .models import OTPChallenge
from students.models import Student

User = get_user_model()


def _issue_otp(user: User) -> None:
    fixed_otp = getattr(settings, "DEFAULT_OTP_CODE", "").strip()
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


def role_login(request: HttpRequest) -> HttpResponse:
    if request.user.is_authenticated:
        return redirect("dashboard-router")

    stage = request.session.get("login_stage", "email")
    email = request.session.get("login_email", "")
    error_message = ""
    next_url = request.GET.get("next") or request.POST.get("next") or ""

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
                    request.session["login_email"] = email

                    if user.must_change_password or not user.has_usable_password():
                        _issue_otp(user)
                        request.session["login_stage"] = "otp"
                        stage = "otp"
                    else:
                        request.session["login_stage"] = "password"
                        stage = "password"

        elif stage == "password":
            email = posted_email or email
            user = User.objects.filter(email__iexact=email).first()
            password = request.POST.get("password", "")

            if not user:
                error_message = "Session expired. Enter email again."
                request.session.pop("login_stage", None)
                request.session.pop("login_email", None)
                stage = "email"
            else:
                authenticated_user = authenticate(request, username=user.username, password=password)
                if authenticated_user is None:
                    error_message = "Invalid password."
                else:
                    login(request, authenticated_user)
                    request.session.pop("login_stage", None)
                    request.session.pop("login_email", None)
                    if next_url and next_url.startswith("/"):
                        return redirect(next_url)
                    return redirect("dashboard-router")

        elif stage == "otp":
            email = posted_email or email
            user = User.objects.filter(email__iexact=email).first()
            otp_code = request.POST.get("otp_code", "").strip()
            new_password = request.POST.get("new_password", "")

            if not user:
                error_message = "Session expired. Enter email again."
                request.session.pop("login_stage", None)
                request.session.pop("login_email", None)
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

                    authenticated_user = authenticate(request, username=user.username, password=new_password)
                    if authenticated_user is None:
                        request.session.pop("login_stage", None)
                        request.session.pop("login_email", None)
                        messages.success(request, "Password set. Please login.")
                        return redirect("login")

                    login(request, authenticated_user)
                    request.session.pop("login_stage", None)
                    request.session.pop("login_email", None)
                    if next_url and next_url.startswith("/"):
                        return redirect(next_url)
                    return redirect("dashboard-router")

    return render(
        request,
        "auth/login.html",
        {
            "stage": stage,
            "email": email,
            "error_message": error_message,
            "fixed_otp": getattr(settings, "DEFAULT_OTP_CODE", "").strip(),
            "next_url": next_url,
        },
    )


def forgot_password(request: HttpRequest) -> HttpResponse:
    fixed_otp = getattr(settings, "DEFAULT_OTP_CODE", "").strip()
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
    student = Student.objects.select_related("block", "room").filter(user=request.user).first()
    return render(
        request,
        "profile/detail.html",
        {
            "student": student,
        },
    )


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
    return render(request, template)
