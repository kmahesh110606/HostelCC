from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0008_seed_default_admin_user"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="appnotification",
            index=models.Index(fields=["is_active", "audience", "-created_at"], name="notif_active_aud_ct_idx"),
        ),
        migrations.AddIndex(
            model_name="appnotification",
            index=models.Index(fields=["audience", "-created_at"], name="notif_aud_ct_idx"),
        ),
    ]
