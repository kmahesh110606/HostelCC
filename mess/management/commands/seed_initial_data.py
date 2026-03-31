from django.core.management.base import BaseCommand

from hostels.models import HostelBlock
from mess.models import Caterer, MessMenu
from mess.options import MESS_TYPES, iter_caterer_rows


MENU_COMMON = {
    "MON": {
        "breakfast": [
            "Mix Vegetable Upma",
            "Chutney",
            "Curd",
            "Pongal",
            "Sambar",
            "Toasted Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Veg Pulao",
            "Boondi Raita",
            "Dal Fry",
            "White Rice",
            "Mochai Kara Kolambu",
            "Carrot and Beans Poriyal",
            "Paruppu",
            "Paruppu Podi",
            "Gingerly Oil",
            "Thovayial",
            "Pickle",
            "Pappad",
            "Banana",
            "Buttermilk",
            "Lemon Mint Juice",
        ],
        "snacks": ["Sandwich", "Sauce", "Tea/Coffee/Milk"],
        "dinner": [
            "Phulka",
            "Rajma Curry",
            "Jeera Dal",
            "White Rice",
            "Dry Cabbage Poriyal",
            "Rasam",
            "Pickle",
            "Ice Cream",
            "Salad (Tomato, Carrot, Lemon)",
            "Green Chilli",
            "Milk",
            "Buttermilk",
        ],
    },
    "TUE": {
        "breakfast": [
            "Idli",
            "Sambar",
            "Mint Chutney",
            "Podi Oil",
            "Poha Bhujia",
            "Chopped Onion",
            "Lemon",
            "Wheat Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Methi Dal",
            "Jeera Rice",
            "White Rice",
            "Chettinad Sambar",
            "Cabbage Aloo Poriyal",
            "Uduppi Tomato Rasam",
            "Curd",
            "Paruppu Podi",
            "Ghee",
            "Thovayial",
            "Pickle",
            "Fruit",
            "Pappad",
            "Salad",
            "Lemon Mint Juice",
        ],
        "snacks": ["Sweet Potato", "Tea/Coffee/Milk"],
        "dinner": [
            "Chapathi",
            "Soya Chunk Gravy",
            "Harar Dal",
            "White Rice",
            "Beans Poriyal",
            "Rasam",
            "Curd",
            "Pickle",
            "Milk",
            "Sweet",
            "Salad (Cucumber, Carrot, Lemon)",
            "Buttermilk",
        ],
    },
    "WED": {
        "breakfast": [
            "Puri",
            "Puri Masala",
            "Rawa Khichdi",
            "Chutney",
            "Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Palak Paneer",
            "Ghee Rice",
            "Panchmel Dal",
            "White Rice",
            "Arachivitta Sambar",
            "Tendli Poriyal",
            "Milagu Rasam",
            "Paruppu Podi",
            "Ghee",
            "Thovayial",
            "Pickle",
            "Fruit (Papaya)",
            "Sweet Lassi",
            "Lemon Mint Juice",
        ],
        "snacks": ["Pasta (Red/White)", "Tea/Coffee/Milk"],
        "dinner": [
            "Mixed Veg Sabzi",
            "Semiya Khichadi",
            "Ahrar Dal Tadka",
            "Coconut Chutney",
            "White Rice",
            "Rasam",
            "Curd",
            "Sweet",
            "Cold Badam Milk",
            "Salad (Beetroot, Carrot, Cucumber)",
            "Butter Milk",
            "Milk",
        ],
    },
    "THU": {
        "breakfast": [
            "Pav Bhaji",
            "Onion (Chopped)",
            "Idiyappam",
            "Vadacurry",
            "Coconut Milk",
            "Wheat Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Mixed Veg Pulao",
            "Potato Chips",
            "White Rice",
            "Dal Fry",
            "Raw Banana Poriyal",
            "Pineapple Rasam",
            "Curd",
            "Paruppu Podi",
            "Gingerly Oil",
            "Thovayial",
            "Pickle",
            "Lemon Mint Juice",
            "Fruit Salad (Black Grapes, Pineapple)",
        ],
        "snacks": ["Boiled Chana Chat", "Chopped Onions", "Tea/Coffee/Milk"],
        "dinner": [
            "White Channa Masala",
            "Phulka",
            "White Rice",
            "Sambar",
            "Mixed Vegetable Poriyal",
            "Rasam",
            "Pickle",
            "Salad (Cucumber, Carrot)",
            "Milk",
            "Buttermilk",
        ],
    },
    "FRI": {
        "breakfast": [
            "Dosa",
            "Sambar",
            "Chutney",
            "Podi Oil",
            "Semiya Khichadi",
            "Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Paneer Tikka Masala (Semi Dry)",
            "Andhra Pappu",
            "Green Peas Pulav",
            "White Rice",
            "Uduppi Sambar",
            "Potato Pattani Masala",
            "Moong Dal Rasam",
            "Mint Buttermilk",
            "Paruppu Podi",
            "Ghee",
            "Thovayial",
            "Pickle",
            "Lemon Mint Juice",
            "Fruits (Watermelon)",
        ],
        "snacks": ["Bhel Puri", "Tea/Coffee/Milk"],
        "dinner": [
            "Veg Pulao",
            "White Channa Masala",
            "Idly",
            "Chutney",
            "Sambar",
            "White Rice",
            "Carrot Poriyal",
            "Rasam",
            "Curd",
            "Pickle",
            "Sweet",
            "Salad",
            "Milk",
            "Buttermilk",
        ],
    },
    "SAT": {
        "breakfast": [
            "Rawa Idly",
            "Chutney",
            "Sambar",
            "Potato Onion Poha",
            "Wheat Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Roasted Veggies",
            "Schezwan Fried Rice",
            "White Rice",
            "Dal Fry",
            "Milagu Rasam",
            "Curd",
            "Keerai Poriyal",
            "Paruppu Podi",
            "Gingerly Oil",
            "Thovayial",
            "Fryums",
            "Pickle",
            "Fruit (Banana)",
            "Lemon Mint Juice",
        ],
        "snacks": ["Pani Puri", "Tea/Coffee/Milk"],
        "dinner": [
            "Phulka",
            "Cabbage Green Peas Masala Fry",
            "Jeera Rice",
            "Dal Fry",
            "Plain Rice",
            "Kadhi Pakoda Curry",
            "Rasam",
            "Curd",
            "Papad",
            "Pickle",
            "Salad",
            "Milk",
            "Buttermilk",
        ],
    },
    "SUN": {
        "breakfast": [
            "Pav Bhaji",
            "Millet Pongal",
            "Sambar",
            "Chutney",
            "Bread",
            "Butter",
            "Jam",
            "Tea/Coffee/Milk",
        ],
        "lunch": [
            "Dum Paneer Biryani",
            "Gobi and Aloo Masala",
            "Onion Raita",
            "White Rice",
            "Mysore Rasam",
            "Curd Rice",
            "Pickle",
            "Mixed Fruits (Watermelon, Grapes)",
            "Buttermilk",
            "Salad",
        ],
        "snacks": ["Masala Sweet Corn", "Tea/Coffee/Milk"],
        "dinner": [
            "Ghee Rice",
            "Dal Makhani",
            "Rawa Khichdi",
            "Coconut Chutney",
            "Sambar",
            "White Rice",
            "Loki Chana Dry",
            "Rasam",
            "Sweet",
            "Salad",
            "Milk",
            "Buttermilk",
            "Clear Soup",
        ],
    },
}

