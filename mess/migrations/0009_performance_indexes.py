from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0008_alter_caterer_options_alter_messmenu_options_and_more"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="feedback",
            index=models.Index(fields=["month", "created_at"], name="mess_fb_month_ct_idx"),
        ),
        migrations.AddIndex(
            model_name="feedback",
            index=models.Index(fields=["student", "created_at"], name="mess_fb_student_ct_idx"),
        ),
        migrations.AddIndex(
            model_name="feedback",
            index=models.Index(fields=["menu_item"], name="mess_fb_item_idx"),
        ),
        migrations.AddIndex(
            model_name="menupolloption",
            index=models.Index(fields=["month", "poll_type"], name="mess_poll_month_ty_idx"),
        ),
    ]
