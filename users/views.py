import logging

from django.conf import settings
from django.contrib.auth import authenticate, get_user_model
from django.core.exceptions import ValidationError
from django.core.cache import cache
from users.otp_queue import OtpEmailJob, enqueue_otp_email
from rest_framework import viewsets
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from hostels.models import HostelBlock, Room
from mess.options import (
    MESS_TYPES,
    build_block_mess_caterers_payload,
    build_block_mess_types_payload,
    canonical_mess_type,
    get_all_caterer_names,
    get_allowed_mess_types_for_block,
)
from students.models import Student
from .models import AppNotification, OTPChallenge
from .permissions import IsAdmin
from .serializers import (
    AuthenticatedChangePasswordSerializer,
    AppNotificationSerializer,
    FirstTimePasswordSerializer,
    SignupCompleteSerializer,
    SignupOTPRequestSerializer,
    OTPRequestSerializer,
    OTPVerifySerializer,
    RoleAwareTokenSerializer,
    UserProfileSerializer,
    resolve_user_identifier,
)

User = get_user_model()
logger = logging.getLogger(__name__)


def _get_fixed_otp_code() -> str:
    if not getattr(settings, "DEBUG", False):
        return ""
    return getattr(settings, "DEFAULT_OTP_CODE", "").strip()


def _issue_otp_for_user(user) -> tuple[bool, str]:
    fixed_otp = _get_fixed_otp_code()
    challenge = OTPChallenge.create_for_user(user, code=fixed_otp or None)
    if fixed_otp:
        return True, ""
    if not user.email:
        return False, "No email address is available for this account."
    from_email = (getattr(settings, "DEFAULT_FROM_EMAIL", "") or getattr(settings, "EMAIL_HOST_USER", "") or "").strip()
    if not from_email:
        return False, "Email service is not configured. Please contact admin."
    try:
        enqueue_otp_email(
            OtpEmailJob(
                email=user.email,
                otp_code=challenge.otp_code,
                from_email=from_email,
            )
        )
        return True, ""
    except Exception:
        logger.exception("Failed to queue OTP email", extra={"email": user.email})
        return False, "Unable to send OTP email right now. Please try again in a moment."


def _is_allowed_signup_email(email: str) -> bool:
    normalized = (email or "").strip().lower()
    if normalized == "1442space@gmail.com":
        return True
    if "@" not in normalized:
        return False

    domain = normalized.rsplit("@", 1)[1]
    return domain == "vitstudent.ac.in" or domain == "vit.ac.in" or domain.endswith(".vit.ac.in")


def _is_student_signup_email(email: str) -> bool:
    normalized = (email or "").strip().lower()
    return normalized.endswith("@vitstudent.ac.in")


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


def _token_payload_for_user(user):
    refresh = RoleAwareTokenSerializer.get_token(user)
    return {
        "refresh": str(refresh),
        "access": str(refresh.access_token),
        "role": user.role,
        "username": user.username,
        "email": user.email,
        "full_name": user.get_full_name().strip() or user.username,
        "must_change_password": user.must_change_password,
    }


class LoginView(TokenObtainPairView):
    serializer_class = RoleAwareTokenSerializer
    permission_classes = [AllowAny]


class HealthView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({"status": "ok"})


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserProfileSerializer(request.user).data)


class RequestOTPView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = OTPRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        identifier = serializer.validated_data["identifier"]

        user = resolve_user_identifier(identifier)
        if not user or not user.email:
            return Response({"detail": "If account exists, OTP has been sent."})

        fixed_otp = _get_fixed_otp_code()
        challenge = OTPChallenge.create_for_user(user, code=fixed_otp or None)

        if fixed_otp:
            return Response({"detail": "OTP generated in dev mode.", "dev_mode": True})

        from_email = (getattr(settings, "DEFAULT_FROM_EMAIL", "") or getattr(settings, "EMAIL_HOST_USER", "") or "").strip()
        if not from_email:
            return Response({"detail": "Email service is not configured. Please contact admin."}, status=503)

        try:
            enqueue_otp_email(
                OtpEmailJob(
                    email=user.email,
                    otp_code=challenge.otp_code,
                    from_email=from_email,
                )
            )
        except Exception:
            logger.exception("Failed to queue OTP email", extra={"email": user.email})
            return Response({"detail": "Unable to send OTP email right now. Please try again shortly."}, status=503)
        return Response({"detail": "OTP sent to registered email.", "dev_mode": False})


