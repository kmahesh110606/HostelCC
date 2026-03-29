from django.db import migrations, models
import django.db.models.deletion


MESS_TYPE_ALIASES = {
    "VEGETARIAN": "VEG",
    "NONVEG": "NON_VEG",
    "NON-VEG": "NON_VEG",
    "NON VEG": "NON_VEG",
    "NONVEGETARIAN": "NON_VEG",
    "NON VEGETARIAN": "NON_VEG",
    "FOOD_PARK": "FOODPARK",
    "FOOD PARK": "FOODPARK",
}
VALID_MESS_TYPES = {"VEG", "NON_VEG", "SPECIAL", "FOODPARK"}
DEFAULT_MESS_TYPE = "VEG"


def _canonical_mess_type(value):
    raw = (value or "").strip().upper()
    if not raw:
        return ""

    raw = MESS_TYPE_ALIASES.get(raw, raw)
    normalized = raw.replace("-", "_").replace(" ", "_")
    normalized = MESS_TYPE_ALIASES.get(normalized, normalized)
    return normalized if normalized in VALID_MESS_TYPES else ""


def _normalize_and_assign_caterer(apps, schema_editor):
    Student = apps.get_model("students", "Student")
    Caterer = apps.get_model("mess", "Caterer")

    for student in Student.objects.all().iterator():
        if not student.block_id:
            continue

        normalized_type = _canonical_mess_type(student.mess_allotment) or DEFAULT_MESS_TYPE
        block_caterers = Caterer.objects.filter(block_id=student.block_id)

        selected = (
            block_caterers.filter(meal_types=normalized_type).order_by("name", "id").first()
        )

        if not selected:
            # Legacy rows may contain caterer names in mess_allotment.
            selected = block_caterers.filter(name__iexact=(student.mess_allotment or "").strip()).order_by("id").first()

        if not selected:
            selected = block_caterers.order_by("name", "id").first()

        update_fields = []
        if student.mess_allotment != normalized_type:
            student.mess_allotment = normalized_type
            update_fields.append("mess_allotment")

        if selected and student.mess_caterer_id != selected.id:
            student.mess_caterer_id = selected.id
            update_fields.append("mess_caterer")

        if update_fields:
            student.save(update_fields=update_fields)


def _noop_reverse(apps, schema_editor):
    return


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0008_alter_caterer_options_alter_messmenu_options_and_more"),
        ("students", "0004_remove_points_balance_and_normalize_mess_type"),
    ]

    operations = [
        migrations.AddField(
            model_name="student",
            name="mess_caterer",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="students",
                to="mess.caterer",
            ),
        ),
        migrations.RunPython(_normalize_and_assign_caterer, _noop_reverse),
    ]
