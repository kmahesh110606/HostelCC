from django.db import migrations, models


ALL_MESS_TYPES = ("VEG", "NON_VEG", "SPECIAL", "FOODPARK")
BLOCK_MESS_TYPES = {
    "A": ("VEG", "NON_VEG", "SPECIAL", "FOODPARK"),
    "C": ("VEG", "NON_VEG", "SPECIAL", "FOODPARK"),
    "D1": ("VEG", "NON_VEG", "SPECIAL", "FOODPARK"),
    "D2": ("VEG", "NON_VEG", "SPECIAL", "FOODPARK"),
    "E": ("VEG", "NON_VEG", "SPECIAL"),
}

BLOCK_MESS_CATERERS = {
    "A": {
        "VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Proodle Hospitality",
            "Grace Caterers",
        ],
        "NON_VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Grace Caterers",
        ],
        "SPECIAL": ["Fusion Catering Services", "Grace Caterers"],
        "FOODPARK": ["Rassence Catering", "Proodle Hospitality"],
    },
    "D1": {
        "VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Proodle Hospitality",
            "Grace Caterers",
        ],
        "NON_VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Grace Caterers",
        ],
        "SPECIAL": ["Fusion Catering Services", "Grace Caterers"],
        "FOODPARK": ["Rassence Catering", "Proodle Hospitality"],
    },
    "D2": {
        "VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Proodle Hospitality",
            "Grace Caterers",
        ],
        "NON_VEG": [
            "Rassence Catering",
            "Fusion Catering Services",
            "Grace Caterers",
        ],
        "SPECIAL": ["Fusion Catering Services", "Grace Caterers"],
        "FOODPARK": ["Rassence Catering", "Proodle Hospitality"],
    },
    "C": {
        "VEG": ["SRRC Catering Services", "Zenith Food Services"],
        "NON_VEG": ["SRRC Catering Services", "Zenith Food Services"],
        "SPECIAL": ["SRRC Catering Services"],
        "FOODPARK": ["Zenith Food Services"],
    },
    "E": {
        "VEG": ["J Sathya P R Food and Hospitality Services"],
        "NON_VEG": ["J Sathya P R Food and Hospitality Services"],
        "SPECIAL": ["J Sathya P R Food and Hospitality Services"],
    },
}

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


def _canonical_mess_type(value):
    raw = (value or "").strip().upper()
    if not raw:
        return ""

    raw = MESS_TYPE_ALIASES.get(raw, raw)
    normalized = raw.replace("-", "_").replace(" ", "_")
    normalized = MESS_TYPE_ALIASES.get(normalized, normalized)
    return normalized if normalized in ALL_MESS_TYPES else ""


def _allowed_mess_types_for_block(block_name):
    return BLOCK_MESS_TYPES.get((block_name or "").upper(), ALL_MESS_TYPES)


def _infer_from_caterer(block_name, current_value):
    name = (current_value or "").strip().lower()
    if not name:
        return ""

    rows = BLOCK_MESS_CATERERS.get((block_name or "").upper(), {})
    for mess_type, names in rows.items():
        for candidate in names:
            if candidate.lower() == name:
                return mess_type
    return ""


def normalize_student_mess_allotment(apps, schema_editor):
    Student = apps.get_model("students", "Student")

    for student in Student.objects.select_related("block").all():
        block_name = student.block.block_name if student.block_id else ""
        allowed = _allowed_mess_types_for_block(block_name)
        normalized = _canonical_mess_type(student.mess_allotment)

        if normalized not in allowed:
            inferred = _infer_from_caterer(block_name, student.mess_allotment)
            if inferred in allowed:
                normalized = inferred
            else:
                normalized = allowed[0]

        if student.mess_allotment != normalized:
            student.mess_allotment = normalized
            student.save(update_fields=["mess_allotment"])


def noop_reverse(apps, schema_editor):
    return


class Migration(migrations.Migration):

    dependencies = [
        ("students", "0003_student_mess_change_unlocked"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="student",
            name="points_balance",
        ),
        migrations.AlterField(
            model_name="student",
            name="mess_allotment",
            field=models.CharField(
                choices=[
                    ("VEG", "Veg"),
                    ("NON_VEG", "Non-Veg"),
                    ("SPECIAL", "Special"),
                    ("FOODPARK", "Food Park"),
                ],
                db_index=True,
                default="VEG",
                max_length=20,
            ),
        ),
        migrations.RunPython(normalize_student_mess_allotment, noop_reverse),
    ]
