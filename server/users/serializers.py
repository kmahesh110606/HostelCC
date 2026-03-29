from django.contrib.auth import authenticate
from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import AppNotification, OTPChallenge
from students.utils import resolve_student_for_user

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email", "role", "first_name", "last_name"]


def resolve_user_identifier(identifier: str):
    value = (identifier or "").strip()
    if not value:
        return None

    if "@" in value:
        return User.objects.filter(email__iexact=value).first()
    return User.objects.filter(username__iexact=value).first()


class RoleAwareTokenSerializer(TokenObtainPairSerializer):
    username_field = "email"

    email = serializers.EmailField(required=False)
    username = serializers.CharField(required=False, allow_blank=True)

    default_error_messages = {
        "no_active_account": "No active account found with the given credentials",
    }

    def validate(self, attrs):
        identifier = attrs.get("email") or attrs.get("username") or self.initial_data.get("email") or self.initial_data.get("username")
        password = attrs.get("password") or self.initial_data.get("password")

        user = resolve_user_identifier(identifier or "")
        if user is None:
            raise serializers.ValidationError(self.error_messages["no_active_account"], code="no_active_account")

        authenticated = authenticate(
            request=self.context.get("request"),
            username=user.username,
            password=password,
        )
        if not authenticated or not authenticated.is_active:
            raise serializers.ValidationError(self.error_messages["no_active_account"], code="no_active_account")

        refresh = self.get_token(authenticated)
        data = {
            "refresh": str(refresh),
            "access": str(refresh.access_token),
            "role": authenticated.role,
            "username": authenticated.username,
            "email": authenticated.email,
            "full_name": authenticated.get_full_name().strip() or authenticated.username,
            "must_change_password": authenticated.must_change_password,
        }
        return data

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token["role"] = user.role
        token["username"] = user.username
        token["email"] = user.email
        token["must_change_password"] = user.must_change_password
        return token


class OTPRequestSerializer(serializers.Serializer):
    email = serializers.EmailField(required=False)
    username = serializers.CharField(max_length=150, required=False, allow_blank=True)

    def validate(self, attrs):
        identifier = attrs.get("email") or attrs.get("username")
        if not identifier:
            raise serializers.ValidationError("Email is required.")
        attrs["identifier"] = identifier
        return attrs


class OTPVerifySerializer(serializers.Serializer):
    email = serializers.EmailField(required=False)
    username = serializers.CharField(max_length=150, required=False, allow_blank=True)
    otp_code = serializers.CharField(max_length=6)

    def validate(self, attrs):
        identifier = attrs.get("email") or attrs.get("username")
        if not identifier:
            raise serializers.ValidationError("Email is required.")
        attrs["identifier"] = identifier
        return attrs


class FirstTimePasswordSerializer(serializers.Serializer):
    email = serializers.EmailField(required=False)
    username = serializers.CharField(max_length=150, required=False, allow_blank=True)
    otp_code = serializers.CharField(max_length=6)
    new_password = serializers.CharField(min_length=8)

    def validate(self, attrs):
        identifier = attrs.get("email") or attrs.get("username")
        if not identifier:
            raise serializers.ValidationError("Email is required.")

        user = resolve_user_identifier(identifier)
        if not user:
            raise serializers.ValidationError("User does not exist.")

        challenge = OTPChallenge.objects.filter(user=user, consumed=False).order_by("-created_at").first()
        if not challenge or not challenge.is_valid_code(attrs["otp_code"]):
            raise serializers.ValidationError("OTP is invalid or expired.")

        attrs["user"] = user
        attrs["challenge"] = challenge
        return attrs


class SignupOTPRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class SignupCompleteSerializer(serializers.Serializer):
    email = serializers.EmailField()
    otp_code = serializers.CharField(max_length=6)
    password = serializers.CharField(min_length=8)
    confirm_password = serializers.CharField(min_length=8)
    name = serializers.CharField(max_length=150)
    phone_country_code = serializers.CharField(max_length=6, required=False, default="+91")
    phone_number = serializers.CharField(max_length=20, required=False, allow_blank=True)

    registration_no = serializers.CharField(max_length=30, required=False, allow_blank=True)
    block = serializers.CharField(max_length=10, required=False, allow_blank=True)
    room_no = serializers.CharField(max_length=10, required=False, allow_blank=True)
    mess_type = serializers.CharField(max_length=100, required=False, allow_blank=True)

    role = serializers.CharField(max_length=20, required=False, allow_blank=True)
    job_title = serializers.CharField(max_length=120, required=False, allow_blank=True)
    department = serializers.CharField(max_length=30, required=False, allow_blank=True)
    assigned_mess_name = serializers.CharField(max_length=120, required=False, allow_blank=True)

    def validate(self, attrs):
        if attrs["password"] != attrs["confirm_password"]:
            raise serializers.ValidationError("Passwords do not match.")
        return attrs


class AuthenticatedChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(min_length=1)
    new_password = serializers.CharField(min_length=8)


class UserProfileSerializer(serializers.ModelSerializer):
    full_name = serializers.SerializerMethodField()
    student = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "email",
            "first_name",
            "last_name",
            "full_name",
            "role",
            "phone_country_code",
            "phone_number",
            "job_title",
            "department",
            "assigned_mess_name",
            "must_change_password",
            "is_email_verified",
            "is_active",
            "student",
        ]

    def get_full_name(self, obj):
        return obj.get_full_name().strip() or obj.username

    def get_student(self, obj):
        student = resolve_student_for_user(obj)
        if not student:
            return None
        return {
            "id": student.id,
            "name": student.name,
            "roll_no": student.roll_no,
            "block_name": student.block.block_name if student.block else "",
            "room_no": student.room_no,
            "mess_allotment": student.mess_allotment,
        }


class AppNotificationSerializer(serializers.ModelSerializer):
    created_by_name = serializers.SerializerMethodField()
    poster_url = serializers.SerializerMethodField()

    class Meta:
        model = AppNotification
        fields = [
            "id",
            "title",
            "message",
            "poster",
            "poster_url",
            "level",
            "audience",
            "is_active",
            "created_by",
            "created_by_name",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["created_by", "created_by_name", "created_at", "updated_at"]

    def get_created_by_name(self, obj):
        if not obj.created_by:
            return ""
        return obj.created_by.get_full_name().strip() or obj.created_by.username

    def get_poster_url(self, obj):
        if not obj.poster:
            return ""
        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.poster.url)
        return obj.poster.url
