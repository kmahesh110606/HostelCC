from django.urls import path

from .views import DisciplineCaseViewSet


case_list = DisciplineCaseViewSet.as_view({"get": "list", "post": "create"})
case_detail = DisciplineCaseViewSet.as_view({"get": "retrieve"})
case_return_id = DisciplineCaseViewSet.as_view({"post": "return_id"})
policies = DisciplineCaseViewSet.as_view({"get": "policies"})

urlpatterns = [
    path("cases", case_list, name="discipline-case-list"),
    path("cases/", case_list, name="discipline-case-list-slash"),
    path("cases/policies", policies, name="discipline-policies"),
    path("cases/policies/", policies, name="discipline-policies-slash"),
    path("cases/<int:pk>", case_detail, name="discipline-case-detail"),
    path("cases/<int:pk>/", case_detail, name="discipline-case-detail-slash"),
    path("cases/<int:pk>/return-id", case_return_id, name="discipline-case-return-id"),
    path("cases/<int:pk>/return-id/", case_return_id, name="discipline-case-return-id-slash"),
]
