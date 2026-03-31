from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import AppNotification, User


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (("Role", {"fields": ("role",)}),)
    list_display = ("username", "email", "role", "is_staff", "is_active")
    list_filter = ("role", "is_staff", "is_superuser", "is_active")


@admin.register(AppNotification)
class AppNotificationAdmin(admin.ModelAdmin):
    list_display = ("title", "level", "audience", "is_active", "created_at")
    list_filter = ("level", "audience", "is_active")
    search_fields = ("title", "message")
