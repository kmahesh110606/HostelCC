import logging
from django.db.models import Q
from django.utils import timezone
from django.db import transaction
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from students.models import Student
from users.permissions import IsAdmin
from .models import (
    ItemType,
    Venue,
    ChairSubmission,
    ClockRoomSubmission,
    SubmissionAuditLog,
)
from .serializers import (
    ItemTypeSerializer,
    VenueSerializer,
    ChairSubmissionSerializer,
    ClockRoomSubmissionSerializer,
    SubmissionAuditLogSerializer,
)

logger = logging.getLogger(__name__)


def _resolve_student_from_qr_token(qr_token: str):
    token = (qr_token or "").strip()
    if not token:
        return None
    return Student.objects.filter(Q(user__username__iexact=token) | Q(roll_no__iexact=token)).first()


class ItemTypeViewSet(viewsets.ModelViewSet):
    """Manage item types"""
    queryset = ItemType.objects.filter(is_active=True)
    serializer_class = ItemTypeSerializer
    permission_classes = [IsAuthenticated, IsAdmin]


class VenueViewSet(viewsets.ModelViewSet):
    """Manage venues/clock rooms"""
    queryset = Venue.objects.filter(is_active=True)
    serializer_class = VenueSerializer
    permission_classes = [IsAuthenticated, IsAdmin]


