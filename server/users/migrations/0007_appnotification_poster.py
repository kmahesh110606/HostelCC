from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0006_appnotification"),
    ]

    operations = [
        migrations.AddField(
            model_name="appnotification",
            name="poster",
            field=models.FileField(blank=True, upload_to="notification_posters/"),
        ),
    ]
