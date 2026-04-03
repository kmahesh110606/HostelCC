from django.db import migrations, models


MESS_TYPE_CHOICES = [
    ("VEG", "Veg"),
    ("NON_VEG", "Non-Veg"),
    ("SPECIAL", "Special"),
    ("FOODPARK", "Food Park"),
]

WEEK_DAY_CHOICES = [
    ("MON", "Monday"),
    ("TUE", "Tuesday"),
    ("WED", "Wednesday"),
    ("THU", "Thursday"),
    ("FRI", "Friday"),
    ("SAT", "Saturday"),
    ("SUN", "Sunday"),
]


class Migration(migrations.Migration):
    dependencies = [
        ("mess", "0010_prevent_duplicate_rating"),
    ]

    operations = [
        migrations.AddField(
            model_name="caterer",
            name="student_capacity",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.CreateModel(
            name="MessMenuArchive",
            fields=[
                (
                    "id",
                    models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID"),
                ),
                ("archived_month", models.CharField(db_index=True, max_length=7)),
                (
                    "mess_type",
                    models.CharField(
                        choices=MESS_TYPE_CHOICES,
                        db_index=True,
                        default="VEG",
                        max_length=20,
                    ),
                ),
                (
                    "week_day",
                    models.CharField(choices=WEEK_DAY_CHOICES, db_index=True, max_length=3),
                ),
                ("breakfast_items", models.TextField()),
                ("lunch_items", models.TextField()),
                ("snacks_items", models.TextField()),
                ("dinner_items", models.TextField()),
                ("archived_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "ordering": ["-archived_month", "mess_type", "week_day"],
                "unique_together": {("archived_month", "mess_type", "week_day")},
            },
        ),
    ]
