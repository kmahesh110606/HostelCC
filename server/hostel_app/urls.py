from django.contrib import admin
from django.conf import settings
from django.conf.urls.static import static
from django.urls import include, path
from hostel_app.views import healthz

from users.web_views import (
    dashboard_router,
    forgot_password,
    home,
    notification_panel,
    profile_page,
    role_login,
    web_logout,
    welcome_page,
)

urlpatterns = [
    path("healthz/", healthz, name="healthz"),
    path("admin/", admin.site.urls),
    path("accounts/login/", role_login, name="login"),
    path("accounts/forgot-password/", forgot_password, name="forgot-password"),
    path("accounts/change-password/", forgot_password, name="profile-change-password"),
    path("accounts/logout/", web_logout, name="logout"),
    path("accounts/", include("django.contrib.auth.urls")),
    path("welcome/", welcome_page, name="welcome"),
    path("profile/", profile_page, name="profile"),
    path("community/", include("complaints.web_urls")),
    path("mess/", include("mess.web_urls")),
    path("laundry/", include("laundry.web_urls")),
    path("notifications/", notification_panel, name="notification-panel"),
    path("", home, name="home"),
    path("dashboard/", dashboard_router, name="dashboard-router"),
    path("api/auth/", include("users.urls")),
    path("api/hostels/", include("hostels.urls")),
    path("api/students/", include("students.urls")),
    path("api/laundry/", include("laundry.urls")),
    path("api/mess/", include("mess.urls")),
    path("api/complaints/", include("complaints.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
