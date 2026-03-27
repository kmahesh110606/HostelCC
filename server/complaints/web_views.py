from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Q
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render

from mess.models import MessMenu
from students.models import Student

from .models import Complaint, ComplaintReply, ComplaintVote


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

            if not category or category not in {choice[0] for choice in Complaint.Category.choices}:
                messages.error(request, "Please select a valid category.")
            elif not text and not uploaded:
                messages.error(request, "Add complaint text or attach image/video.")
            else:
                student = Student.objects.filter(user=request.user).first()
                Complaint.objects.create(
                    student=student,
                    author=request.user,
                    category=category,
                    text=text,
                    media=uploaded,
                    media_type=_infer_media_type(uploaded),
                )
                messages.success(request, "Post published.")
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

        if action == "vote":
            complaint = get_object_or_404(Complaint, id=request.POST.get("complaint_id"))
            direction = request.POST.get("direction", "").strip().lower()
            if direction not in {"up", "down"}:
                messages.error(request, "Invalid vote action.")
                return redirect("community-feed")

            value = ComplaintVote.Value.UPVOTE if direction == "up" else ComplaintVote.Value.DOWNVOTE
            vote, created = ComplaintVote.objects.get_or_create(
                complaint=complaint,
                user=request.user,
                defaults={"value": value},
            )
            if not created:
                if vote.value == value:
                    vote.delete()
                else:
                    vote.value = value
                    vote.save(update_fields=["value", "updated_at"])
            complaint.refresh_vote_counts()
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

    complaint_items = []
    for complaint in complaints:
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
            }
        )

    menus = MessMenu.objects.all().order_by("week_day")

    return render(
        request,
        "community/feed.html",
        {
            "complaint_items": complaint_items,
            "categories": Complaint.Category.choices,
            "query": query,
            "category_filter": category_filter,
            "media_filter": media_filter,
            "media_choices": Complaint.MediaType.choices,
            "menus": menus,
        },
    )
