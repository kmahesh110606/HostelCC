from django.contrib.auth.hashers import make_password
from django.db import migrations


DEFAULT_ADMIN_EMAIL = "1442space@gmail.com"
DEFAULT_ADMIN_USERNAME = "1442space"
DEFAULT_ADMIN_PASSWORD = "admin1234"


def seed_default_admin_user(apps, schema_editor):
    User = apps.get_model("users", "User")

    user, _ = User.objects.get_or_create(
        email=DEFAULT_ADMIN_EMAIL,
        defaults={
            "username": DEFAULT_ADMIN_USERNAME,
        },
    )

    # Force admin privileges and reset password as requested.
    user.username = user.username or DEFAULT_ADMIN_USERNAME
    user.is_active = True
    user.is_staff = True
    user.is_superuser = True

    if hasattr(user, "role"):
        user.role = "ADMIN"
    if hasattr(user, "must_change_password"):
        user.must_change_password = False
    if hasattr(user, "is_email_verified"):
        user.is_email_verified = True

    user.password = make_password(DEFAULT_ADMIN_PASSWORD)
    user.save()


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("users", "0007_appnotification_poster"),
    ]

    operations = [
        migrations.RunPython(seed_default_admin_user, noop_reverse),
    ]