MENU_NON_VEG_SPECIAL = {
    "MON": {
        "breakfast": ["Boiled Egg"],
        "lunch": ["Mughlai Chicken"],
        "snacks": [],
        "dinner": [],
    },
    "TUE": {
        "breakfast": ["Egg Bhurji"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Chettinad Egg Masala"],
    },
    "WED": {
        "breakfast": ["Boiled Egg"],
        "lunch": ["Chicken Handi Masala"],
        "snacks": [],
        "dinner": ["Egg Curry"],
    },
    "THU": {
        "breakfast": ["Boiled Egg"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Egg Fried Rice"],
    },
    "FRI": {
        "breakfast": ["Egg Bhurji"],
        "lunch": ["Chicken Chettinad Masala (Semi Dry)"],
        "snacks": [],
        "dinner": ["Tomato Egg Curry"],
    },
    "SAT": {
        "breakfast": ["Boiled Egg"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Chicken and Veg Soup"],
    },
    "SUN": {
        "breakfast": ["Egg Bhurji"],
        "lunch": ["Dum Chicken Biryani"],
        "snacks": [],
        "dinner": [],
    },
}

MENU_SPECIAL_ONLY = {
    "MON": {
        "breakfast": ["Cornflakes", "Cold Milk", "Muskmelon Juice"],
        "lunch": ["Kadai Paneer Dry"],
        "snacks": [],
        "dinner": ["Vaazhai Thandu Soup"],
    },
    "TUE": {
        "breakfast": ["Chocos", "Cold Milk", "Mosambi Juice"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Spicy Mushroom Soup"],
    },
    "WED": {
        "breakfast": ["Chocos", "Cold Milk", "Apple Juice"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Clear Soup"],
    },
    "THU": {
        "breakfast": ["Cornflakes", "Cold Milk", "Pineapple Juice"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Sweet Corn Soup"],
    },
    "FRI": {
        "breakfast": ["Cornflakes", "Cold Milk", "Watermelon Juice"],
        "lunch": [],
        "snacks": [],
        "dinner": ["Hot and Sour Soup"],
    },
    "SAT": {
        "breakfast": ["Chocos", "Cold Milk", "Grape Juice"],
        "lunch": [],
        "snacks": [],
        "dinner": [],
    },
    "SUN": {
        "breakfast": ["Chocos", "Cold Milk", "Orange Juice"],
        "lunch": [],
        "snacks": [],
        "dinner": [],
    },
}


def _serialize_items(items):
    return ", ".join(item.strip() for item in items if item and item.strip())


def _merged_items(day_code, meal_key, mess_type):
    merged = list(MENU_COMMON[day_code][meal_key])
    if mess_type in {"NON_VEG", "SPECIAL"}:
        merged.extend(MENU_NON_VEG_SPECIAL[day_code][meal_key])
    if mess_type == "SPECIAL":
        merged.extend(MENU_SPECIAL_ONLY[day_code][meal_key])
    return _serialize_items(merged)


class Command(BaseCommand):
    help = "Seed blocks, caterers, and full weekly mess menu data"

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

        for mess_type in ["VEG", "NON_VEG", "SPECIAL"]:
            for day in MENU_COMMON.keys():
                MessMenu.objects.update_or_create(
                    mess_type=mess_type,
                    week_day=day,
                    defaults={
                        "breakfast_items": _merged_items(day, "breakfast", mess_type),
                        "lunch_items": _merged_items(day, "lunch", mess_type),
                        "snacks_items": _merged_items(day, "snacks", mess_type),
                        "dinner_items": _merged_items(day, "dinner", mess_type),
                    },
                )

        # Food Park changes daily and should not have fixed weekly menu entries.
        MessMenu.objects.filter(mess_type="FOODPARK").delete()

        self.stdout.write(self.style.SUCCESS("Seeded blocks, caterers, and full weekly mess menu."))
