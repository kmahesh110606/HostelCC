from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views

router = DefaultRouter()
router.register(r'item-types', views.ItemTypeViewSet, basename='item-type')
router.register(r'venues', views.VenueViewSet, basename='venue')
router.register(r'chair-submissions', views.ChairSubmissionViewSet, basename='chair-submission')
router.register(r'clock-room-submissions', views.ClockRoomSubmissionViewSet, basename='clock-room-submission')
router.register(r'audit-logs', views.SubmissionAuditLogViewSet, basename='audit-log')

urlpatterns = [
    path('', include(router.urls)),
    path('student/status/', views.StudentCheckoutStatusView.as_view(), name='student-status'),
    path('verify-qr/', views.verify_qr_token, name='verify-qr'),
]
