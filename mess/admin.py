from django.contrib import admin
from django.utils import timezone
from django.utils.html import format_html

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu, MessMenuArchive


@admin.register(MessMenu)
class MessMenuAdmin(admin.ModelAdmin):
    list_display = ("mess_type", "week_day")
    search_fields = ("mess_type", "week_day")
    list_filter = ("mess_type",)
    actions = ["archive_selected_menus"]

    def archive_selected_menus(self, request, queryset):
        archived_month = timezone.localdate().strftime("%Y-%m")
        archived_count = 0

        for menu in queryset:
            _, created = MessMenuArchive.objects.update_or_create(
                archived_month=archived_month,
                mess_type=menu.mess_type,
                week_day=menu.week_day,
                defaults={
                    "breakfast_items": menu.breakfast_items,
                    "lunch_items": menu.lunch_items,
                    "snacks_items": menu.snacks_items,
                    "dinner_items": menu.dinner_items,
                },
            )
            archived_count += 1

        self.message_user(
            request,
            format_html(
                "Archived <strong>{}</strong> menu row(s) into <strong>{}</strong>.",
                archived_count,
                archived_month,
            ),
        )

    archive_selected_menus.short_description = "Archive selected menu rows for the current month"


@admin.register(Caterer)
class CatererAdmin(admin.ModelAdmin):
    list_display = ("name", "block", "meal_types", "student_capacity")
    list_filter = ("block", "meal_types")
    search_fields = ("name", "meal_types")


@admin.register(MessMenuArchive)
class MessMenuArchiveAdmin(admin.ModelAdmin):
    list_display = ("archived_month", "mess_type", "week_day", "archived_at")
    list_filter = ("archived_month", "mess_type", "week_day")
    search_fields = ("archived_month", "mess_type", "week_day")
    readonly_fields = ("archived_month", "mess_type", "week_day", "breakfast_items", "lunch_items", "snacks_items", "dinner_items", "archived_at")


@admin.register(Feedback)
class FeedbackAdmin(admin.ModelAdmin):
    list_display = ("student", "week_day", "meal_time", "menu_item", "rating", "month", "created_at")
    list_filter = ("month", "week_day", "meal_time", "rating")


@admin.register(MenuPollOption)
class MenuPollOptionAdmin(admin.ModelAdmin):
    list_display = ("month", "item_name", "poll_type", "vote_count")
    list_filter = ("month", "poll_type")
    search_fields = ("item_name",)

    def vote_count(self, obj):
        return obj.votes.count()
    vote_count.short_description = "Votes"


@admin.register(MenuPollVote)
class MenuPollVoteAdmin(admin.ModelAdmin):
    list_display = ("student", "option", "created_at")
    list_filter = ("created_at", "option__month")
    search_fields = ("student__roll_no", "student__name", "option__item_name")
    actions = ["reset_poll_votes_by_month"]

    def reset_poll_votes_by_month(self, request, queryset):
        """Reset (delete) all poll votes for a specific month to free up DB space."""
        # Get unique months from the queryset
        months = queryset.values_list("option__month", flat=True).distinct()
        deleted_count = 0
        for month in months:
            deleted, _ = MenuPollVote.objects.filter(option__month=month).delete()
            deleted_count += deleted
        
        self.message_user(
            request,
            format_html(
                "✓ Deleted <strong>{}</strong> poll votes and associated poll options for {}. "
                "Students can now vote again for the next month.",
                deleted_count,
                ", ".join(months),
            ),
        )
    reset_poll_votes_by_month.short_description = "Reset poll votes for selected month(s)"


@admin.register(MessChangeRequest)
class MessChangeRequestAdmin(admin.ModelAdmin):
    list_display = ("student", "requested_mess", "month", "status")
    list_filter = ("status", "month")

