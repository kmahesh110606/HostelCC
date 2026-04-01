from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("complaints", "0007_alter_complaint_text"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="complaint",
            index=models.Index(fields=["category", "status", "created_at"], name="comp_cat_stat_ct_idx"),
        ),
        migrations.AddIndex(
            model_name="complaint",
            index=models.Index(fields=["-created_at", "upvotes"], name="comp_created_up_idx"),
        ),
    ]
