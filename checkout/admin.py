from django.contrib import admin
from .models import (
    ItemType,
    Venue,
    ChairSubmission,
    ClockRoomSubmission,
    SubmissionAuditLog,
)


@admin.register(ItemType)
class ItemTypeAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'is_active', 'display_order']
    list_filter = ['is_active']
    search_fields = ['name', 'code']
    ordering = ['display_order', 'name']


@admin.register(Venue)
class VenueAdmin(admin.ModelAdmin):
    list_display = ['name', 'location', 'item_count', 'max_capacity', 'is_active']
    list_filter = ['is_active']
    search_fields = ['name', 'location']
    readonly_fields = ['item_count', 'created_at', 'updated_at']


@admin.register(ChairSubmission)
class ChairSubmissionAdmin(admin.ModelAdmin):
    list_display = ['student', 'status', 'submitted_at', 'submitted_by_admin']
    list_filter = ['status', 'submitted_at']
    search_fields = ['student__roll_no', 'student__name', 'qr_token']
    readonly_fields = ['qr_token', 'submitted_at']


@admin.register(ClockRoomSubmission)
class ClockRoomSubmissionAdmin(admin.ModelAdmin):
    list_display = ['student', 'item_type', 'current_venue', 'token_number', 'submitted_at']
    list_filter = ['item_type', 'submitted_at', 'current_venue']
    search_fields = ['student__roll_no', 'token_number']
    readonly_fields = ['token_number', 'submitted_at']
    
    fieldsets = (
        ('Student & Item', {
            'fields': ('student', 'item_type', 'chair_submission')
        }),
        ('Venue Information', {
            'fields': ('venue', 'hostel_block', 'current_venue')
        }),
        ('Token Information', {
            'fields': ('token_number', 'qr_code_data')
        }),
        ('Submission Details', {
            'fields': ('submitted_at', 'scanned_by_admin')
        }),
        ('Relocation', {
            'fields': ('relocated_at', 'relocated_by')
        }),
    )


@admin.register(SubmissionAuditLog)
class SubmissionAuditLogAdmin(admin.ModelAdmin):
    list_display = ['student', 'action', 'created_at', 'performed_by']
    list_filter = ['action', 'created_at']
    search_fields = ['student__roll_no', 'performed_by__username']
    readonly_fields = ['created_at', 'details']
