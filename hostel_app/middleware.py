import logging
from django.utils.deprecation import MiddlewareMixin

logger = logging.getLogger("request_audit")


class RequestAuditMiddleware(MiddlewareMixin):
    def process_request(self, request):
        x_forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
        ip_addr = x_forwarded_for.split(",")[0].strip() if x_forwarded_for else request.META.get("REMOTE_ADDR", "unknown")
        client_mac = request.headers.get("X-Client-MAC", "unavailable")
        user_agent = request.headers.get("User-Agent", "unknown")

        suspicious = any(
            marker in (user_agent or "").lower()
            for marker in ["sqlmap", "nikto", "nmap", "acunetix"]
        )

        logger.info(
            "request path=%s method=%s ip=%s mac=%s ua=%s suspicious=%s",
            request.path,
            request.method,
            ip_addr,
            client_mac,
            user_agent,
            suspicious,
        )
