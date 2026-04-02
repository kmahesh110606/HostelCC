from __future__ import annotations

from collections import OrderedDict
from functools import lru_cache

MESS_TYPES = OrderedDict(
    [
        ("VEG", "Veg"),
        ("NON_VEG", "Non-Veg"),
        ("SPECIAL", "Special"),
        ("FOODPARK", "Food Park"),
    ]
)

MESS_TYPE_CHOICES = tuple((value, label) for value, label in MESS_TYPES.items())
DEFAULT_MESS_TYPE = "VEG"

# Fixed block-wise mapping requested by the product team.
BLOCK_MESS_CATERERS: dict[str, dict[str, list[str]]] = {
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

# Block B is left unrestricted so existing data does not break.
DEFAULT_BLOCK_MESS_TYPES = tuple(MESS_TYPES.keys())

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


def canonical_mess_type(value: str | None) -> str:
    raw = (value or "").strip().upper()
    if not raw:
        return ""

    raw = MESS_TYPE_ALIASES.get(raw, raw)
    normalized = raw.replace("-", "_").replace(" ", "_")
    normalized = MESS_TYPE_ALIASES.get(normalized, normalized)
    return normalized if normalized in MESS_TYPES else ""


def get_allowed_mess_types_for_block(block_name: str | None) -> list[str]:
    block = (block_name or "").strip().upper()
    if block in BLOCK_MESS_CATERERS:
        return list(BLOCK_MESS_CATERERS[block].keys())
    return list(DEFAULT_BLOCK_MESS_TYPES)


def get_allowed_caterers_for_block(block_name: str | None) -> list[str]:
    block = (block_name or "").strip().upper()
    rows = BLOCK_MESS_CATERERS.get(block, {})

    seen: OrderedDict[str, None] = OrderedDict()
    for names in rows.values():
        for name in names:
            seen.setdefault(name, None)
    return list(seen.keys())


def get_allowed_caterers_for_block_and_type(block_name: str | None, mess_type: str | None) -> list[str]:
    block = (block_name or "").strip().upper()
    normalized_mess_type = canonical_mess_type(mess_type)
    if not block or not normalized_mess_type:
        return []

    return list(BLOCK_MESS_CATERERS.get(block, {}).get(normalized_mess_type, []))


@lru_cache(maxsize=1)
def get_all_caterer_names() -> list[str]:
    seen: OrderedDict[str, None] = OrderedDict()
    for block_rows in BLOCK_MESS_CATERERS.values():
        for names in block_rows.values():
            for name in names:
                seen.setdefault(name, None)
    return list(seen.keys())


@lru_cache(maxsize=1)
def build_block_mess_types_payload() -> dict[str, list[str]]:
    payload: dict[str, list[str]] = {}
    for block in ["A", "B", "C", "D1", "D2", "E"]:
        payload[block] = get_allowed_mess_types_for_block(block)
    return payload


@lru_cache(maxsize=1)
def build_block_caterers_payload() -> dict[str, list[str]]:
    payload: dict[str, list[str]] = {}
    for block in ["A", "B", "C", "D1", "D2", "E"]:
        payload[block] = get_allowed_caterers_for_block(block)
    return payload


@lru_cache(maxsize=1)
def build_block_mess_caterers_payload() -> dict[str, dict[str, list[str]]]:
    payload: dict[str, dict[str, list[str]]] = {}
    for block, by_type in BLOCK_MESS_CATERERS.items():
        payload[block] = {mess_type: list(names) for mess_type, names in by_type.items()}
    return payload


def infer_mess_type_from_caterer(block_name: str | None, caterer_name: str | None) -> str:
    block = (block_name or "").strip().upper()
    name = (caterer_name or "").strip().lower()
    if not block or not name:
        return ""

    by_type = BLOCK_MESS_CATERERS.get(block, {})
    for mess_type, names in by_type.items():
        if any(existing.lower() == name for existing in names):
            return mess_type
    return ""


def iter_caterer_rows() -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    for block, by_type in BLOCK_MESS_CATERERS.items():
        for mess_type, names in by_type.items():
            for name in names:
                rows.append((block, mess_type, name))
    return rows
