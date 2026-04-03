from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0012_messmonthlyarchive"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="NightMessLog",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("checked_out_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("returned_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                (
                    "checked_out_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="night_mess_checkout_logs",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "returned_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="night_mess_return_logs",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "student",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="night_mess_logs",
                        to="students.student",
                    ),
                ),
            ],
            options={
                "ordering": ["-checked_out_at"],
            },
        ),
        migrations.AddIndex(
            model_name="nightmesslog",
            index=models.Index(fields=["student", "-checked_out_at"], name="night_mess_student_ct_idx"),
        ),
        migrations.AddIndex(
            model_name="nightmesslog",
            index=models.Index(fields=["returned_at", "-checked_out_at"], name="night_mess_return_ct_idx"),
        ),
    ]
