from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0005_rename_users_otpch_user_id_00f04a_idx_users_otpch_user_id_ba3a2c_idx"),
    ]

    operations = [
        migrations.CreateModel(
            name="AppNotification",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("title", models.CharField(max_length=140)),
                ("message", models.TextField()),
                (
                    "level",
                    models.CharField(
                        choices=[("INFO", "Info"), ("WARNING", "Warning"), ("URGENT", "Urgent")],
                        default="INFO",
                        max_length=10,
                    ),
                ),
                (
                    "audience",
                    models.CharField(
                        choices=[
                            ("ALL", "All"),
                            ("STUDENT", "Student"),
                            ("WARDEN", "Warden"),
                            ("MESS_MANAGER", "Mess Manager"),
                            ("LAUNDRY_PERSON", "Laundry Manager"),
                            ("ADMIN", "Admin"),
                        ],
                        default="ALL",
                        max_length=20,
                    ),
                ),
                ("is_active", models.BooleanField(default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "created_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="created_notifications",
                        to="users.user",
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
    ]