class VerifyOTPView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = OTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = resolve_user_identifier(serializer.validated_data["identifier"])
        if not user:
            return Response({"valid": False}, status=400)

        challenge = OTPChallenge.objects.filter(user=user, consumed=False).order_by("-created_at").first()
        if not challenge or not challenge.is_valid_code(serializer.validated_data["otp_code"]):
            return Response({"valid": False}, status=400)

        return Response({"valid": True, "must_change_password": user.must_change_password})


class FirstTimePasswordSetupView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = FirstTimePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        challenge = serializer.validated_data["challenge"]

        user.set_password(serializer.validated_data["new_password"])
        user.must_change_password = False
        user.is_email_verified = True
        user.save(update_fields=["password", "must_change_password", "is_email_verified"])

        challenge.consumed = True
        challenge.save(update_fields=["consumed"])

        return Response({"detail": "Password created successfully."})


class SignupOptionsView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        cache_key = "signup-options:v2"
        payload = cache.get(cache_key)
        if payload is None:
            payload = {
                "country_codes": ["+91", "+1", "+44", "+65", "+971"],
                "block_choices": [{"value": code, "label": label} for code, label in HostelBlock.BlockName.choices],
                "staff_roles": [
                    {"value": User.Role.WARDEN, "label": "Warden"},
                    {"value": User.Role.MESS_MANAGER, "label": "Mess Manager"},
                    {"value": User.Role.LAUNDRY_PERSON, "label": "Laundry Manager"},
                    {"value": User.Role.SUPERVISOR, "label": "Supervisor"},
                    {"value": User.Role.DIRECTOR, "label": "Director"},
                ],
                "department_choices": [{"value": code, "label": label} for code, label in User.Department.choices],
                "mess_names": get_all_caterer_names(),
                "student_mess_types": list(MESS_TYPES.keys()),
                "block_mess_types": build_block_mess_types_payload(),
                "block_mess_caterers": build_block_mess_caterers_payload(),
            }
            cache.set(cache_key, payload, timeout=3600)
        return Response(payload)


class SignupRequestOTPView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = SignupOTPRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()

        if not _is_allowed_signup_email(email):
            return Response(
                {"detail": "Use @vitstudent.ac.in, @vit.ac.in, or the authorized admin email."},
                status=400,
            )

        user = User.objects.filter(email__iexact=email).first()
        if user and user.has_usable_password() and not user.must_change_password:
            return Response({"detail": "Account already exists. Please sign in."}, status=400)

        created = False
        if not user:
            user = User.objects.create(
                email=email,
                username=_ensure_username(email),
                is_active=True,
                must_change_password=True,
                is_email_verified=False,
            )
            created = True
            user.set_unusable_password()
            user.save(update_fields=["password"])

        otp_sent, otp_error = _issue_otp_for_user(user)
        if not otp_sent:
            if created:
                user.delete()
            return Response({"detail": otp_error}, status=503)
        return Response({"detail": "OTP sent to email.", "dev_mode": bool(_get_fixed_otp_code())})


