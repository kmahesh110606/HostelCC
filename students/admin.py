from django.contrib import admin
from django import forms

from mess.models import Caterer

from .models import Student


class StudentAdminForm(forms.ModelForm):
    class Meta:
        model = Student
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        block_id = None
        if self.is_bound:
            raw_block = (self.data.get("block") or "").strip()
            if raw_block:
                try:
                    block_id = int(raw_block)
                except ValueError:
                    block_id = None
        elif self.instance and self.instance.block_id:
            block_id = self.instance.block_id

        if block_id:
            self.fields["mess_caterer"].queryset = Caterer.objects.filter(block_id=block_id).order_by("name")
        else:
            self.fields["mess_caterer"].queryset = Caterer.objects.none()

        self.fields["mess_caterer"].help_text = "Choose one caterer from the selected block."


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    form = StudentAdminForm
    list_display = (
        "roll_no",
        "name",
        "block",
        "room_no",
        "mess_caterer",
        "mess_allotment",
        "mess_change_unlocked",
    )
    search_fields = ("roll_no", "name", "mess_caterer__name")
    list_filter = ("block", "mess_caterer", "mess_allotment", "mess_change_unlocked")
    actions = ["unlock_mess_changes", "lock_mess_changes"]

    def unlock_mess_changes(self, request, queryset):
        updated = queryset.update(mess_change_unlocked=True)
        self.message_user(request, f"Unlocked mess change for {updated} student(s).")

    unlock_mess_changes.short_description = "Unlock mess change for selected students"

    def lock_mess_changes(self, request, queryset):
        updated = queryset.update(mess_change_unlocked=False)
        self.message_user(request, f"Locked mess change for {updated} student(s).")

    lock_mess_changes.short_description = "Lock mess change for selected students"
