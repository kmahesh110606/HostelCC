from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import OTPChallenge

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email", "role", "first_name", "last_name"]


class RoleAwareTokenSerializer(TokenObtainPairSerializer):
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token["role"] = user.role
        token["username"] = user.username
        token["must_change_password"] = user.must_change_password
        return token


class OTPRequestSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)


class OTPVerifySerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    otp_code = serializers.CharField(max_length=6)


class FirstTimePasswordSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    otp_code = serializers.CharField(max_length=6)
    new_password = serializers.CharField(min_length=8)

    def validate(self, attrs):
        user = User.objects.filter(username=attrs["username"]).first()
        if not user:
            raise serializers.ValidationError("User does not exist.")

        challenge = OTPChallenge.objects.filter(user=user, consumed=False).order_by("-created_at").first()
        if not challenge or not challenge.is_valid_code(attrs["otp_code"]):
            raise serializers.ValidationError("OTP is invalid or expired.")

        attrs["user"] = user
        attrs["challenge"] = challenge
        return attrs
