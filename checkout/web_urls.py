from django.urls import path
from . import web_views

urlpatterns = [
    path('admin/', web_views.admin_dashboard, name='checkout-admin-dashboard'),
    path('admin/chair-scanner/', web_views.chair_scanner, name='chair-scanner'),
    path('admin/item-scanner/<str:item_type>/', web_views.item_scanner, name='item-scanner'),
    path('admin/submissions/', web_views.submissions_list, name='submissions-list'),
    path('admin/venues/', web_views.venue_management, name='venue-management'),
    path('student/', web_views.student_portal, name='checkout-student-portal'),
]
