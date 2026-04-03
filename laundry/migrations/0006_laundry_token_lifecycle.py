from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("laundry", "0005_laundryholiday"),
    ]

    operations = [
        migrations.AddField(
            model_name="laundryschedule",
            name="assigned_token_code",
            field=models.CharField(blank=True, default="", max_length=40),
        ),
        migrations.AddField(
            model_name="laundryschedule",
            name="laundry_done_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="laundryschedule",
            name="token_assigned_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="laundryevent",
            name="event_type",
            field=models.CharField(
                choices=[
                    ("SUBMISSION", "Submission"),
                    ("COMPLETE", "Completed"),
                    ("COLLECTION", "Collection"),
                ],
                max_length=12,
            ),
        ),
    ]
