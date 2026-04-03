from rest_framework import serializers
from django.utils import timezone
from .models import (
    ItemType,
    Venue,
    ChairSubmission,
    ClockRoomSubmission,
    SubmissionAuditLog,
)
from students.models import Student
from laundry.qr_utils import build_qr_svg


class ItemTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ItemType
        fields = ['id', 'code', 'name', 'display_order', 'is_active']


class VenueSerializer(serializers.ModelSerializer):
    class Meta:
        model = Venue
        fields = ['id', 'name', 'description', 'location', 'max_capacity', 'item_count', 'is_active']


class ChairSubmissionSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    student_roll = serializers.CharField(source='student.roll_no', read_only=True)
    student_id = serializers.IntegerField(source='student.id', read_only=True)
    submitted_by_admin_name = serializers.CharField(source='submitted_by_admin.get_full_name', read_only=True)
    
    class Meta:
        model = ChairSubmission
        fields = [
            'id',
            'student',
            'student_id',
            'student_name',
            'student_roll',
            'qr_token',
            'status',
            'submitted_at',
            'submitted_by_admin',
            'submitted_by_admin_name',
            'notes',
        ]
        read_only_fields = ['qr_token', 'submitted_at']


class ClockRoomSubmissionSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    student_roll = serializers.CharField(source='student.roll_no', read_only=True)
    item_type_name = serializers.CharField(source='item_type.name', read_only=True)
    venue_name = serializers.CharField(source='current_venue.name', read_only=True)
    block_name = serializers.CharField(source='hostel_block.name', read_only=True)
    scanned_by_name = serializers.CharField(source='scanned_by_admin.get_full_name', read_only=True)
    chair_status = serializers.CharField(source='chair_submission.status', read_only=True)
    
    class Meta:
        model = ClockRoomSubmission
        fields = [
            'id',
            'student',
            'student_name',
            'student_roll',
            'item_type',
            'item_type_name',
            'venue',
            'hostel_block',
            'block_name',
            'venue_name',
            'token_number',
            'qr_code_data',
            'chair_submission',
            'chair_status',
            'submitted_at',
            'scanned_by_admin',
            'scanned_by_name',
            'current_venue',
            'relocated_at',
            'relocated_by',
        ]
        read_only_fields = [
            'token_number',
            'qr_code_data',
            'submitted_at',
            'scanned_by_admin',
            'chair_submission',
        ]


class SubmissionAuditLogSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    performed_by_name = serializers.CharField(source='performed_by.get_full_name', read_only=True)
    action_display = serializers.CharField(source='get_action_display', read_only=True)
    
    class Meta:
        model = SubmissionAuditLog
        fields = [
            'id',
            'student',
            'student_name',
            'action',
            'action_display',
            'submission',
            'performed_by',
            'performed_by_name',
            'details',
            'created_at',
        ]
        read_only_fields = ['created_at']


class StudentCheckoutStatusSerializer(serializers.Serializer):
    """Comprehensive student checkout status"""
    student_id = serializers.IntegerField()
    student_name = serializers.CharField()
    student_roll = serializers.CharField()
    chair_submitted = serializers.BooleanField()
    chair_status = serializers.CharField(allow_null=True)
    chair_submitted_at = serializers.DateTimeField(allow_null=True)
    items_submitted = serializers.ListField(child=serializers.DictField())
    qr_token = serializers.CharField()
    messages = serializers.ListField(child=serializers.CharField())


class QRScanResultSerializer(serializers.Serializer):
    """Result of QR scan operation"""
    success = serializers.BooleanField()
    message = serializers.CharField()
    student_data = StudentCheckoutStatusSerializer(required=False)
    token = serializers.CharField(required=False)
    redirect_url = serializers.CharField(required=False)


class VenueUpdateSerializer(serializers.Serializer):
    """For updating student item venues"""
    submission_id = serializers.IntegerField()
    new_venue_id = serializers.IntegerField()
    notes = serializers.CharField(required=False, allow_blank=True)
