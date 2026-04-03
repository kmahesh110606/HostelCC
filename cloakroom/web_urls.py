from django.urls import path

from .web_views import cloakroom_portal

urlpatterns = [
    path("", cloakroom_portal, name="cloakroom-portal"),
]
