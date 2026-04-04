from django.contrib import admin

from .models import CloakroomEntry, CloakroomRoom


@admin.register(CloakroomRoom)
class CloakroomRoomAdmin(admin.ModelAdmin):
    list_display = ("block", "room_no", "is_active", "created_at")
    list_filter = ("block", "is_active")
    search_fields = ("room_no", "block__block_name")
    ordering = ("block__block_name", "room_no")


@admin.register(CloakroomEntry)
class CloakroomEntryAdmin(admin.ModelAdmin):
    list_display = (
        "token_no",
        "student",
        "item_name",
        "storage_room_no",
        "status",
        "submitted_at",
        "returned_at",
    )
    search_fields = ("token_no", "student__roll_no", "student__name", "item_name", "storage_room_no")
    list_filter = ("status", "student__block")
