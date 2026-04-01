from rest_framework import serializers

from .models import Complaint, ComplaintReply, ComplaintVote


class ComplaintReplySerializer(serializers.ModelSerializer):
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = ComplaintReply
        fields = ["id", "complaint", "author", "author_name", "text", "created_at"]
        read_only_fields = ["complaint", "author", "created_at"]

    def get_author_name(self, obj):
        full_name = obj.author.get_full_name().strip()
        return full_name or obj.author.username


class ComplaintSerializer(serializers.ModelSerializer):
    replies = ComplaintReplySerializer(many=True, read_only=True)
    author_name = serializers.SerializerMethodField()
    student_name = serializers.SerializerMethodField()
    registration_no = serializers.SerializerMethodField()
    block_name = serializers.SerializerMethodField()
    room_no = serializers.SerializerMethodField()
    media_url = serializers.SerializerMethodField()
    can_delete = serializers.SerializerMethodField()
    can_manage = serializers.SerializerMethodField()
    status_label = serializers.SerializerMethodField()
    user_vote = serializers.SerializerMethodField()

    class Meta:
        model = Complaint
        fields = [
            "id",
            "student",
            "author",
            "author_name",
            "student_name",
            "registration_no",
            "block_name",
            "room_no",
            "category",
            "text",
            "media",
            "media_url",
            "media_type",
            "warden_tag",
            "status",
            "status_label",
            "user_vote",
            "upvotes",
            "downvotes",
            "created_at",
            "can_delete",
            "can_manage",
            "replies",
        ]
        read_only_fields = [
            "author",
            "student",
            "status",
            "created_at",
            "upvotes",
            "downvotes",
            "media_type",
        ]

    def get_author_name(self, obj):
        if obj.author:
            full_name = obj.author.get_full_name().strip()
            return full_name or obj.author.username
        if obj.student:
            return obj.student.name
        return "Unknown"

    def validate(self, attrs):
        raw_text = attrs.get("text")
        text = raw_text.strip() if isinstance(raw_text, str) else ""
        media = attrs.get("media")
        if media is None and self.instance is not None:
            media = getattr(self.instance, "media", None)

        if not text and not media:
            raise serializers.ValidationError({"detail": "Add complaint text or attach image/video."})

        attrs["text"] = text
        return attrs

    def get_student_name(self, obj):
        return obj.student.name if obj.student else ""

    def get_registration_no(self, obj):
        return obj.student.roll_no if obj.student else ""

    def get_block_name(self, obj):
        if obj.student and obj.student.block:
            return obj.student.block.block_name
        return ""

    def get_room_no(self, obj):
        return obj.student.room_no if obj.student else ""

    def get_media_url(self, obj):
        if obj.media:
            # Return relative media URL so it works across all environments (localhost, 10.0.2.2, prod, etc.)
            return obj.media.url
        return ""

    def get_can_delete(self, obj):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False
        if request.user.role == "ADMIN":
            return True
        if obj.author_id == request.user.id:
            return True
        return bool(obj.student and obj.student.user_id == request.user.id)

    def get_can_manage(self, obj):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return False

        user = request.user
        if user.role in {"ADMIN", "WARDEN"}:
            return True
        return user.role == "SUPERVISOR" and bool(user.department and user.department == obj.category)

    def get_status_label(self, obj):
        return obj.status_display_label

    def get_user_vote(self, obj):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated:
            return "none"

        user_id = request.user.id
        prefetched_votes = getattr(obj, "_prefetched_objects_cache", {}).get("votes")
        if prefetched_votes is not None:
            for vote in prefetched_votes:
                if vote.user_id == user_id:
                    return "up" if vote.value == ComplaintVote.Value.UPVOTE else "down"
            return "none"

        vote_value = obj.votes.filter(user_id=user_id).values_list("value", flat=True).first()
        if vote_value == ComplaintVote.Value.UPVOTE:
            return "up"
        if vote_value == ComplaintVote.Value.DOWNVOTE:
            return "down"
        return "none"


class ComplaintVoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = ComplaintVote
        fields = ["id", "complaint", "user", "value", "created_at", "updated_at"]
        read_only_fields = ["user", "created_at", "updated_at"]
