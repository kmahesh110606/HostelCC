from django.db import migrations


def seed_item_types(apps, schema_editor):
    ItemType = apps.get_model("checkout", "ItemType")
    defaults = [
        ("mattress", "Mattress", 1),
        ("bucket", "Bucket", 2),
        ("bags_suitcase", "Bags/Suitcase", 3),
        ("carton_box", "Carton Box", 4),
        ("others", "Others", 5),
    ]
    for code, name, order in defaults:
        ItemType.objects.update_or_create(
            code=code,
            defaults={"name": name, "display_order": order, "is_active": True},
        )


def unseed_item_types(apps, schema_editor):
    ItemType = apps.get_model("checkout", "ItemType")
    ItemType.objects.filter(code__in=["mattress", "bucket", "bags_suitcase", "carton_box", "others"]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("checkout", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed_item_types, unseed_item_types),
    ]
