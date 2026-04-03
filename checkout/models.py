import uuid
from django.db import models
from django.utils import timezone
from django.core.exceptions import ValidationError
from django.conf import settings
from students.models import Student
from hostels.models import HostelBlock


class ItemType(models.Model):
    """Item types students can submit to clock rooms"""
    
    ITEM_CHOICES = [
        ('mattress', 'Mattress'),
        ('bucket', 'Bucket'),
        ('bags_suitcase', 'Bags/Suitcase'),
        ('carton_box', 'Carton Box'),
        ('others', 'Others'),
    ]
    
    code = models.CharField(max_length=50, unique=True, choices=ITEM_CHOICES)
    name = models.CharField(max_length=100)
    display_order = models.IntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['display_order', 'name']
    
    def __str__(self):
        return self.name


class Venue(models.Model):
    """Storage venues/clock rooms for item submission"""
    
    name = models.CharField(max_length=200, db_index=True)
    description = models.TextField(blank=True)
    location = models.CharField(max_length=200, blank=True)
    max_capacity = models.IntegerField(null=True, blank=True)
    
    # Track items in this venue
    item_count = models.IntegerField(default=0)
    
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-updated_at', 'name']
    
    def __str__(self):
        return self.name


class ChairSubmission(models.Model):
    """Track chair submission as mandatory first step"""
    
    CHAIR_STATUS_CHOICES = [
        ('perfect', 'Perfect Condition'),
        ('damaged', 'Damaged'),
    ]
    
    student = models.OneToOneField(Student, on_delete=models.CASCADE, related_name='chair_submission')
    qr_token = models.CharField(max_length=100, unique=True, default=uuid.uuid4, editable=False, db_index=True)
    status = models.CharField(max_length=20, choices=CHAIR_STATUS_CHOICES, default='perfect')
    submitted_at = models.DateTimeField(auto_now_add=True)
    submitted_by_admin = models.ForeignKey(
        settings.AUTH_USER_MODEL, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True,
        related_name='chair_submissions_processed'
    )
    notes = models.TextField(blank=True, help_text="Admin notes if chair is damaged")
    
    class Meta:
        ordering = ['-submitted_at']
    
    def __str__(self):
        return f"{self.student.roll_no} - Chair {self.status}"


class ClockRoomSubmission(models.Model):
    """Track item submissions to clock rooms"""
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='clock_room_submissions')
    item_type = models.ForeignKey(ItemType, on_delete=models.CASCADE)
    venue = models.ForeignKey(Venue, on_delete=models.SET_NULL, null=True, blank=True)
    hostel_block = models.ForeignKey(HostelBlock, on_delete=models.SET_NULL, null=True, blank=True)
    
    # Token management
    token_number = models.CharField(max_length=50, unique=True, db_index=True)
    qr_code_data = models.TextField(blank=True)  # Store QR code data/reference
    
    # Chair submission validation
    chair_submission = models.ForeignKey(ChairSubmission, on_delete=models.SET_NULL, null=True, blank=True)
    
    # Timestamps
    submitted_at = models.DateTimeField(auto_now_add=True)
    scanned_by_admin = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='items_scanned'
    )
    
    # Relocation tracking
    current_venue = models.ForeignKey(
        Venue,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='current_items'
    )
    relocated_at = models.DateTimeField(null=True, blank=True)
    relocated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='items_relocated'
    )
    
    class Meta:
        ordering = ['-submitted_at']
        indexes = [
            models.Index(fields=['student', 'item_type']),
            models.Index(fields=['token_number']),
        ]
    
    def __str__(self):
        return f"{self.student.roll_no} - {self.item_type.name} - {self.token_number}"
    
    def clean(self):
        # Validate chair submission exists
        if not self.chair_submission_id and self.student_id:
            chair = ChairSubmission.objects.filter(student_id=self.student_id).first()
            if not chair:
                raise ValidationError("Chair must be submitted before clock room submission.")


class SubmissionAuditLog(models.Model):
    """Audit log for all submission changes"""
    
    ACTION_CHOICES = [
        ('chair_submit', 'Chair Submitted'),
        ('item_submit', 'Item Submitted'),
        ('venue_update', 'Venue Updated'),
        ('relocation', 'Item Relocated'),
        ('viewed', 'Student Viewed Portal'),
    ]
    
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='audit_logs')
    action = models.CharField(max_length=20, choices=ACTION_CHOICES)
    submission = models.ForeignKey(
        ClockRoomSubmission, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True,
        related_name='audit_logs'
    )
    performed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='audit_actions'
    )
    details = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return f"{self.student.roll_no} - {self.get_action_display()}"
