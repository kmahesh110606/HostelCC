import logging
from django.shortcuts import render, redirect
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.db.models import Count
from .models import (
    ItemType,
    Venue,
    ChairSubmission,
    ClockRoomSubmission,
    SubmissionAuditLog,
)
from students.models import Student
from hostels.models import HostelBlock
from laundry.qr_utils import build_qr_svg

logger = logging.getLogger(__name__)


def _is_admin(user) -> bool:
    return getattr(user, "role", "") == "ADMIN"


@login_required
def admin_dashboard(request):
    """Admin dashboard for QR checkout system"""
    if not _is_admin(request.user):
        return redirect('home')
    
    # Statistics
    total_chairs_submitted = ChairSubmission.objects.count()
    damaged_chairs = ChairSubmission.objects.filter(status='damaged').count()
    total_items_submitted = ClockRoomSubmission.objects.count()
    total_venues = Venue.objects.filter(is_active=True).count()
    total_students = Student.objects.count()
    
    # Recent submissions
    recent_chairs = ChairSubmission.objects.select_related('student')[:10]
    recent_items = ClockRoomSubmission.objects.select_related(
        'student', 'item_type', 'current_venue'
    ).order_by('-submitted_at')[:10]
    
    # Venue status
    venues = Venue.objects.filter(is_active=True).values(
        'id', 'name', 'item_count', 'max_capacity'
    )
    item_types = ItemType.objects.filter(is_active=True).order_by("display_order", "name")
    
    context = {
        'total_chairs_submitted': total_chairs_submitted,
        'damaged_chairs': damaged_chairs,
        'total_items_submitted': total_items_submitted,
        'total_venues': total_venues,
        'total_students': total_students,
        'chair_submission_rate': f"{(total_chairs_submitted / total_students * 100):.1f}%" if total_students else "0%",
        'recent_chairs': recent_chairs,
        'recent_items': recent_items,
        'venues': venues,
        'item_types': item_types,
    }
    
    return render(request, 'checkout/admin_dashboard.html', context)


@login_required
def chair_scanner(request):
    """Chair submission scanning interface"""
    if not _is_admin(request.user):
        return redirect('home')
    
    item_types = ItemType.objects.filter(is_active=True)
    
    context = {
        'page_title': 'Chair Submission',
        'item_types': item_types,
    }
    
    return render(request, 'checkout/chair_scanner.html', context)


@login_required
def item_scanner(request, item_type):
    """Item submission scanning interface"""
    if not _is_admin(request.user):
        return redirect('home')
    
    try:
        selected_item = ItemType.objects.get(code=item_type, is_active=True)
    except ItemType.DoesNotExist:
        return redirect('checkout-admin-dashboard')
    
    venues = Venue.objects.filter(is_active=True)
    item_types = ItemType.objects.filter(is_active=True)
    blocks = HostelBlock.objects.all().order_by("name")
    
    context = {
        'page_title': f'{selected_item.name} Submission',
        'selected_item': selected_item,
        'venues': venues,
        'all_item_types': item_types,
        'blocks': blocks,
    }
    
    return render(request, 'checkout/item_scanner.html', context)


@login_required
def submissions_list(request):
    """View all submissions"""
    if not _is_admin(request.user):
        return redirect('home')
    
    # Get filters from request
    student_search = request.GET.get('student', '').strip()
    item_filter = request.GET.get('item', '')
    venue_filter = request.GET.get('venue', '')
    
    submissions = ClockRoomSubmission.objects.select_related(
        'student', 'item_type', 'current_venue', 'scanned_by_admin'
    ).order_by('-submitted_at')
    
    if student_search:
        submissions = submissions.filter(
            student__roll_no__icontains=student_search
        ) | submissions.filter(
            student__name__icontains=student_search
        )
    
    if item_filter:
        submissions = submissions.filter(item_type__code=item_filter)
    
    if venue_filter:
        submissions = submissions.filter(current_venue_id=venue_filter)
    
    item_types = ItemType.objects.filter(is_active=True)
    venues = Venue.objects.filter(is_active=True)
    
    context = {
        'submissions': submissions,
        'item_types': item_types,
        'venues': venues,
        'current_item_filter': item_filter,
        'current_venue_filter': venue_filter,
        'student_search': student_search,
    }
    
    return render(request, 'checkout/submissions_list.html', context)


@login_required
def venue_management(request):
    """Manage venues"""
    if not _is_admin(request.user):
        return redirect('home')
    
    venues = Venue.objects.all().order_by('-updated_at')
    item_stats = ClockRoomSubmission.objects.values('current_venue__name').annotate(
        count=Count('id')
    )
    
    context = {
        'venues': venues,
        'item_stats': item_stats,
    }
    
    return render(request, 'checkout/venue_management.html', context)


@login_required
def student_portal(request):
    """Student portal to view submission status"""
    try:
        student = Student.objects.get(user=request.user)
    except Student.DoesNotExist:
        return redirect('home')
    
    # Get chair submission
    chair_submission = ChairSubmission.objects.filter(student=student).first()
    
    # Get clock room submissions
    submissions = ClockRoomSubmission.objects.filter(
        student=student
    ).select_related('item_type', 'current_venue').order_by('-submitted_at')
    
    context = {
        'student': student,
        'chair_submission': chair_submission,
        'submissions': submissions,
        'can_submit_items': chair_submission is not None,
        'student_qr_svg': build_qr_svg(student.roll_no),
        'student_qr_payload': student.roll_no,
    }
    
    return render(request, 'checkout/student_portal.html', context)
