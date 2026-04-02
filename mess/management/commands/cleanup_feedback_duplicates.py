from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count

from mess.models import Feedback


class Command(BaseCommand):
    help = "Remove duplicate feedback rows for the same student, menu item, and month."

    def handle(self, *args, **options):
        duplicate_groups = (
            Feedback.objects.values("student_id", "menu_item", "month")
            .annotate(total=Count("id"))
            .filter(total__gt=1)
        )

        duplicate_group_count = duplicate_groups.count()
        if duplicate_group_count == 0:
            self.stdout.write(self.style.SUCCESS("No duplicate feedback rows found."))
            return

        ids_to_delete = []
        for group in duplicate_groups.iterator():
            group_ids = list(
                Feedback.objects.filter(
                    student_id=group["student_id"],
                    menu_item=group["menu_item"],
                    month=group["month"],
                )
                .order_by("created_at", "id")
                .values_list("id", flat=True)
            )
            if len(group_ids) > 1:
                ids_to_delete.extend(group_ids[1:])

        with transaction.atomic():
            deleted_count, _ = Feedback.objects.filter(id__in=ids_to_delete).delete()

        self.stdout.write(
            self.style.WARNING(
                f"Removed {deleted_count} duplicate feedback rows across {duplicate_group_count} duplicate groups."
            )
        )