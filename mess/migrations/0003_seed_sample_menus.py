from django.db import migrations


def seed_menus(apps, schema_editor):
    MessMenu = apps.get_model("mess", "MessMenu")

    sample_rows = [
        {
            "week_day": "MON",
            "breakfast_items": "Idli, Sambar, Chutney, Banana",
            "lunch_items": "Rice, Dal Tadka, Cabbage Poriyal, Curd",
            "snacks_items": "Samosa, Tea",
            "dinner_items": "Chapati, Mixed Veg Curry, Jeera Rice",
        },
        {
            "week_day": "TUE",
            "breakfast_items": "Pongal, Vada, Coconut Chutney",
            "lunch_items": "Rice, Sambar, Potato Roast, Rasam",
            "snacks_items": "Bhel Puri, Coffee",
            "dinner_items": "Parotta, Kurma, Lemon Rice",
        },
        {
            "week_day": "WED",
            "breakfast_items": "Dosa, Tomato Chutney, Boiled Egg",
            "lunch_items": "Veg Biryani, Raita, Onion Pakoda",
            "snacks_items": "Bread Omelette, Tea",
            "dinner_items": "Chapati, Paneer Butter Masala, Rice",
        },
        {
            "week_day": "THU",
            "breakfast_items": "Poori, Aloo Masala, Fruit Bowl",
            "lunch_items": "Rice, Kara Kuzhambu, Beans Poriyal, Curd",
            "snacks_items": "Puffs, Tea",
            "dinner_items": "Fried Rice, Gobi Manchurian, Soup",
        },
        {
            "week_day": "FRI",
            "breakfast_items": "Upma, Kesari, Chutney",
            "lunch_items": "Rice, Soya Curry, Dal Fry, Buttermilk",
            "snacks_items": "Cutlet, Coffee",
            "dinner_items": "Noodles, Veg Kurma, Chapati",
        },
    ]

    for row in sample_rows:
        MessMenu.objects.update_or_create(week_day=row["week_day"], defaults=row)


class Migration(migrations.Migration):

    dependencies = [
        ("mess", "0002_initial"),
    ]

    operations = [
        migrations.RunPython(seed_menus, migrations.RunPython.noop),
    ]