class ChairSubmissionViewSet(viewsets.ModelViewSet):
    """Admin operations for chair submissions"""
    queryset = ChairSubmission.objects.all()
    serializer_class = ChairSubmissionSerializer
    permission_classes = [IsAuthenticated, IsAdmin]
    
    @action(detail=False, methods=['post'])
    def process_chair_scan(self, request):
        """Process QR code scan for chair submission"""
        qr_token = request.data.get('qr_token', '').strip()
        chair_status = request.data.get('status', 'perfect').lower()
        notes = request.data.get('notes', '').strip()
        
        if not qr_token:
            return Response(
                {'error': 'QR token is required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if chair_status not in ['perfect', 'damaged']:
            return Response(
                {'error': 'Invalid chair status'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        student = _resolve_student_from_qr_token(qr_token)
        if not student:
            return Response(
                {'error': 'Student not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        with transaction.atomic():
            chair_submission, created = ChairSubmission.objects.update_or_create(
                student=student,
                defaults={
                    'status': chair_status,
                    'submitted_by_admin': request.user,
                    'notes': notes,
                }
            )
            
            SubmissionAuditLog.objects.create(
                student=student,
                action='chair_submit',
                performed_by=request.user,
                details={'status': chair_status}
            )
        
        serializer = ChairSubmissionSerializer(chair_submission)
        return Response({
            'message': 'Chair submission recorded',
            'data': serializer.data
        }, status=status.HTTP_201_CREATED)


class ClockRoomSubmissionViewSet(viewsets.ModelViewSet):
    """Manage clock room submissions"""
    queryset = ClockRoomSubmission.objects.all()
    serializer_class = ClockRoomSubmissionSerializer
    permission_classes = [IsAuthenticated, IsAdmin]

    def get_queryset(self):
        queryset = super().get_queryset().select_related(
            "student",
            "item_type",
            "venue",
            "current_venue",
            "hostel_block",
            "chair_submission",
        )
        q = (self.request.query_params.get("q") or "").strip()
        item = (self.request.query_params.get("item") or "").strip()
        venue = (self.request.query_params.get("venue") or "").strip()
        if q:
            queryset = queryset.filter(Q(student__roll_no__icontains=q) | Q(student__name__icontains=q))
        if item:
            queryset = queryset.filter(item_type__code__iexact=item)
        if venue:
            queryset = queryset.filter(current_venue_id=venue)
        return queryset
    
    def get_next_token_number(self):
        """Generate next unique sequential token"""
        today = timezone.localdate()
        count = ClockRoomSubmission.objects.filter(submitted_at__date=today).count() + 1
        token = f"CLK-{today.strftime('%Y%m%d')}-{count:05d}"
        return token
    
    @action(detail=False, methods=['post'])
    def process_item_scan(self, request):
        """Process QR scan for item submission to clock room"""
        qr_token = request.data.get('qr_token', '').strip()
        item_type_id = request.data.get('item_type_id')
        venue_id = request.data.get('venue_id')
        hostel_block_id = request.data.get('hostel_block_id')
        
        if not all([qr_token, item_type_id, venue_id, hostel_block_id]):
            return Response(
                {'error': 'Missing required fields: qr_token, item_type_id, venue_id, hostel_block_id'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        student = _resolve_student_from_qr_token(qr_token)
        if not student:
            return Response(
                {'error': 'Student not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Check if chair is submitted
        try:
            chair_submission = ChairSubmission.objects.get(student=student)
        except ChairSubmission.DoesNotExist:
            return Response(
                {'error': 'Chair must be submitted first before item submission'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            item_type = ItemType.objects.get(id=item_type_id)
            venue = Venue.objects.get(id=venue_id)
        except (ItemType.DoesNotExist, Venue.DoesNotExist):
            return Response(
                {'error': 'Invalid item type or venue'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Check for duplicate submission of same item
        existing = ClockRoomSubmission.objects.filter(
            student=student,
            item_type=item_type,
            submitted_at__date=timezone.localdate()
        ).first()
        
        if existing:
            return Response(
                {'error': f'Item {item_type.name} already submitted today. Token: {existing.token_number}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        with transaction.atomic():
            token_number = self.get_next_token_number()
            
            submission = ClockRoomSubmission.objects.create(
                student=student,
                item_type=item_type,
                venue=venue,
                hostel_block_id=hostel_block_id,
                current_venue=venue,
                token_number=token_number,
                chair_submission=chair_submission,
                scanned_by_admin=request.user,
            )
            
            # Update venue item count
            venue.item_count = venue.item_count + 1
            venue.save(update_fields=['item_count'])
            
            SubmissionAuditLog.objects.create(
                student=student,
                action='item_submit',
                submission=submission,
                performed_by=request.user,
                details={
                    'item_type': item_type.name,
                    'venue': venue.name,
                    'token': token_number
                }
            )
        
        serializer = ClockRoomSubmissionSerializer(submission)
        return Response({
            'message': f'Item submitted successfully. Token: {token_number}',
            'data': serializer.data
        }, status=status.HTTP_201_CREATED)
    
    @action(detail=False, methods=['post'])
    def relocate_item(self, request):
        """Relocate an item to a different venue"""
        submission_id = request.data.get('submission_id')
        new_venue_id = request.data.get('new_venue_id')
        notes = request.data.get('notes', '').strip()
        
        if not all([submission_id, new_venue_id]):
            return Response(
                {'error': 'submission_id and new_venue_id are required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            submission = ClockRoomSubmission.objects.get(id=submission_id)
            new_venue = Venue.objects.get(id=new_venue_id)
        except (ClockRoomSubmission.DoesNotExist, Venue.DoesNotExist):
            return Response(
                {'error': 'Invalid submission or venue'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        with transaction.atomic():
            old_venue = submission.current_venue
            submission.current_venue = new_venue
            submission.relocated_at = timezone.now()
            submission.relocated_by = request.user
            submission.save()
            
            # Update venue counts
            if old_venue:
                old_venue.item_count = max(0, old_venue.item_count - 1)
                old_venue.save(update_fields=['item_count'])
            
            new_venue.item_count = new_venue.item_count + 1
            new_venue.save(update_fields=['item_count'])
            
            SubmissionAuditLog.objects.create(
                student=submission.student,
                action='relocation',
                submission=submission,
                performed_by=request.user,
                details={
                    'from_venue': old_venue.name if old_venue else 'Unknown',
                    'to_venue': new_venue.name,
                    'notes': notes
                }
            )
        
        serializer = ClockRoomSubmissionSerializer(submission)
        return Response({
            'message': 'Item relocated successfully',
            'data': serializer.data
        }, status=status.HTTP_200_OK)


class StudentCheckoutStatusView(APIView):
    """Get student checkout status"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        """Get current student's checkout status"""
        try:
            student = Student.objects.get(user=request.user)
        except Student.DoesNotExist:
            return Response(
                {'error': 'Student profile not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Get chair submission
        chair_submission = ChairSubmission.objects.filter(student=student).first()
        
        # Get all clock room submissions
        submissions = ClockRoomSubmission.objects.filter(student=student).order_by('-submitted_at')
        
        items_submitted = []
        for submission in submissions:
            items_submitted.append({
                'id': submission.id,
                'item_type': submission.item_type.name,
                'venue': submission.current_venue.name if submission.current_venue else 'Not assigned',
                'token': submission.token_number,
                'submitted_at': submission.submitted_at.isoformat(),
                'status': 'relocated' if submission.relocated_at else 'submitted'
            })
        
        messages = []
        if not chair_submission:
            messages.append("Please submit your chair first")
        elif chair_submission.status == 'damaged':
            messages.append(f"Note: Your chair was marked as damaged - {chair_submission.notes}")
        
        data = {
            'student_id': student.id,
            'student_name': student.name,
            'student_roll': student.roll_no,
            'chair_submitted': chair_submission is not None,
            'chair_status': chair_submission.status if chair_submission else None,
            'chair_submitted_at': chair_submission.submitted_at.isoformat() if chair_submission else None,
            'items_submitted': items_submitted,
            'qr_token': str(chair_submission.qr_token) if chair_submission else '',
            'messages': messages,
        }
        
        if not request.query_params.get("silent"):
            SubmissionAuditLog.objects.create(
                student=student,
                action='viewed',
                performed_by=request.user
            )
        
        return Response(data, status=status.HTTP_200_OK)


class SubmissionAuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    """View audit logs"""
    queryset = SubmissionAuditLog.objects.all()
    serializer_class = SubmissionAuditLogSerializer
    permission_classes = [IsAuthenticated, IsAdmin]
    
    def get_queryset(self):
        queryset = super().get_queryset()
        student_id = self.request.query_params.get('student_id')
        if student_id:
            queryset = queryset.filter(student_id=student_id)
        return queryset


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def verify_qr_token(request):
    """Verify if QR token belongs to a student"""
    qr_token = request.data.get('qr_token', '').strip()
    
    if not qr_token:
        return Response(
            {'error': 'QR token is required'},
            status=status.HTTP_400_BAD_REQUEST
        )
    
    try:
        student = _resolve_student_from_qr_token(qr_token)
        
        if not student:
            return Response(
                {'error': 'Student not found'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Get chair submission
        chair_sub = ChairSubmission.objects.filter(student=student).first()
        
        return Response({
            'student_id': student.id,
            'student_name': student.name,
            'student_roll': student.roll_no,
            'chair_submitted': chair_sub is not None,
            'qr_token': qr_token
        }, status=status.HTTP_200_OK)
    
    except Exception as e:
        logger.exception("Error verifying QR token")
        return Response(
            {'error': 'Error verifying QR token'},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )
