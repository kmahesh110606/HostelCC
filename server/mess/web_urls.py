from django.urls import path

from .web_views import mess_portal

urlpatterns = [
    path("", mess_portal, name="mess-portal"),
]
