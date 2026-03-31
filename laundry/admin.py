from django.contrib import admin

from .models import LaundryEvent, LaundryRoomRange, LaundrySchedule


@admin.register(LaundrySchedule)
class LaundryScheduleAdmin(admin.ModelAdmin):
    list_display = ("student", "day_of_week", "submission_status", "collection_status", "due_collection_by")
    search_fields = ("student__roll_no", "student__name")


@admin.register(LaundryEvent)
class LaundryEventAdmin(admin.ModelAdmin):
    list_display = ("student", "event_type", "scanned_by", "created_at")
    list_filter = ("event_type",)


@admin.register(LaundryRoomRange)
class LaundryRoomRangeAdmin(admin.ModelAdmin):
    list_display = ("block_name", "day_of_week", "room_from", "room_to", "is_active")
    list_filter = ("block_name", "day_of_week", "is_active")
    search_fields = ("block_name", "room_from", "room_to")
