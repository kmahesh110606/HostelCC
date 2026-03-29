from django.urls import path

from .web_views import laundry_portal

urlpatterns = [
    path("", laundry_portal, name="laundry-portal"),
]
