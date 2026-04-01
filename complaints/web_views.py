import csv
import json

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Q
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.core.paginator import Paginator

from students.models import Student

from .models import Complaint, ComplaintReply, ComplaintVote


def _can_manage_complaint(user, complaint: Complaint) -> bool:
    if not user.is_authenticated:
        return False
    if user.role in {"ADMIN", "WARDEN"}:
        return True
    return user.role == "SUPERVISOR" and bool(user.department and user.department == complaint.category)


def _log_status_activity(complaint: Complaint, actor, new_status: str) -> None:
    actor_name = actor.get_full_name().strip() or actor.username
    ComplaintReply.objects.create(
        complaint=complaint,
        author=actor,
        text=f"[Status Update] {actor_name} set status to {complaint.get_status_display()}.",
    )


def _infer_media_type(uploaded_file) -> str:
    if not uploaded_file:
        return Complaint.MediaType.TEXT

    lowered = uploaded_file.name.lower()
    if lowered.endswith((".png", ".jpg", ".jpeg", ".gif", ".webp")):
        return Complaint.MediaType.IMAGE
    if lowered.endswith((".mp4", ".mov", ".webm", ".mkv")):
        return Complaint.MediaType.VIDEO
    return Complaint.MediaType.TEXT


@login_required
def community_rules(request: HttpRequest) -> HttpResponse:
    if request.method == "POST":
        if request.POST.get("agree") == "yes":
            request.session["community_rules_agreed"] = True
            return redirect("community-feed")
        messages.error(request, "You must agree to continue.")

    return render(
        request,
        "community/rules.html",
        {
            "categories": Complaint.Category.choices,
        },
    )


@login_required
def community_feed(request: HttpRequest) -> HttpResponse:
    if not request.session.get("community_rules_agreed"):
        return redirect("community-rules")

    if request.method == "POST":
        action = request.POST.get("action", "").strip()

        if action == "create":
            category = request.POST.get("category", "").strip()
            text = request.POST.get("text", "").strip()
            uploaded = request.FILES.get("media")

            error = None
            if not category or category not in {choice[0] for choice in Complaint.Category.choices}:
                error = "Please select a valid category."
            elif not text and not uploaded:
                error = "Add complaint text or attach image/video."
            
            if error:
                if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
                    return JsonResponse({'success': False, 'error': error})
                messages.error(request, error)
            else:
                student = Student.objects.filter(user=request.user).first()
                complaint = Complaint.objects.create(
                    student=student,
                    author=request.user,
                    category=category,
                    text=text,
                    media=uploaded,
                    media_type=_infer_media_type(uploaded),
                )
                if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
                    return JsonResponse({'success': True, 'complaint_id': complaint.id})
                messages.success(request, "Post published.")
            
            if not (request.headers.get('X-Requested-With') == 'XMLHttpRequest'):
                return redirect("community-feed")

        if action == "comment":
            complaint = get_object_or_404(Complaint, id=request.POST.get("complaint_id"))
            text = request.POST.get("comment_text", "").strip()
            if text:
                ComplaintReply.objects.create(complaint=complaint, author=request.user, text=text)
                messages.success(request, "Comment posted.")
            else:
                messages.error(request, "Comment cannot be empty.")
            return redirect("community-feed")

        if action == "set_status":
            complaint = get_object_or_404(Complaint, id=request.POST.get("complaint_id"))
            requested_status = request.POST.get("status", "").strip().upper()
            valid_statuses = {choice[0] for choice in Complaint.Status.choices}

            if not _can_manage_complaint(request.user, complaint):
                messages.error(request, "You can only manage complaints for your department unless you are a warden/admin.")
            elif requested_status not in valid_statuses:
                messages.error(request, "Invalid status selected.")
            else:
                if complaint.status != requested_status:
                    complaint.status = requested_status
                    complaint.save(update_fields=["status"])
                    _log_status_activity(complaint, request.user, requested_status)
                messages.success(request, "Complaint status updated.")
            return redirect("community-feed")

        if action == "vote":
            complaint = get_object_or_404(Complaint, id=request.POST.get("complaint_id"))
            direction = request.POST.get("direction", "").strip().lower()
            if direction not in {"up", "down"}:
                if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
                    return JsonResponse({'success': False, 'error': 'Invalid vote action'})
                messages.error(request, "Invalid vote action.")
                return redirect("community-feed")

            value = ComplaintVote.Value.UPVOTE if direction == "up" else ComplaintVote.Value.DOWNVOTE
            vote, created = ComplaintVote.objects.get_or_create(
                complaint=complaint,
                user=request.user,
                defaults={"value": value},
            )
            
            user_vote = None
            if not created:
                if vote.value == value:
                    vote.delete()
                    user_vote = None
                else:
                    vote.value = value
                    vote.save(update_fields=["value", "updated_at"])
                    user_vote = direction
            else:
                user_vote = direction
            
            complaint.refresh_vote_counts()
            
            # Return JSON for AJAX requests
            if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
                return JsonResponse({
                    'success': True,
                    'upvotes': complaint.upvotes,
                    'downvotes': complaint.downvotes,
                    'user_vote': user_vote,
                })
            
            return redirect("community-feed")

        if action == "delete":
            complaint = get_object_or_404(Complaint, id=request.POST.get("complaint_id"))
            is_owner = complaint.author_id == request.user.id or bool(
                complaint.student and complaint.student.user_id == request.user.id
            )
            if request.user.role == "ADMIN" or is_owner:
                complaint.delete()
                messages.success(request, "Post deleted.")
            else:
                messages.error(request, "You do not have permission to delete this post.")
            return redirect("community-feed")

    query = request.GET.get("q", "").strip()
    category_filter = request.GET.get("category", "").strip()
    media_filter = request.GET.get("media_type", "").strip()
    status_filter = request.GET.get("status", "").strip().upper()
    block_filter = request.GET.get("block", "").strip().upper()
    sort_by = request.GET.get("sort", "newest").strip().lower()

    complaints = Complaint.objects.select_related("student", "student__block", "author").prefetch_related(
        "replies",
        "replies__author",
    )

    if query:
        complaints = complaints.filter(Q(text__icontains=query) | Q(author__username__icontains=query))
    if category_filter:
        complaints = complaints.filter(category=category_filter)
    if media_filter:
        complaints = complaints.filter(media_type=media_filter)
    if block_filter:
        complaints = complaints.filter(student__block__block_name=block_filter)

    is_supervisor = request.user.role == "SUPERVISOR"
    if is_supervisor and request.user.department:
        complaints = complaints.filter(category=request.user.department)

    active_scope = complaints
    if status_filter:
        complaints = complaints.filter(status=status_filter)

    if sort_by == "oldest":
        complaints = complaints.order_by("created_at")
    elif sort_by == "upvotes":
        complaints = complaints.order_by("-upvotes", "-created_at")
    else:
        complaints = complaints.order_by("-created_at")

    # Paginate at QuerySet level BEFORE building complaint_items to avoid loading all records into memory
    page_num = int(request.GET.get('page', 1))
    paginator = Paginator(complaints, 10)  # 10 items per page
    page_obj = paginator.get_page(page_num)
    
    complaint_items = []
    for complaint in page_obj:
        author_name = "Unknown"
        if complaint.author:
            full_name = complaint.author.get_full_name().strip()
            author_name = full_name or complaint.author.username
        elif complaint.student:
            author_name = complaint.student.name

        complaint_items.append(
            {
                "obj": complaint,
                "author_name": author_name,
                "registration_no": complaint.student.roll_no if complaint.student else "",
                "block_name": complaint.student.block.block_name if complaint.student and complaint.student.block else "",
                "room_no": complaint.student.room_no if complaint.student else "",
                "can_delete": request.user.role == "ADMIN"
                or complaint.author_id == request.user.id
                or bool(complaint.student and complaint.student.user_id == request.user.id),
                "can_manage": _can_manage_complaint(request.user, complaint),
                "status_label": complaint.status_display_label,
            }
        )

    active_complaints = active_scope.filter(status=Complaint.Status.OPEN)[:12]

    # Handle AJAX/JSON requests
    if request.GET.get('ajax') == '1':
        
        items_data = []
        for item in complaint_items:
            complaint = item['obj']
            items_data.append({
                'id': complaint.id,
                'category': complaint.get_category_display(),
                'status': complaint.status,
                'status_label': complaint.status_display_label,
                'text': complaint.text,
                'author_name': item['author_name'],
                'block_name': item['block_name'],
                'registration_no': item['registration_no'],
                'created_at': complaint.created_at.isoformat(),
                'upvotes': complaint.upvotes,
                'downvotes': complaint.downvotes,
                'reply_count': complaint.replies.count(),
                'media': complaint.media.url if complaint.media else None,
                'media_type': complaint.media_type,
                'can_manage': item['can_manage'],
            })
        
        return JsonResponse({
            'items': items_data,
            'total': paginator.count,
            'has_more': page_obj.has_next(),
            'page': page_obj.number,
        })

    return render(
        request,
        "community/feed.html",
        {
            "complaint_items": complaint_items,
            "categories": Complaint.Category.choices,
            "query": query,
            "category_filter": category_filter,
            "media_filter": media_filter,
            "status_filter": status_filter,
            "block_filter": block_filter,
            "sort_by": sort_by,
            "media_choices": Complaint.MediaType.choices,
            "status_choices": Complaint.Status.choices,
            "block_choices": sorted({choice for choice in Student.objects.values_list("block__block_name", flat=True).distinct() if choice}),
            "active_complaints": active_complaints,
            "show_management_panel": request.user.role in {"SUPERVISOR", "WARDEN", "ADMIN"},
        },
    )


