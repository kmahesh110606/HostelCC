# Generated migration to prevent duplicate ratings per student per menu item per month

from django.db import migrations


def deduplicate_feedback(apps, schema_editor):
    Feedback = apps.get_model("mess", "Feedback")

    duplicates = (
        Feedback.objects.values("id", "student_id", "menu_item", "month")
        .order_by("student_id", "menu_item", "month", "created_at", "id")
    )

    seen_keys = set()
    duplicate_ids = []

    for row in duplicates.iterator():
        key = (row["student_id"], row["menu_item"], row["month"])
        if key in seen_keys:
            duplicate_ids.append(row["id"])
        else:
            seen_keys.add(key)

    if duplicate_ids:
        Feedback.objects.filter(id__in=duplicate_ids).delete()


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
