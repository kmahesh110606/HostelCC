from django.contrib import admin
from django.db.models import Avg, Count
from django.utils import timezone
from django.utils.html import format_html

from .models import (
    Caterer,
    Feedback,
    MenuPollOption,
    MenuPollVote,
    MessChangeRequest,
    MessMenu,
    MessMenuArchive,
    MessMonthlyArchive,
    NightMessLog,
)


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
    actions = ["archive_feedback_trends_by_month"]

    def archive_feedback_trends_by_month(self, request, queryset):
        months = list(queryset.values_list("month", flat=True).distinct())
        archived_months = []

        for month in months:
            month_feedback = Feedback.objects.filter(month=month)
            trends = list(
                month_feedback.values("menu_item", "week_day", "meal_time")
                .annotate(avg_rating=Avg("rating"), total_votes=Count("id"))
                .order_by("-avg_rating", "-total_votes", "menu_item")
            )
            snapshot = {
                "month": month,
                "kind": "FEEDBACK",
                "trends": trends,
                "total_feedback": month_feedback.count(),
                "archived_at": timezone.now().isoformat(),
            }
            MessMonthlyArchive.objects.update_or_create(
                month=month,
                kind=MessMonthlyArchive.Kind.FEEDBACK,
                defaults={"payload": snapshot},
            )
            month_feedback.delete()
            archived_months.append(month)

        self.message_user(
            request,
            format_html(
                "Archived feedback trends for <strong>{}</strong> and cleared the live month data.",
                ", ".join(archived_months) if archived_months else "no months",
            ),
        )

    archive_feedback_trends_by_month.short_description = "Archive feedback trends for selected month(s) and reset live feedback"


@admin.register(MenuPollOption)
class MenuPollOptionAdmin(admin.ModelAdmin):
    list_display = ("month", "item_name", "poll_type", "vote_count")
    list_filter = ("month", "poll_type")
    search_fields = ("item_name",)
    actions = ["archive_poll_trends_by_month"]

    def vote_count(self, obj):
        return obj.votes.count()
    vote_count.short_description = "Votes"

    def archive_poll_trends_by_month(self, request, queryset):
        months = list(queryset.values_list("month", flat=True).distinct())
        archived_months = []

        for month in months:
            options = MenuPollOption.objects.filter(month=month).annotate(vote_count=Count("votes"))
            snapshot = {
                "month": month,
                "kind": "POLL",
                "options": [
                    {
                        "item_name": option.item_name,
                        "poll_type": option.poll_type,
                        "votes": option.vote_count,
                    }
                    for option in options
                ],
                "total_options": options.count(),
                "archived_at": timezone.now().isoformat(),
            }
            MessMonthlyArchive.objects.update_or_create(
                month=month,
                kind=MessMonthlyArchive.Kind.POLL,
                defaults={"payload": snapshot},
            )
            MenuPollVote.objects.filter(option__month=month).delete()
            options.delete()
            archived_months.append(month)

        self.message_user(
            request,
            format_html(
                "Archived poll trends for <strong>{}</strong> and reset the live poll tables.",
                ", ".join(archived_months) if archived_months else "no months",
            ),
        )

    archive_poll_trends_by_month.short_description = "Archive poll trends for selected month(s) and reset live polls"


@admin.register(MenuPollVote)
class MenuPollVoteAdmin(admin.ModelAdmin):
    list_display = ("student", "option", "created_at")
    list_filter = ("created_at", "option__month")
    search_fields = ("student__roll_no", "student__name", "option__item_name")
    actions = ["reset_poll_votes_by_month"]

    def reset_poll_votes_by_month(self, request, queryset):
        """Archive poll snapshot data and delete live poll votes/options for selected month(s)."""
        months = list(queryset.values_list("option__month", flat=True).distinct())
        deleted_count = 0
        for month in months:
            options = MenuPollOption.objects.filter(month=month).annotate(vote_count=Count("votes"))
            snapshot = {
                "month": month,
                "kind": "POLL",
                "options": [
                    {
                        "item_name": option.item_name,
                        "poll_type": option.poll_type,
                        "votes": option.vote_count,
                    }
                    for option in options
                ],
                "total_options": options.count(),
                "archived_at": timezone.now().isoformat(),
            }
            MessMonthlyArchive.objects.update_or_create(
                month=month,
                kind=MessMonthlyArchive.Kind.POLL,
                defaults={"payload": snapshot},
            )
            deleted_votes, _ = MenuPollVote.objects.filter(option__month=month).delete()
            deleted_options, _ = options.delete()
            deleted_count += deleted_votes + deleted_options
        
        self.message_user(
            request,
            format_html(
                "Archived poll trends and deleted <strong>{}</strong> poll rows for {}. "
                "Students can now vote again for the next month.",
                deleted_count,
                ", ".join(months) if months else "no months",
            ),
        )
    reset_poll_votes_by_month.short_description = "Archive and reset poll votes for selected month(s)"


@admin.register(MessMonthlyArchive)
class MessMonthlyArchiveAdmin(admin.ModelAdmin):
    list_display = ("month", "kind", "archived_at")
    list_filter = ("kind", "month")
    search_fields = ("month", "kind")
    readonly_fields = ("month", "kind", "payload", "archived_at")


@admin.register(MessChangeRequest)
class MessChangeRequestAdmin(admin.ModelAdmin):
    list_display = ("student", "requested_mess", "month", "status")
    list_filter = ("status", "month")


@admin.register(NightMessLog)
class NightMessLogAdmin(admin.ModelAdmin):
    list_display = (
        "student",
        "checked_out_at",
        "returned_at",
        "checked_out_by",
        "returned_by",
        "is_overdue_display",
    )
    list_filter = ("checked_out_at", "returned_at")
    search_fields = ("student__roll_no", "student__name", "student__room_no", "student__block__block_name")
    readonly_fields = ("checked_out_at", "returned_at")

    def is_overdue_display(self, obj: NightMessLog) -> bool:
        return obj.is_overdue

    is_overdue_display.boolean = True
    is_overdue_display.short_description = "Overdue (> 1:00 AM)"

