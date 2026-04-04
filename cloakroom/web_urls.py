from django.urls import path

from .web_views import cloakroom_admin, cloakroom_portal

urlpatterns = [
    path("", cloakroom_portal, name="cloakroom-portal"),
    path("admin/", cloakroom_admin, name="cloakroom-admin"),
]
