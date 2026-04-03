from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("students", "0005_student_mess_caterer_assignment"),
    ]

    operations = [
        migrations.AddField(
            model_name="student",
            name="cloakroom_unlocked",
            field=models.BooleanField(default=False),
        ),
    ]
