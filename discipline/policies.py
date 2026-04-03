from __future__ import annotations

from typing import Dict, List

VIOLATION_POLICIES: List[dict] = [
    {
        "code": "LATE_ENTRY_AT_NIGHT",
        "title": "Late entry to hostel at night (9:00 PM boys, 8:00 PM girls)",
        "actions": [
            "Record only (no fine)",
        ],
    },
    {
        "code": "AVOID_ATTENDANCE_OR_NIGHT_ABSENCE",
        "title": "Avoiding hostel attendance or not being present at night",
        "actions": [
            "1st time: Warning",
            "2nd time: Outing cancellation for 15 days",
            "On repetition: Outing cancellation for one semester",
        ],
    },
    {
        "code": "ENTERING_WITHOUT_ID_CARD",
        "title": "Entering campus or hostel gate without ID card",
        "actions": [
            "1st time: Warning",
            "On repetition: Penalty of Rs.500/-",
        ],
    },
    {
        "code": "MISUSE_OF_ID_CARD",
        "title": "Misuse of student ID card",
        "actions": [
            "1st time: Penalty of Rs.500/-",
            "On repetition: Penalty of Rs.1000/-",
        ],
    },
    {
        "code": "LATE_AFTER_OUTING",
        "title": "Late coming after outing",
        "actions": [
            "1st time: Penalty of Rs.1000/-",
            "2nd time: Penalty of Rs.1500/-",
            "3rd time: Penalty of Rs.2000/-",
            "On repetition: Hostel outing canceled for one semester",
        ],
    },
    {
        "code": "ABSENT_WITHOUT_LEAVE",
        "title": "Absent without obtaining leave",
        "actions": [
            "1st time: Penalty of Rs.3000/-",
            "On repetition: Penalty of Rs.5000/-",
        ],
    },
    {
        "code": "ROOM_SWAPPING_WITHOUT_PERMISSION",
        "title": "Room swapping without hostel authority information",
        "actions": ["Penalty of Rs.5000/-"],
    },
    {
        "code": "ALLOWING_NON_RESIDENT_INSIDE",
        "title": "Allowing day scholar/day boarder/non-VITian inside hostel",
        "actions": ["Penalty of Rs.5000/-"],
    },
    {
        "code": "UNAUTHORIZED_ENTRY_OTHER_BLOCKS",
        "title": "Unauthorized entry to other hostel blocks",
        "actions": [
            "1st time: Warning",
            "2nd time: Penalty of Rs.500/-",
        ],
    },
    {
        "code": "BIRTHDAY_OR_PARTY_DISRUPTION",
        "title": "Birthday celebration/party disturbing hostel tranquillity",
        "actions": [
            "1st time: Penalty of Rs.3000/- to each participant",
            "2nd time: Penalty of Rs.5000/- to each participant",
        ],
    },
    {
        "code": "LOUD_MUSIC_OR_DISTURBANCE",
        "title": "Loud music/games/activities disturbing others",
        "actions": [
            "1st time: Warning",
            "2nd time: Penalty of Rs.3000/-",
        ],
    },
    {
        "code": "UNALLOTTED_MESS_CONSUMPTION",
        "title": "Having food from non-allotted mess",
        "actions": ["Fine as per norms (Actual monetary loss x 3)"],
    },
    {
        "code": "MISBEHAVING_WITH_AUTHORITY",
        "title": "Misbehaving with hostel authorities",
        "actions": [
            "1st time: Warning",
            "2nd time: Penalty of Rs.1000/-",
            "3rd time: Outing cancellation for one semester",
        ],
    },
    {
        "code": "UNAUTHORIZED_ENTRY_HOSTEL_OFFICE",
        "title": "Entering hostel office without permission and taking confiscated items",
        "actions": ["Penalty of Rs.3000/- or suspension up to 1 month (serious cases)"],
    },
    {
        "code": "MISUSING_DRINKING_WATER",
        "title": "Misusing drinking water",
        "actions": ["Fine up to Rs.5000/-"],
    },
    {
        "code": "DAMAGING_VIT_PROPERTY",
        "title": "Damaging VIT property",
        "actions": ["Rs.5000 fine + (Actual monetary loss x 3)"],
    },
    {
        "code": "STEALING_VIT_PROPERTY",
        "title": "Stealing VIT property",
        "actions": ["Suspension up to 1 year with reasonable fine"],
    },
    {
        "code": "STEALING_INMATE_PROPERTY",
        "title": "Stealing hostel inmate property",
        "actions": ["Suspension from institution for up to 1 year"],
    },
    {
        "code": "SMOKING",
        "title": "Smoking",
        "actions": [
            "1st time: Rs.1000 penalty + community service + counselling",
            "2nd time: Penalty of Rs.3000/-",
            "On repetition: Suspension for 15 days",
        ],
    },
    {
        "code": "E_SMOKING",
        "title": "E-smoking (Prohibition of Electronic Cigarettes Act, 2019)",
        "actions": ["Suspension up to one semester"],
    },
    {
        "code": "E_CIGARETTE_TRADE",
        "title": "Sale/trading of e-cigarettes/vape",
        "actions": ["Expulsion from institution"],
    },
    {
        "code": "DRUNKEN_ENTRY",
        "title": "Coming to hostel in drunken state",
        "actions": ["Suspension for one semester"],
    },
    {
        "code": "ALCOHOL_POSSESSION_OR_INDUCING",
        "title": "Bringing/possessing/drinking liquor in hostel or inducing others",
        "actions": [
            "1st time: Suspension for 1 year",
            "2nd time: Suspension for 2 years",
        ],
    },
    {
        "code": "ALCOHOL_NON_COOP_MEDICAL",
        "title": "Alcohol consumption and non-cooperation for medical check-up",
        "actions": [
            "1st time: Suspension for one semester",
            "2nd time: Suspension for 1 year",
            "On repetition: Expulsion from university",
        ],
    },
    {
        "code": "NARCOTIC_SUBSTANCE_USE_OR_SALE",
        "title": "Using/selling narcotic substances or inducing others",
        "actions": ["Expulsion from university"],
    },
    {
        "code": "FIGHT_MINOR_INJURY",
        "title": "Fighting/slander/quarrelling causing minor injury",
        "actions": ["Penalty of Rs.5000/- + social services"],
    },
    {
        "code": "FIGHT_MAJOR_INJURY",
        "title": "Fighting/slander/quarrelling causing major injury",
        "actions": ["Expulsion from university"],
    },
    {
        "code": "HARASSMENT",
        "title": "Mental/physical/sexual harassment",
        "actions": [
            "Less serious: Suspension for 1 month",
            "Serious: Suspension for 1 year or expulsion",
        ],
    },
    {
        "code": "RAGGING",
        "title": "Ragging",
        "actions": ["Expulsion from institution"],
    },
    {
        "code": "PLAYING_WITH_FIRE",
        "title": "Setting fire/playing with fire/bursting crackers",
        "actions": [
            "If no damage: Fine Rs.5000/-",
            "If damage/injury: Suspension up to one semester with reasonable fine",
        ],
    },
    {
        "code": "MISUSING_FIRE_ALARM",
        "title": "Misusing/playing with fire alarm",
        "actions": [
            "1st time: Fine Rs.2000/-",
            "2nd time: Fine Rs.2000/- and outing cancellation for 3 months",
        ],
    },
    {
        "code": "SOCIAL_MEDIA_DEFAMATION_INMATE",
        "title": "Defaming hostel inmates through social media",
        "actions": ["Fine Rs.5000/-"],
    },
    {
        "code": "SOCIAL_MEDIA_DEFAMATION_VIT",
        "title": "Defaming VIT through social media",
        "actions": ["Expulsion from institution"],
    },
    {
        "code": "HACKING_OR_UNAUTHORIZED_ACCESS",
        "title": "Hacking/unauthorized device access for file/data changes",
        "actions": ["Suspension for 1 year or expulsion"],
    },
    {
        "code": "FORGERY_OR_FINANCIAL_FRAUD",
        "title": "Forgery/gambling/fraud/multilevel marketing/financial fraud",
        "actions": ["Expulsion from institution"],
    },
    {
        "code": "MOTOR_VEHICLE_IN_HOSTEL",
        "title": "Bringing motor vehicles to hostel area or using rental for outing",
        "actions": ["Penalty of Rs.5000/- + suspension as per norms"],
    },
    {
        "code": "ELECTRICAL_APPLIANCE_POSSESSION",
        "title": "Possession/usage of electrical appliances in hostel room",
        "actions": ["Penalty of Rs.500/- + confiscation of appliance"],
    },
    {
        "code": "FALSE_INFORMATION_IN_ENQUIRY",
        "title": "Giving false information during enquiry",
        "actions": ["Outing cancellation for 3 months + warning office order"],
    },
    {
        "code": "MULTIPLE_OFFICE_ORDERS",
        "title": "Getting office orders for more than three occasions",
        "actions": ["Suspension up to one semester based on severity"],
    },
    {
        "code": "SELLING_ITEMS_FOR_POCKET_MONEY",
        "title": "Selling items in hostel for pocket money",
        "actions": ["Penalty of Rs.5000/-"],
    },
]

POLICY_BY_CODE: Dict[str, dict] = {item["code"]: item for item in VIOLATION_POLICIES}
VIOLATION_CHOICES = [(item["code"], item["title"]) for item in VIOLATION_POLICIES]


def action_for_occurrence(violation_code: str, occurrence_number: int) -> str:
    policy = POLICY_BY_CODE.get(violation_code)
    if not policy:
        return ""

    actions = policy.get("actions", [])
    if not actions:
        return ""

    if occurrence_number <= len(actions):
        return actions[occurrence_number - 1]

    return actions[-1]
