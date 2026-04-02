# Generated migration to prevent duplicate ratings per student per menu item per month

from django.db import migrations


def deduplicate_feedback(apps, schema_editor):
    Feedback = apps.get_model("mess", "Feedback")
    table_name = schema_editor.quote_name(Feedback._meta.db_table)

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
