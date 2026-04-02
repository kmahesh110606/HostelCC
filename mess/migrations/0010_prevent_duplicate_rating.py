# Generated migration to prevent duplicate ratings per student per menu item per month

from django.db import migrations


def deduplicate_feedback(apps, schema_editor):
    Feedback = apps.get_model("mess", "Feedback")
    table_name = schema_editor.quote_name(Feedback._meta.db_table)

    # Prevent concurrent writes from re-introducing duplicates during migration.
    schema_editor.execute(f"LOCK TABLE {table_name} IN ACCESS EXCLUSIVE MODE")

    schema_editor.execute(
        f"""
        DELETE FROM {table_name}
        WHERE id IN (
            SELECT id
            FROM (
                SELECT
                    id,
                    ROW_NUMBER() OVER (
                        PARTITION BY student_id, menu_item, month
                        ORDER BY created_at ASC, id ASC
                    ) AS row_number
                FROM {table_name}
            ) duplicate_rows
            WHERE row_number > 1
        )
        """
    )

    with schema_editor.connection.cursor() as cursor:
        cursor.execute(
            f"""
            SELECT COUNT(*)
            FROM (
                SELECT student_id, menu_item, month
                FROM {table_name}
                GROUP BY student_id, menu_item, month
                HAVING COUNT(*) > 1
            ) duplicate_groups
            """
        )
        remaining = int(cursor.fetchone()[0])

    if remaining:
        raise RuntimeError(
            "Duplicate feedback rows still exist after cleanup; cannot apply unique constraint."
        )


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0009_performance_indexes"),
    ]

    operations = [
        migrations.RunPython(deduplicate_feedback, migrations.RunPython.noop),
        migrations.AlterUniqueTogether(
            name="feedback",
            unique_together={("student", "menu_item", "month")},
        ),
    ]
