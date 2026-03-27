from django.urls import path

from .web_views import community_feed, community_rules

urlpatterns = [
    path("", community_feed, name="community-feed"),
    path("rules/", community_rules, name="community-rules"),
]
