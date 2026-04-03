from django.urls import path

from .web_views import (
    download_laundry_logs_csv,
    download_laundry_schedule_csv,
    download_laundry_token_tags,
    laundry_portal,
)

urlpatterns = [
    path("", laundry_portal, name="laundry-portal"),
    path("exports/logs.csv", download_laundry_logs_csv, name="laundry-export-logs"),
    path("exports/logs.csv/", download_laundry_logs_csv, name="laundry-export-logs-slash"),
    path("exports/day-schedule.csv", download_laundry_schedule_csv, name="laundry-export-day-schedule"),
    path("exports/day-schedule.csv/", download_laundry_schedule_csv, name="laundry-export-day-schedule-slash"),
    path("exports/token-tags.html", download_laundry_token_tags, name="laundry-export-token-tags"),
    path("exports/token-tags.html/", download_laundry_token_tags, name="laundry-export-token-tags-slash"),
]
