from django.contrib import admin

from .models import Caterer, Feedback, MenuPollOption, MenuPollVote, MessChangeRequest, MessMenu


@admin.register(MessMenu)
class MessMenuAdmin(admin.ModelAdmin):
    list_display = ("week_day",)
    search_fields = ("week_day",)


@admin.register(Caterer)
class CatererAdmin(admin.ModelAdmin):
    list_display = ("name", "block", "meal_types")
    list_filter = ("block",)
    search_fields = ("name", "meal_types")


@admin.register(Feedback)
class FeedbackAdmin(admin.ModelAdmin):
    list_display = ("student", "menu_item", "rating", "month", "created_at")
    list_filter = ("month", "rating")


@admin.register(MenuPollOption)
class MenuPollOptionAdmin(admin.ModelAdmin):
    list_display = ("month", "item_name")


@admin.register(MenuPollVote)
class MenuPollVoteAdmin(admin.ModelAdmin):
    list_display = ("student", "option", "created_at")


@admin.register(MessChangeRequest)
class MessChangeRequestAdmin(admin.ModelAdmin):
    list_display = ("student", "requested_mess", "month", "status")
    list_filter = ("status", "month")
