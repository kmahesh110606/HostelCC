from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    FirstTimePasswordSetupView,
    HealthView,
    LoginView,
    RequestOTPView,
    VerifyOTPView,
)

urlpatterns = [
    path("login", LoginView.as_view(), name="api-login"),
    path("refresh", TokenRefreshView.as_view(), name="token-refresh"),
    path("health", HealthView.as_view(), name="health"),
    path("request-otp", RequestOTPView.as_view(), name="request-otp"),
    path("verify-otp", VerifyOTPView.as_view(), name="verify-otp"),
    path("first-time-password", FirstTimePasswordSetupView.as_view(), name="first-time-password"),
]
