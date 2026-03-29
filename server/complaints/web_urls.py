from django.urls import path

from .web_views import community_feed, community_rules, download_active_complaints_csv

urlpatterns = [
    path("", community_feed, name="community-feed"),
    path("rules/", community_rules, name="community-rules"),
    path("exports/active.csv", download_active_complaints_csv, name="complaints-export-active"),
    path("exports/active.csv/", download_active_complaints_csv, name="complaints-export-active-slash"),
]
