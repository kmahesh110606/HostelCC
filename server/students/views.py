import csv
import io

from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from hostels.models import HostelBlock
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

        with transaction.atomic():
            for row in reader:
                block_name = row.get("block", "").strip().upper()
                block, _ = HostelBlock.objects.get_or_create(block_name=block_name)
                username = row.get("username", row["roll_no"]).strip()
                user, _ = User.objects.get_or_create(
                    username=username,
                    defaults={
                        "email": row.get("email", ""),
                        "role": User.Role.STUDENT,
                        "first_name": row.get("name", ""),
                    },
                )
                Student.objects.update_or_create(
                    roll_no=row["roll_no"].strip(),
                    defaults={
                        "user": user,
                        "name": row.get("name", ""),
                        "block": block,
                        "room_no": row.get("room_no", ""),
                        "mess_allotment": row.get("mess_allotment", "General Mess"),
                        "points_balance": row.get("points_balance", 0),
                    },
                )
                created_count += 1

        return Response({"processed_records": created_count})
