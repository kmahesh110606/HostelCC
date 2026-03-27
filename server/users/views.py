from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from .models import OTPChallenge
from .serializers import (
    FirstTimePasswordSerializer,
    OTPRequestSerializer,
    OTPVerifySerializer,
    RoleAwareTokenSerializer,
)

User = get_user_model()


class LoginView(TokenObtainPairView):
    serializer_class = RoleAwareTokenSerializer
    permission_classes = [AllowAny]


class HealthView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({"status": "ok"})


class RequestOTPView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = OTPRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        username = serializer.validated_data["username"]

        user = User.objects.filter(username=username).first()
        if not user or not user.email:
            return Response({"detail": "If account exists, OTP has been sent."})

        fixed_otp = getattr(settings, "DEFAULT_OTP_CODE", "").strip()
        challenge = OTPChallenge.create_for_user(user, code=fixed_otp or None)

        if fixed_otp:
            return Response({"detail": "OTP generated in dev mode.", "dev_mode": True})

        send_mail(
            subject="Hostel Management OTP",
            message=f"Your OTP is {challenge.otp_code}. It expires in 10 minutes.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[user.email],
            fail_silently=False,
        )
        return Response({"detail": "OTP sent to registered email.", "dev_mode": False})


class VerifyOTPView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = OTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = User.objects.filter(username=serializer.validated_data["username"]).first()
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