@login_required
def download_active_complaints_csv(request: HttpRequest) -> HttpResponse:
    if request.user.role != "ADMIN":
        messages.error(request, "Only admin can download complaints reports.")
        return redirect("dashboard-router")

    complaints = (
        Complaint.objects.select_related("student", "student__block", "author")
        .prefetch_related("replies", "replies__author")
        .filter(status__in=[Complaint.Status.OPEN, Complaint.Status.IN_PROGRESS])
        .order_by("-created_at")
    )

    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = 'attachment; filename="complaints_open_in_progress.csv"'

    writer = csv.writer(response)
    writer.writerow(
        [
            "complaint_id",
            "category",
            "category_label",
            "status",
            "status_label",
            "text",
            "media_type",
            "media_url",
            "warden_tag",
            "upvotes",
            "downvotes",
            "created_at",
            "author_id",
            "author_username",
            "author_full_name",
            "author_email",
            "student_id",
            "student_roll_no",
            "student_name",
            "student_block",
            "student_room_no",
            "reply_count",
            "replies",
        ]
    )

    for item in complaints:
        author = item.author
        student = item.student
        replies = []
        for reply in item.replies.all().order_by("created_at"):
            reply_author = reply.author.get_full_name().strip() or reply.author.username
            cleaned_text = " ".join((reply.text or "").splitlines()).strip()
            replies.append(f"{reply.created_at.isoformat()} | {reply_author} | {cleaned_text}")

        media_url = request.build_absolute_uri(item.media.url) if item.media else ""

        writer.writerow(
            [
                item.id,
                item.category,
                item.get_category_display(),
                item.status,
                item.get_status_display(),
                item.text,
                item.media_type,
                media_url,
                item.warden_tag,
                item.upvotes,
                item.downvotes,
                item.created_at.isoformat() if item.created_at else "",
                author.id if author else "",
                author.username if author else "",
                author.get_full_name().strip() if author else "",
                author.email if author else "",
                student.id if student else "",
                student.roll_no if student else "",
                student.name if student else "",
                student.block.block_name if student and student.block else "",
                student.room_no if student else "",
                len(replies),
                json.dumps(replies),
            ]
        )

    return response
