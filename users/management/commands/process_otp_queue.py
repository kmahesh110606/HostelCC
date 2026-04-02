import time

from django.core.management.base import BaseCommand

from users.otp_queue import pop_otp_email_job, send_otp_email


class Command(BaseCommand):
    help = "Process queued OTP email jobs from Redis."

    def add_arguments(self, parser):
        parser.add_argument("--once", action="store_true", help="Process a single job and exit.")
        parser.add_argument("--sleep", type=float, default=1.0, help="Sleep interval when the queue is empty.")

    def handle(self, *args, **options):
        once = options["once"]
        sleep_interval = float(options["sleep"])

        self.stdout.write(self.style.SUCCESS("OTP queue worker started."))
        while True:
            job = pop_otp_email_job(timeout=5)
            if job is None:
                if once:
                    return
                time.sleep(sleep_interval)
                continue

            try:
                send_otp_email(job)
                self.stdout.write(self.style.SUCCESS(f"Sent OTP email to {job.email}"))
            except Exception as exc:  # pragma: no cover - worker logging path
                self.stderr.write(self.style.ERROR(f"Failed to send OTP email to {job.email}: {exc}"))

            if once:
                return
