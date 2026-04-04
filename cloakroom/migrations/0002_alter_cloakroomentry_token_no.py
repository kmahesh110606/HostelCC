from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("cloakroom", "0001_initial"),
    ]

    operations = [
        migrations.AlterField(
            model_name="cloakroomentry",
            name="token_no",
            field=models.PositiveIntegerField(db_index=True),
        ),
    ]
