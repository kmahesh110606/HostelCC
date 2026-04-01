import logging
import random

from django.conf import settings
from django.http import JsonResponse
from django.utils.deprecation import MiddlewareMixin

logger = logging.getLogger("request_audit")


class RequestAuditMiddleware(MiddlewareMixin):
    def process_request(self, request):
        if not getattr(settings, "REQUEST_AUDIT_ENABLED", True):
            return None

        skip_prefixes = tuple(getattr(settings, "REQUEST_AUDIT_SKIP_PATH_PREFIXES", ("/static/", "/media/", "/health/")))
        if request.path.startswith(skip_prefixes):
            return None

        x_forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
        ip_addr = x_forwarded_for.split(",")[0].strip() if x_forwarded_for else request.META.get("REMOTE_ADDR", "unknown")
        client_mac = request.headers.get("X-Client-MAC", "unavailable")
        user_agent = request.headers.get("User-Agent", "unknown")

        suspicious = any(
            marker in (user_agent or "").lower()
            for marker in ["sqlmap", "nikto", "nmap", "acunetix"]
        )

        suspicious_only = bool(getattr(settings, "REQUEST_AUDIT_LOG_SUSPICIOUS_ONLY", False))
        sample_rate = float(getattr(settings, "REQUEST_AUDIT_SAMPLE_RATE", 0.1) or 0.0)
        sample_rate = max(0.0, min(1.0, sample_rate))
        sampled = random.random() < sample_rate

        if not suspicious and (suspicious_only or not sampled):
            return None

        log_method = logger.warning if suspicious else logger.info
        log_method(
            "request path=%s method=%s ip=%s mac=%s ua=%s suspicious=%s",
            request.path,
            request.method,
            ip_addr,
            client_mac,
            user_agent,
            suspicious,
        )
        return None


class ApiSafeErrorMiddleware(MiddlewareMixin):
    def process_exception(self, request, exception):
        if request.path.startswith("/api/"):
            logger.exception("Unhandled API exception at path=%s", request.path)
            return JsonResponse(
                {"detail": "Server error. Please try again shortly."},
                status=500,
            )
        return None
