from rest_framework.permissions import BasePermission


class RolePermission(BasePermission):
    allowed_roles = []

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role in self.allowed_roles)


class IsAdmin(RolePermission):
    allowed_roles = ["ADMIN"]


class IsStudent(RolePermission):
    allowed_roles = ["STUDENT"]


class IsWarden(RolePermission):
    allowed_roles = ["WARDEN", "ADMIN"]


class IsMessManager(RolePermission):
    allowed_roles = ["MESS_MANAGER", "ADMIN"]


class IsLaundryPerson(RolePermission):
    allowed_roles = ["LAUNDRY_PERSON", "ADMIN"]