class SignupCompleteView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = SignupCompleteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        email = data["email"].strip().lower()
        user = User.objects.filter(email__iexact=email).first()
        if not user:
            return Response({"detail": "Signup session expired. Request OTP again."}, status=400)

        challenge = OTPChallenge.objects.filter(user=user, consumed=False).order_by("-created_at").first()
        if not challenge or not challenge.is_valid_code(data["otp_code"]):
            return Response({"detail": "Invalid or expired OTP."}, status=400)

        name = data["name"].strip()
        if not name:
            return Response({"detail": "Name is required."}, status=400)

        parts = name.split()
        user.first_name = parts[0]
        user.last_name = " ".join(parts[1:]) if len(parts) > 1 else ""
        user.phone_country_code = (data.get("phone_country_code") or "+91").strip() or "+91"
        user.phone_number = (data.get("phone_number") or "").strip()

        if _is_student_signup_email(email):
            reg_no = (data.get("registration_no") or "").strip().upper()
            block_name = (data.get("block") or "").strip().upper()
            room_no = (data.get("room_no") or "").strip().upper()
            mess_type = canonical_mess_type(data.get("mess_type"))
            caterer_name = (data.get("caterer_name") or "").strip()

            if not all([reg_no, block_name, room_no, mess_type, caterer_name]):
                return Response(
                    {
                        "detail": "Registration number, block, room number, mess type and caterer are required for students."
                    },
                    status=400,
                )

            block = HostelBlock.objects.filter(block_name=block_name).first()
            if not block:
                return Response({"detail": "Invalid block selected."}, status=400)

            allowed_mess_types = get_allowed_mess_types_for_block(block_name)
            if mess_type not in allowed_mess_types:
                return Response(
                    {
                        "detail": f"Invalid mess type for block {block_name}. Allowed: {', '.join(allowed_mess_types)}."
                    },
                    status=400,
                )

            room, _ = Room.objects.get_or_create(block=block, room_no=room_no, defaults={"capacity": 1})
            mess_caterer = None
            if caterer_name:
                from mess.models import Caterer

                mess_caterer = Caterer.objects.filter(name=caterer_name, block_id=block.id, meal_types=mess_type).first()
                if not mess_caterer:
                    return Response(
                        {"detail": "Please choose a valid caterer for the selected block and mess type."},
                        status=400,
                    )

            user.role = User.Role.STUDENT
            user.username = _ensure_username(user.email, reg_no)
            user.job_title = ""
            user.department = ""
            user.assigned_mess_name = ""

            try:
                Student.objects.update_or_create(
                    roll_no=reg_no,
                    defaults={
                        "user": user,
                        "name": name,
                        "block": block,
                        "room": room,
                        "room_no": room_no,
                        "mess_allotment": mess_type,
                        "mess_caterer": mess_caterer,
                    },
                )
            except ValidationError as exc:
                return Response({"detail": "; ".join(getattr(exc, "messages", [str(exc)]))}, status=400)
        else:
            role = (data.get("role") or "").strip()
            job_title = (data.get("job_title") or "").strip()
            department = (data.get("department") or "").strip()
            assigned_mess_name = (data.get("assigned_mess_name") or "").strip()

            if email == "1442space@gmail.com":
                role = User.Role.ADMIN
            elif role not in {
                User.Role.WARDEN,
                User.Role.MESS_MANAGER,
                User.Role.LAUNDRY_PERSON,
                User.Role.SUPERVISOR,
                User.Role.DIRECTOR,
            }:
                return Response({"detail": "Please choose a valid staff role."}, status=400)

            if not job_title or not department:
                return Response({"detail": "Job title and concerned department are required."}, status=400)

            if role == User.Role.MESS_MANAGER and not assigned_mess_name:
                return Response({"detail": "Please choose a mess name for mess manager role."}, status=400)

            if role == User.Role.MESS_MANAGER and assigned_mess_name not in get_all_caterer_names():
                return Response({"detail": "Please choose a valid mess name from the available options."}, status=400)

            user.role = role
            user.username = _ensure_username(user.email)
            user.job_title = job_title
            user.department = department
            user.assigned_mess_name = assigned_mess_name if role == User.Role.MESS_MANAGER else ""

        user.set_password(data["password"])
        user.must_change_password = False
        user.is_email_verified = True
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
                "password",
                "must_change_password",
                "is_email_verified",
            ]
        )

        challenge.consumed = True
        challenge.save(update_fields=["consumed"])

        return Response({"detail": "Signup complete.", "data": _token_payload_for_user(user)})


class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = AuthenticatedChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        current_password = serializer.validated_data["current_password"]
        new_password = serializer.validated_data["new_password"]

        authenticated = authenticate(request=request, username=request.user.username, password=current_password)
        if not authenticated:
            return Response({"detail": "Current password is incorrect."}, status=400)

        request.user.set_password(new_password)
        request.user.must_change_password = False
        request.user.save(update_fields=["password", "must_change_password"])
        return Response({"detail": "Password updated successfully."})


class AppNotificationViewSet(viewsets.ModelViewSet):
    serializer_class = AppNotificationSerializer

    def get_queryset(self):
        qs = AppNotification.objects.all()
        if self.action == "list" and getattr(self.request.user, "role", None) != User.Role.ADMIN:
            qs = qs.filter(is_active=True).filter(audience__in=[AppNotification.Audience.ALL, self.request.user.role])
        return qs

    def get_permissions(self):
        if self.action in ["create", "update", "partial_update", "destroy"]:
            return [IsAdmin()]
        return [IsAuthenticated()]

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)
