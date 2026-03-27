from rest_framework import serializers

from .models import Complaint, ComplaintReply, ComplaintVote


class ComplaintReplySerializer(serializers.ModelSerializer):
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = ComplaintReply
        fields = ["id", "complaint", "author", "author_name", "text", "created_at"]
        read_only_fields = ["author", "created_at"]

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
            "upvotes",
            "downvotes",
            "created_at",
            "can_delete",
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
            request = self.context.get("request")
            url = obj.media.url
            return request.build_absolute_uri(url) if request else url
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


class ComplaintVoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = ComplaintVote
        fields = ["id", "complaint", "user", "value", "created_at", "updated_at"]
        read_only_fields = ["user", "created_at", "updated_at"]
