from django.core.management.base import BaseCommand

from hostels.models import HostelBlock
from mess.models import Caterer, MessMenu
from mess.options import MESS_TYPES, iter_caterer_rows


class Command(BaseCommand):
    help = "Seed blocks, caterers, and mock mess menu data"

    def handle(self, *args, **options):
        block_names = ["A", "B", "C", "D1", "D2", "E"]
        blocks = {}
        for name in block_names:
            block, _ = HostelBlock.objects.get_or_create(block_name=name)
            blocks[name] = block

        for block_name, mess_type, name in iter_caterer_rows():
            Caterer.objects.get_or_create(
                name=name,
                block=blocks[block_name],
                meal_types=mess_type,
            )

        mock_menu = {
            "MON": {
                "breakfast": "Idli, Sambar, Chutney, Boiled Egg",
                "lunch": "Rice, Sambar, Veg Poriyal, Chicken Curry, Curd",
                "snacks": "Sundal, Tea",
                "dinner": "Chapati, Paneer Butter Masala, Dal Fry",
            },
            "TUE": {
                "breakfast": "Pongal, Vada, Chutney",
                "lunch": "Rice, Rasam, Potato Roast, Fish Fry",
                "snacks": "Puffs, Tea",
                "dinner": "Jeera Rice, Veg Kurma, Omelette",
            },
            "WED": {
                "breakfast": "Dosa, Chutney, Sambar",
                "lunch": "Lemon Rice, Kootu, Chicken 65, Salad",
                "snacks": "Banana Bajji, Coffee",
                "dinner": "Parotta, Chana Masala, Egg Gravy",
            },
            "THU": {
                "breakfast": "Poori, Potato Masala, Milk",
                "lunch": "Rice, Kara Kuzhambu, Beans Poriyal, Curd",
                "snacks": "Masala Corn, Tea",
                "dinner": "Tomato Rice, Raita, Veg Cutlet",
            },
            "FRI": {
                "breakfast": "Upma, Kesari, Chutney",
                "lunch": "Veg Biryani, Onion Raitha, Boiled Egg",
                "snacks": "Samosa, Tea",
                "dinner": "Fried Rice, Gobi Manchurian, Dal Tadka",
            },
        }

        for mess_type in MESS_TYPES.keys():
            for day, items in mock_menu.items():
                MessMenu.objects.update_or_create(
                    mess_type=mess_type,
                    week_day=day,
                    defaults={
                        "breakfast_items": items["breakfast"],
                        "lunch_items": items["lunch"],
                        "snacks_items": items["snacks"],
                        "dinner_items": items["dinner"],
                    },
                )

        self.stdout.write(self.style.SUCCESS("Seeded blocks, caterers, and mess menu."))
