from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("hostels", "0001_initial"),
        ("cloakroom", "0002_alter_cloakroomentry_token_no"),
    ]

    operations = [
        migrations.CreateModel(
            name="CloakroomRoom",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("room_no", models.CharField(max_length=10)),
                ("is_active", models.BooleanField(db_index=True, default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "block",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="cloakroom_rooms",
                        to="hostels.hostelblock",
                    ),
                ),
            ],
            options={
                "ordering": ["block__block_name", "room_no"],
                "unique_together": {("block", "room_no")},
            },
        ),
    ]
