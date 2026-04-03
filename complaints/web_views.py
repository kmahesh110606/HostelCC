import csv

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Count, Prefetch, Q
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.core.paginator import Paginator
from django.template.loader import render_to_string

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


def _is_xhr(request: HttpRequest) -> bool:
    return request.headers.get("X-Requested-With") == "XMLHttpRequest"


def _build_community_feed_scope(request: HttpRequest):
    query = request.GET.get("q", "").strip()
    category_filter = request.GET.get("category", "").strip()
    media_filter = request.GET.get("media_type", "").strip()
    status_filter = request.GET.get("status", "").strip().upper()
    block_filter = request.GET.get("block", "").strip().upper()
    sort_by = request.GET.get("sort", "newest").strip().lower()

    replies_qs = ComplaintReply.objects.select_related("author").order_by("created_at")
    complaints = (
        Complaint.objects.select_related("student", "student__block", "author")
        .annotate(reply_count=Count("replies"))
        .prefetch_related(Prefetch("replies", queryset=replies_qs))
    )

    if query:
        complaints = complaints.filter(Q(text__icontains=query) | Q(author__username__icontains=query))
    if category_filter:
        complaints = complaints.filter(category=category_filter)
    if media_filter:
        complaints = complaints.filter(media_type=media_filter)
    if block_filter:
        complaints = complaints.filter(student__block__block_name=block_filter)

    if request.user.role == "SUPERVISOR" and request.user.department:
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

    return {
        "query": query,
        "category_filter": category_filter,
        "media_filter": media_filter,
        "status_filter": status_filter,
        "block_filter": block_filter,
        "sort_by": sort_by,
        "complaints": complaints,
        "active_scope": active_scope,
    }


def _complaint_matches_current_filters(request: HttpRequest, complaint: Complaint) -> bool:
    query = request.GET.get("q", "").strip().lower()
    category_filter = request.GET.get("category", "").strip()
    media_filter = request.GET.get("media_type", "").strip()
    status_filter = request.GET.get("status", "").strip().upper()
    block_filter = request.GET.get("block", "").strip().upper()

    if query:
        complaint_text = (complaint.text or "").lower()
        author_username = complaint.author.username.lower() if complaint.author else ""
        if query not in complaint_text and query not in author_username:
            return False

    if category_filter and complaint.category != category_filter:
        return False
    if media_filter and complaint.media_type != media_filter:
        return False
    if status_filter and complaint.status != status_filter:
        return False
    if block_filter:
        complaint_block = complaint.student.block.block_name if complaint.student and complaint.student.block else ""
        if complaint_block.upper() != block_filter:
            return False

    if request.user.role == "SUPERVISOR" and request.user.department and complaint.category != request.user.department:
        return False

    return True


