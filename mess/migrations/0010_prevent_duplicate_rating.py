# Generated migration to prevent duplicate ratings per student per menu item per month

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0009_performance_indexes"),
    ]

    operations = [
        migrations.AlterUniqueTogether(
            name="feedback",
            unique_together={("student", "menu_item", "month")},
        ),
    ]
