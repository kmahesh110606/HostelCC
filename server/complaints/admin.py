from django.contrib import admin

from .models import Complaint, ComplaintReply


class ComplaintReplyInline(admin.TabularInline):
    model = ComplaintReply
    extra = 0


@admin.register(Complaint)
class ComplaintAdmin(admin.ModelAdmin):
    list_display = ("student", "category", "status", "created_at")
    list_filter = ("category", "status")
    search_fields = ("student__roll_no", "text")
    inlines = [ComplaintReplyInline]
