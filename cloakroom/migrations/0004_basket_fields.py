from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("cloakroom", "0003_cloakroomroom"),
    ]

    operations = [
        migrations.AddField(
            model_name="cloakroomroom",
            name="item_name",
            field=models.CharField(blank=True, default="", max_length=180),
        ),
        migrations.AddField(
            model_name="cloakroomroom",
            name="next_token_no",
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name="cloakroomentry",
            name="basket_token_no",
            field=models.PositiveIntegerField(db_index=True, default=0),
        ),
    ]
