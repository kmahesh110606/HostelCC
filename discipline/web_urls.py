from django.urls import path

from .web_views import discipline_portal, export_discipline_cases_csv, export_student_master_csv

urlpatterns = [
    path("", discipline_portal, name="discipline-portal"),
    path("exports/students-master.csv", export_student_master_csv, name="discipline-export-students-master"),
    path("exports/students-master.csv/", export_student_master_csv, name="discipline-export-students-master-slash"),
    path("exports/cases.csv", export_discipline_cases_csv, name="discipline-export-cases"),
    path("exports/cases.csv/", export_discipline_cases_csv, name="discipline-export-cases-slash"),
]
