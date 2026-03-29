from django.urls import path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    AppNotificationViewSet,
    ChangePasswordView,
    FirstTimePasswordSetupView,
    HealthView,
    LoginView,
    MeView,
    RequestOTPView,
    SignupCompleteView,
    SignupOptionsView,
    SignupRequestOTPView,
    VerifyOTPView,
)

router = DefaultRouter()
router.register("notifications", AppNotificationViewSet, basename="app-notifications")

urlpatterns = [
    path("login", LoginView.as_view(), name="api-login"),
    path("login/", LoginView.as_view(), name="api-login-slash"),
    path("refresh", TokenRefreshView.as_view(), name="token-refresh"),
    path("refresh/", TokenRefreshView.as_view(), name="token-refresh-slash"),
    path("health", HealthView.as_view(), name="health"),
    path("health/", HealthView.as_view(), name="health-slash"),
    path("me", MeView.as_view(), name="auth-me"),
    path("me/", MeView.as_view(), name="auth-me-slash"),
    path("request-otp", RequestOTPView.as_view(), name="request-otp"),
    path("request-otp/", RequestOTPView.as_view(), name="request-otp-slash"),
    path("signup/request-otp", SignupRequestOTPView.as_view(), name="signup-request-otp"),
    path("signup/request-otp/", SignupRequestOTPView.as_view(), name="signup-request-otp-slash"),
    path("signup/options", SignupOptionsView.as_view(), name="signup-options"),
    path("signup/options/", SignupOptionsView.as_view(), name="signup-options-slash"),
    path("signup/complete", SignupCompleteView.as_view(), name="signup-complete"),
    path("signup/complete/", SignupCompleteView.as_view(), name="signup-complete-slash"),
    path("verify-otp", VerifyOTPView.as_view(), name="verify-otp"),
    path("verify-otp/", VerifyOTPView.as_view(), name="verify-otp-slash"),
    path("first-time-password", FirstTimePasswordSetupView.as_view(), name="first-time-password"),
    path("first-time-password/", FirstTimePasswordSetupView.as_view(), name="first-time-password-slash"),
    path("change-password", ChangePasswordView.as_view(), name="change-password"),
    path("change-password/", ChangePasswordView.as_view(), name="change-password-slash"),
]

urlpatterns += router.urls
