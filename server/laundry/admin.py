from django.contrib import admin

from .models import LaundryEvent, LaundrySchedule


@admin.register(LaundrySchedule)
class LaundryScheduleAdmin(admin.ModelAdmin):
    list_display = ("student", "day_of_week", "submission_status", "collection_status", "due_collection_by")
    search_fields = ("student__roll_no", "student__name")


@admin.register(LaundryEvent)
class LaundryEventAdmin(admin.ModelAdmin):
    list_display = ("student", "event_type", "scanned_by", "created_at")
    list_filter = ("event_type",)
