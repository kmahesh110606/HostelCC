from django.core.management.base import BaseCommand
from django.db import connection


class Command(BaseCommand):
    help = "Remove duplicate feedback rows for the same student, menu item, and month."

    def handle(self, *args, **options):
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT COUNT(*)
                FROM (
                    SELECT student_id, menu_item, month
                    FROM mess_feedback
                    GROUP BY student_id, menu_item, month
                    HAVING COUNT(*) > 1
                ) duplicate_groups
                """
            )
            before_groups = int(cursor.fetchone()[0])

            if before_groups == 0:
                self.stdout.write(self.style.SUCCESS("No duplicate feedback rows found."))
                return

            cursor.execute(
                """
                DELETE FROM mess_feedback a
                USING mess_feedback b
                WHERE a.id > b.id
                  AND a.student_id = b.student_id
                  AND a.menu_item = b.menu_item
                  AND a.month = b.month
                """
            )
            deleted_count = cursor.rowcount

            cursor.execute(
                """
                SELECT COUNT(*)
                FROM (
                    SELECT student_id, menu_item, month
                    FROM mess_feedback
                    GROUP BY student_id, menu_item, month
                    HAVING COUNT(*) > 1
                ) duplicate_groups
                """
            )
            after_groups = int(cursor.fetchone()[0])

        self.stdout.write(
            self.style.WARNING(
                f"Removed {deleted_count} duplicate feedback rows. Duplicate groups: {before_groups} -> {after_groups}."
            )
        )