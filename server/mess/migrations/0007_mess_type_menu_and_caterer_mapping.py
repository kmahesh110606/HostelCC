from django.db import migrations, models


MESS_TYPES = ("VEG", "NON_VEG", "SPECIAL", "FOODPARK")

BLOCK_MESS_CATERERS = {
    "A": {
        "VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Proodle Hospitality",
            "Grace Caterers",
        ],
        "NON_VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Grace Caterers",
        ],
        "SPECIAL": ["Fusion Catering Services", "Grace Caterers"],
        "FOODPARK": ["Rassence Catering", "Proodle Hospitality"],
    },
    "D1": {
        "VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Proodle Hospitality",
            "Grace Caterers",
        ],
        "NON_VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Grace Caterers",
        ],
        "SPECIAL": ["Fusion Catering Services", "Grace Caterers"],
        "FOODPARK": ["Rassence Catering", "Proodle Hospitality"],
    },
    "D2": {
        "VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Proodle Hospitality",
            "Grace Caterers",
        ],
        "NON_VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Grace Caterers",
        ],
        "SPECIAL": ["Fusion Catering Services", "Grace Caterers"],
        "FOODPARK": ["Rassence Catering", "Proodle Hospitality"],
    },
    "C": {
        "VEG": ["SRRC Catering Services", "Zenith Food Services"],
        "NON_VEG": ["SRRC Catering Services", "Zenith Food Services"],
        "SPECIAL": ["SRRC Catering Services"],
        "FOODPARK": ["Zenith Food Services"],
    },
    "E": {
        "VEG": ["J Sathya P R Food and Hospitality Services"],
        "NON_VEG": ["J Sathya P R Food and Hospitality Services"],
        "SPECIAL": ["J Sathya P R Food and Hospitality Services"],
    },
}


def _seed_menu_and_caterers(apps, schema_editor):
    MessMenu = apps.get_model("mess", "MessMenu")
    Caterer = apps.get_model("mess", "Caterer")
    HostelBlock = apps.get_model("hostels", "HostelBlock")

    snapshot = {}
    for row in MessMenu.objects.all():
        if row.week_day not in snapshot:
            snapshot[row.week_day] = {
                "breakfast_items": row.breakfast_items,
                "lunch_items": row.lunch_items,
                "snacks_items": row.snacks_items,
                "dinner_items": row.dinner_items,
            }

    MessMenu.objects.all().delete()
    for week_day, defaults in snapshot.items():
        for mess_type in MESS_TYPES:
            MessMenu.objects.create(mess_type=mess_type, week_day=week_day, **defaults)

    blocks = {}
    for block_name in ["A", "B", "C", "D1", "D2", "E"]:
        block, _ = HostelBlock.objects.get_or_create(block_name=block_name)
        blocks[block_name] = block

    Caterer.objects.all().delete()
    for block_name, by_type in BLOCK_MESS_CATERERS.items():
        for mess_type, names in by_type.items():
            for name in names:
                Caterer.objects.create(name=name, meal_types=mess_type, block=blocks[block_name])


def _noop_reverse(apps, schema_editor):
    return


def _clear_legacy_caterers(apps, schema_editor):
    Caterer = apps.get_model("mess", "Caterer")
    Caterer.objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0006_feedback_meal_time_feedback_week_day"),
    ]

    operations = [
        migrations.AddField(
            model_name="messmenu",
            name="mess_type",
            field=models.CharField(
                choices=[
                    ("VEG", "Veg"),
                    ("NON_VEG", "Non-Veg"),
                    ("SPECIAL", "Special"),
                    ("FOODPARK", "Food Park"),
                ],
                db_index=True,
                default="VEG",
                max_length=20,
            ),
        ),
        migrations.AlterField(
            model_name="messmenu",
            name="week_day",
            field=models.CharField(
                choices=[
                    ("MON", "Monday"),
                    ("TUE", "Tuesday"),
                    ("WED", "Wednesday"),
                    ("THU", "Thursday"),
                    ("FRI", "Friday"),
                    ("SAT", "Saturday"),
                    ("SUN", "Sunday"),
                ],
                db_index=True,
                max_length=3,
            ),
        ),
        migrations.AlterUniqueTogether(
            name="messmenu",
            unique_together={("mess_type", "week_day")},
        ),
        migrations.RunPython(_clear_legacy_caterers, _noop_reverse),
        migrations.AlterField(
            model_name="caterer",
            name="meal_types",
            field=models.CharField(
                choices=[
                    ("VEG", "Veg"),
                    ("NON_VEG", "Non-Veg"),
                    ("SPECIAL", "Special"),
                    ("FOODPARK", "Food Park"),
                ],
                max_length=20,
            ),
        ),
        migrations.AlterUniqueTogether(
            name="caterer",
            unique_together={("name", "block", "meal_types")},
        ),
        migrations.RunPython(_seed_menu_and_caterers, _noop_reverse),
    ]
