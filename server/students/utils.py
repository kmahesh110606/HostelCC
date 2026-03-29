from django.db.models import Q

from .models import Student


def resolve_student_for_user(user):
    if not user or not getattr(user, "is_authenticated", False):
        return None

    base_qs = Student.objects.select_related("block", "room", "user")

    direct = base_qs.filter(user=user).first()
    if direct:
        return direct

    username = (user.username or "").strip()
    email = (user.email or "").strip().lower()
    email_local = email.split("@", 1)[0] if "@" in email else ""

    candidate_roll_nos = {value for value in (username, email_local) if value}
    if not candidate_roll_nos:
        return None

    lookup = Q()
    for roll_no in candidate_roll_nos:
        lookup |= Q(roll_no__iexact=roll_no)

    matches = list(base_qs.filter(lookup)[:2])
    if len(matches) != 1:
        return None

    student = matches[0]
    if student.user_id is None:
        student.user = user
        student.save(update_fields=["user"])

    return student