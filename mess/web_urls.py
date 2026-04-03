from django.urls import path

from .web_views import download_mess_menu_csv, download_mess_students_csv, mess_portal

urlpatterns = [
    path("", mess_portal, name="mess-portal"),
    path("exports/students.csv", download_mess_students_csv, name="mess-export-students"),
    path("exports/students.csv/", download_mess_students_csv, name="mess-export-students-slash"),
    path("exports/caterer-students.csv", download_mess_students_csv, name="mess-export-caterer-students"),
    path("exports/caterer-students.csv/", download_mess_students_csv, name="mess-export-caterer-students-slash"),
    path("exports/menu.csv", download_mess_menu_csv, name="mess-export-menu"),
    path("exports/menu.csv/", download_mess_menu_csv, name="mess-export-menu-slash"),
]
