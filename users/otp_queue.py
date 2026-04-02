import json
from dataclasses import dataclass
from typing import Any

from django.core.mail import send_mail
from django_redis import get_redis_connection

QUEUE_KEY = "hostelcc:otp_email_queue"


@dataclass(slots=True)
class OtpEmailJob:
    email: str
    otp_code: str
    from_email: str
    subject: str = "Hostel Management OTP"

    def message(self) -> str:
        return f"Your OTP is {self.otp_code}. It expires in 10 minutes."

    def to_json(self) -> str:
        return json.dumps(
            {
                "email": self.email,
                "otp_code": self.otp_code,
                "from_email": self.from_email,
                "subject": self.subject,
            },
            separators=(",", ":"),
        )

    @classmethod
    def from_json(cls, raw: str) -> "OtpEmailJob":
        payload: dict[str, Any] = json.loads(raw)
        return cls(
            email=payload["email"],
            otp_code=payload["otp_code"],
            from_email=payload["from_email"],
            subject=payload.get("subject", "Hostel Management OTP"),
        )


def enqueue_otp_email(job: OtpEmailJob) -> None:
    connection = get_redis_connection("default")
    connection.rpush(QUEUE_KEY, job.to_json())


def pop_otp_email_job(timeout: int = 5) -> OtpEmailJob | None:
    connection = get_redis_connection("default")
    payload = connection.blpop(QUEUE_KEY, timeout=timeout)
    if not payload:
        return None
    _, raw = payload
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8")
    return OtpEmailJob.from_json(raw)


def send_otp_email(job: OtpEmailJob) -> None:
    send_mail(
        subject=job.subject,
        message=job.message(),
        from_email=job.from_email,
        recipient_list=[job.email],
        fail_silently=False,
    )
