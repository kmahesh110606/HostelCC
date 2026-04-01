from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("complaints", "0006_add_complaint_indexes"),
    ]

    operations = [
        migrations.AlterField(
            model_name="complaint",
            name="text",
            field=models.TextField(blank=True, default=""),
        ),
    ]
