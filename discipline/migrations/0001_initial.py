# Generated manually for discipline module

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("students", "0005_student_mess_caterer_assignment"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="DisciplineCase",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "violation_code",
                    models.CharField(
                        choices=[
                            ("AVOID_ATTENDANCE_OR_NIGHT_ABSENCE", "Avoiding hostel attendance or not being present at night"),
                            ("ENTERING_WITHOUT_ID_CARD", "Entering campus or hostel gate without ID card"),
                            ("MISUSE_OF_ID_CARD", "Misuse of student ID card"),
                            ("LATE_AFTER_OUTING", "Late coming after outing"),
                            ("ABSENT_WITHOUT_LEAVE", "Absent without obtaining leave"),
                            ("ROOM_SWAPPING_WITHOUT_PERMISSION", "Room swapping without hostel authority information"),
                            ("ALLOWING_NON_RESIDENT_INSIDE", "Allowing day scholar/day boarder/non-VITian inside hostel"),
                            ("UNAUTHORIZED_ENTRY_OTHER_BLOCKS", "Unauthorized entry to other hostel blocks"),
                            ("BIRTHDAY_OR_PARTY_DISRUPTION", "Birthday celebration/party disturbing hostel tranquillity"),
                            ("LOUD_MUSIC_OR_DISTURBANCE", "Loud music/games/activities disturbing others"),
                            ("UNALLOTTED_MESS_CONSUMPTION", "Having food from non-allotted mess"),
                            ("MISBEHAVING_WITH_AUTHORITY", "Misbehaving with hostel authorities"),
                            ("UNAUTHORIZED_ENTRY_HOSTEL_OFFICE", "Entering hostel office without permission and taking confiscated items"),
                            ("MISUSING_DRINKING_WATER", "Misusing drinking water"),
                            ("DAMAGING_VIT_PROPERTY", "Damaging VIT property"),
                            ("STEALING_VIT_PROPERTY", "Stealing VIT property"),
                            ("STEALING_INMATE_PROPERTY", "Stealing hostel inmate property"),
                            ("SMOKING", "Smoking"),
                            ("E_SMOKING", "E-smoking (Prohibition of Electronic Cigarettes Act, 2019)"),
                            ("E_CIGARETTE_TRADE", "Sale/trading of e-cigarettes/vape"),
                            ("DRUNKEN_ENTRY", "Coming to hostel in drunken state"),
                            ("ALCOHOL_POSSESSION_OR_INDUCING", "Bringing/possessing/drinking liquor in hostel or inducing others"),
                            ("ALCOHOL_NON_COOP_MEDICAL", "Alcohol consumption and non-cooperation for medical check-up"),
                            ("NARCOTIC_SUBSTANCE_USE_OR_SALE", "Using/selling narcotic substances or inducing others"),
                            ("FIGHT_MINOR_INJURY", "Fighting/slander/quarrelling causing minor injury"),
                            ("FIGHT_MAJOR_INJURY", "Fighting/slander/quarrelling causing major injury"),
                            ("HARASSMENT", "Mental/physical/sexual harassment"),
                            ("RAGGING", "Ragging"),
                            ("PLAYING_WITH_FIRE", "Setting fire/playing with fire/bursting crackers"),
                            ("MISUSING_FIRE_ALARM", "Misusing/playing with fire alarm"),
                            ("SOCIAL_MEDIA_DEFAMATION_INMATE", "Defaming hostel inmates through social media"),
                            ("SOCIAL_MEDIA_DEFAMATION_VIT", "Defaming VIT through social media"),
                            ("HACKING_OR_UNAUTHORIZED_ACCESS", "Hacking/unauthorized device access for file/data changes"),
                            ("FORGERY_OR_FINANCIAL_FRAUD", "Forgery/gambling/fraud/multilevel marketing/financial fraud"),
                            ("MOTOR_VEHICLE_IN_HOSTEL", "Bringing motor vehicles to hostel area or using rental for outing"),
                            ("ELECTRICAL_APPLIANCE_POSSESSION", "Possession/usage of electrical appliances in hostel room"),
                            ("FALSE_INFORMATION_IN_ENQUIRY", "Giving false information during enquiry"),
                            ("MULTIPLE_OFFICE_ORDERS", "Getting office orders for more than three occasions"),
                            ("SELLING_ITEMS_FOR_POCKET_MONEY", "Selling items in hostel for pocket money"),
                        ],
                        max_length=80,
                    ),
                ),
                ("occurrence_number", models.PositiveIntegerField(default=1)),
                ("action_taken", models.CharField(blank=True, max_length=255)),
                ("notes", models.TextField(blank=True)),
                ("id_card_confiscated", models.BooleanField(default=True)),
                ("id_card_confiscated_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("id_card_returned_at", models.DateTimeField(blank=True, null=True)),
                ("return_notes", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "created_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="discipline_cases_created",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "returned_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="discipline_cases_returned",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "student",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="discipline_cases", to="students.student"),
                ),
            ],
            options={"ordering": ["-created_at"]},
        ),
        migrations.AddIndex(
            model_name="disciplinecase",
            index=models.Index(fields=["student", "violation_code"], name="disc_student_violation_idx"),
        ),
        migrations.AddIndex(
            model_name="disciplinecase",
            index=models.Index(fields=["student", "id_card_returned_at"], name="disc_student_return_idx"),
        ),
        migrations.AddIndex(
            model_name="disciplinecase",
            index=models.Index(fields=["-created_at"], name="disc_created_desc_idx"),
        ),
    ]