def _build_community_item(request: HttpRequest, complaint: Complaint) -> dict:
    complaint.reply_count = getattr(complaint, "reply_count", 0)
    author_name = "Unknown"
    if complaint.author:
        full_name = complaint.author.get_full_name().strip()
        author_name = full_name or complaint.author.username
    elif complaint.student:
        author_name = complaint.student.name

    return {
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


def _build_active_complaints_payload(request: HttpRequest) -> list[dict]:
    scope = _build_community_feed_scope(request)
    active_complaints = scope["active_scope"].filter(status=Complaint.Status.OPEN)[:12]
    payload = []
    for complaint in active_complaints:
        payload.append(_serialize_active_complaint(complaint))
    return payload


def _serialize_active_complaint(complaint: Complaint) -> dict:
    return {
        "id": complaint.id,
        "category_label": complaint.get_category_display(),
        "text": complaint.text or "",
    }


def _render_community_card(request: HttpRequest, complaint: Complaint) -> str:
    item = _build_community_item(request, complaint)
    return render_to_string(
        "community/_complaint_card.html",
        {
            "item": item,
            "status_choices": Complaint.Status.choices,
        },
        request=request,
    )


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

    scope = _build_community_feed_scope(request)

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
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": error}, status=400)
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
                if _is_xhr(request):
                    current_page = (request.GET.get("page", "1") or "1").strip()
                    can_insert_in_view = current_page in {"", "1"} and scope["sort_by"] == "newest"
                    return JsonResponse(
                        {
                            "success": True,
                            "complaint_id": complaint.id,
                            "visible": _complaint_matches_current_filters(request, complaint) and can_insert_in_view,
                            "card_html": _render_community_card(request, complaint),
                            "active_complaints": _build_active_complaints_payload(request),
                        }
                    )
                messages.success(request, "Post published.")
            
            if not _is_xhr(request):
                return redirect("community-feed")

        if action == "comment":
            complaint_id_raw = (request.POST.get("complaint_id") or "").strip()
            if not complaint_id_raw.isdigit():
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": "Invalid complaint selected."}, status=400)
                messages.error(request, "Invalid complaint selected.")
                return redirect("community-feed")

            complaint = get_object_or_404(Complaint, id=int(complaint_id_raw))
            text = request.POST.get("comment_text", "").strip()
            if text:
                reply = ComplaintReply.objects.create(complaint=complaint, author=request.user, text=text)
                if _is_xhr(request):
                    author_name = reply.author.get_full_name().strip() or reply.author.username
                    return JsonResponse(
                        {
                            "success": True,
                            "reply_count": complaint.replies.count(),
                            "comment": {
                                "author_name": author_name,
                                "text": reply.text,
                                "created_at": reply.created_at.isoformat(),
                                "created_at_label": reply.created_at.strftime("%d %b %Y, %I:%M %p"),
                                "is_activity": reply.text.startswith("[Status Update]"),
                            },
                        }
                    )
                messages.success(request, "Comment posted.")
            else:
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": "Comment cannot be empty."}, status=400)
                messages.error(request, "Comment cannot be empty.")
            return redirect("community-feed")

        if action == "set_status":
            complaint_id_raw = (request.POST.get("complaint_id") or "").strip()
            if not complaint_id_raw.isdigit():
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": "Invalid complaint selected."}, status=400)
                messages.error(request, "Invalid complaint selected.")
                return redirect("community-feed")

            complaint = get_object_or_404(Complaint, id=int(complaint_id_raw))
            requested_status = request.POST.get("status", "").strip().upper()
            valid_statuses = {choice[0] for choice in Complaint.Status.choices}

            if not _can_manage_complaint(request.user, complaint):
                error = "You can only manage complaints for your department unless you are a warden/admin."
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": error}, status=403)
                messages.error(request, error)
            elif requested_status not in valid_statuses:
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": "Invalid status selected."}, status=400)
                messages.error(request, "Invalid status selected.")
            else:
                if complaint.status != requested_status:
                    complaint.status = requested_status
                    complaint.save(update_fields=["status"])
                    _log_status_activity(complaint, request.user, requested_status)
                if _is_xhr(request):
                    return JsonResponse(
                        {
                            "success": True,
                            "status": complaint.status,
                            "status_label": complaint.status_display_label,
                            "visible": _complaint_matches_current_filters(request, complaint),
                            "active_complaints": _build_active_complaints_payload(request),
                        }
                    )
                messages.success(request, "Complaint status updated.")
            return redirect("community-feed")

        if action == "vote":
            complaint = get_object_or_404(Complaint, id=request.POST.get("complaint_id"))
            direction = request.POST.get("direction", "").strip().lower()
            if direction not in {"up", "down"}:
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": "Invalid vote action"}, status=400)
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
            if _is_xhr(request):
                return JsonResponse({
                    "success": True,
                    "upvotes": complaint.upvotes,
                    "downvotes": complaint.downvotes,
                    "user_vote": user_vote,
                })
            
            return redirect("community-feed")

        if action == "delete":
            complaint_id_raw = (request.POST.get("complaint_id") or "").strip()
            if not complaint_id_raw.isdigit():
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": "Invalid complaint selected."}, status=400)
                messages.error(request, "Invalid complaint selected.")
                return redirect("community-feed")

            complaint = get_object_or_404(Complaint, id=int(complaint_id_raw))
            is_owner = complaint.author_id == request.user.id or bool(
                complaint.student and complaint.student.user_id == request.user.id
            )
            if request.user.role == "ADMIN" or is_owner:
                complaint_id = complaint.id
                complaint.delete()
                if _is_xhr(request):
                    return JsonResponse(
                        {
                            "success": True,
                            "deleted_id": complaint_id,
                            "active_complaints": _build_active_complaints_payload(request),
                        }
                    )
                messages.success(request, "Post deleted.")
            else:
                error = "You do not have permission to delete this post."
                if _is_xhr(request):
                    return JsonResponse({"success": False, "error": error}, status=403)
                messages.error(request, error)
            return redirect("community-feed")

    # Paginate at QuerySet level BEFORE building complaint_items to avoid loading all records into memory
    page_num = request.GET.get('page', '1')
    complaints = scope["complaints"]
    paginator = Paginator(complaints, 10)  # 10 items per page
    page_obj = paginator.get_page(page_num)
    
    complaint_items = []
    for complaint in page_obj:
        complaint_items.append(_build_community_item(request, complaint))

    active_complaints = scope["active_scope"].filter(status=Complaint.Status.OPEN)[:12]
    query = scope["query"]
    category_filter = scope["category_filter"]
    media_filter = scope["media_filter"]
    status_filter = scope["status_filter"]
    block_filter = scope["block_filter"]
    sort_by = scope["sort_by"]

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
                'room_no': item['room_no'],
                'created_at': complaint.created_at.isoformat(),
                'upvotes': complaint.upvotes,
                'downvotes': complaint.downvotes,
                'reply_count': getattr(complaint, "reply_count", 0),
                'media': complaint.media.url if complaint.media else None,
                'media_type': complaint.media_type,
                'can_manage': item['can_manage'],
            })
        
        return JsonResponse({
            'items': items_data,
            'active_complaints': [_serialize_active_complaint(complaint) for complaint in active_complaints],
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

    group_by = (request.GET.get("group_by") or "block").strip().lower()
    if group_by not in {"block", "department"}:
        group_by = "block"

    complaints = Complaint.objects.select_related("student", "student__block").filter(
        status__in=[Complaint.Status.OPEN, Complaint.Status.IN_PROGRESS]
    )

    if group_by == "department":
        complaints = complaints.order_by("category", "student__block__block_name", "student__room_no", "student__roll_no")
        file_name = "complaints_grouped_by_department.csv"
    else:
        complaints = complaints.order_by("student__block__block_name", "student__room_no", "category", "student__roll_no")
        file_name = "complaints_grouped_by_block.csv"

    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="{file_name}"'

    writer = csv.writer(response)
    writer.writerow(["Block", "Room No", "Reg No", "Name", "Complaint", "Department", "Status", "Signature"])

    for item in complaints:
        student = item.student

        writer.writerow(
            [
                student.block.block_name if student and student.block else "",
                student.room_no if student else "",
                student.roll_no if student else "",
                student.name if student else "",
                item.text,
                item.get_category_display(),
                item.get_status_display(),
                "",
            ]
        )

    return response
