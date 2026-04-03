from django.contrib import admin

from .models import DisciplineCase


@admin.register(DisciplineCase)
class DisciplineCaseAdmin(admin.ModelAdmin):
    list_display = (
        "student",
        "violation_code",
        "occurrence_number",
        "id_card_confiscated_at",
        "id_card_returned_at",
        "created_by",
        "returned_by",
    )
    list_filter = ("violation_code", "id_card_returned_at", "created_at")
    search_fields = ("student__roll_no", "student__name", "notes", "action_taken")
