import csv
import io

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.db import transaction
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from hostels.models import HostelBlock
from mess.models import Caterer
from mess.options import DEFAULT_MESS_TYPE, canonical_mess_type, get_allowed_mess_types_for_block
from users.permissions import IsAdmin

from .models import Student
from .serializers import StudentSerializer

User = get_user_model()


class StudentViewSet(viewsets.ModelViewSet):
    queryset = Student.objects.select_related("block", "room", "user").all()
    serializer_class = StudentSerializer

    def get_permissions(self):
        if self.action in ["upload_csv", "create", "update", "partial_update", "destroy"]:
            permission_classes = [IsAdmin]
        else:
            permission_classes = [IsAuthenticated]
        return [permission() for permission in permission_classes]

    @action(detail=False, methods=["post"], url_path="upload-csv")
    def upload_csv(self, request):
        csv_file = request.FILES.get("file")
        if not csv_file:
            return Response({"detail": "CSV file is required."}, status=status.HTTP_400_BAD_REQUEST)

        decoded = csv_file.read().decode("utf-8")
        reader = csv.DictReader(io.StringIO(decoded))
        created_count = 0
        error_response = None

        with transaction.atomic():
            for row in reader:
                block_name = row.get("block", "").strip().upper()
                block, _ = HostelBlock.objects.get_or_create(block_name=block_name)

                selected_caterer = None
                raw_caterer_name = (row.get("mess_caterer") or row.get("caterer") or "").strip()
                if raw_caterer_name:
                    selected_caterer = (
                        Caterer.objects.filter(block=block, name__iexact=raw_caterer_name).order_by("id").first()
                    )

                raw_mess_type = row.get("mess_type", row.get("mess_allotment", ""))
                mess_type = canonical_mess_type(raw_mess_type)

                if not selected_caterer and mess_type:
                    selected_caterer = (
                        Caterer.objects.filter(block=block, meal_types=mess_type).order_by("name", "id").first()
                    )

                if not selected_caterer:
                    selected_caterer = Caterer.objects.filter(block=block).order_by("name", "id").first()

                if selected_caterer:
                    mess_type = selected_caterer.meal_types
                else:
                    allowed_types = get_allowed_mess_types_for_block(block_name)
                    if mess_type not in allowed_types:
                        mess_type = allowed_types[0] if allowed_types else DEFAULT_MESS_TYPE

                username = row.get("username", row["roll_no"]).strip()
                user, _ = User.objects.get_or_create(
                    username=username,
                    defaults={
                        "email": row.get("email", ""),
                        "role": User.Role.STUDENT,
                        "first_name": row.get("name", ""),
                    },
                )
                try:
                    Student.objects.update_or_create(
                        roll_no=row["roll_no"].strip(),
                        defaults={
                            "user": user,
                            "name": row.get("name", ""),
                            "block": block,
                            "room_no": row.get("room_no", ""),
                            "mess_caterer": selected_caterer,
                            "mess_allotment": mess_type,
                        },
                    )
                except ValidationError as exc:
                    error_response = Response(
                        {"detail": "; ".join(getattr(exc, "messages", [str(exc)]))},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                    transaction.set_rollback(True)
                    break
                created_count += 1

        if error_response:
            return error_response

        return Response({"processed_records": created_count})
