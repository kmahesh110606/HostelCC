from django.contrib import admin

from .models import HostelBlock, Room


@admin.register(HostelBlock)
class HostelBlockAdmin(admin.ModelAdmin):
    list_display = ("id", "block_name")
    search_fields = ("block_name",)


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ("id", "room_no", "block", "capacity")
    search_fields = ("room_no",)
    list_filter = ("block",)
