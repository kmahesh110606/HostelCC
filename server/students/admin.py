from django.contrib import admin

from .models import Student


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    list_display = ("roll_no", "name", "block", "room_no", "mess_allotment", "points_balance")
    search_fields = ("roll_no", "name")
    list_filter = ("block", "mess_allotment")
