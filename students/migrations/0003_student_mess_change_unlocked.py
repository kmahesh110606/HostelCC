from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("students", "0002_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="student",
            name="mess_change_unlocked",
            field=models.BooleanField(default=False),
        ),
    ]
