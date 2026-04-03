from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("students", "0005_student_mess_caterer_assignment"),
    ]

    operations = [
        migrations.CreateModel(
            name="CloakroomEntry",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("token_no", models.PositiveIntegerField(db_index=True, unique=True)),
                ("item_name", models.CharField(max_length=180)),
                ("storage_room_no", models.CharField(max_length=20)),
                ("notes", models.TextField(blank=True)),
                (
                    "status",
                    models.CharField(
                        choices=[("SUBMITTED", "Submitted"), ("RETURNED", "Returned")],
                        db_index=True,
                        default="SUBMITTED",
                        max_length=20,
                    ),
                ),
                ("submitted_at", models.DateTimeField(auto_now_add=True)),
                ("returned_at", models.DateTimeField(blank=True, null=True)),
                (
                    "returned_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=models.deletion.SET_NULL,
                        related_name="cloakroom_returns",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "student",
                    models.ForeignKey(on_delete=models.deletion.CASCADE, related_name="cloakroom_entries", to="students.student"),
                ),
                (
                    "submitted_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=models.deletion.SET_NULL,
                        related_name="cloakroom_submissions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"ordering": ["-submitted_at", "-id"]},
        )
    ]
