from django.urls import path

from .views import StudentViewSet

student_detail = StudentViewSet.as_view({"get": "retrieve", "put": "update", "patch": "partial_update", "delete": "destroy"})
student_list = StudentViewSet.as_view({"get": "list", "post": "create"})
student_upload = StudentViewSet.as_view({"post": "upload_csv"})

urlpatterns = [
    path("", student_list, name="student-list"),
    path("upload-csv", student_upload, name="student-upload-csv"),
    path("<int:pk>", student_detail, name="student-detail"),
]
