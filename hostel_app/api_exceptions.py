import re

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler


_URL_RE = re.compile(r"https?://[^\s]+", flags=re.IGNORECASE)
_FILE_RE = re.compile(r"([A-Za-z]:\\[^\s]+|/[^\s]+\.(?:py|txt|log|json|yaml|yml))")


def _sanitize_text(value: str) -> str:
    cleaned = _URL_RE.sub("", value or "")
    cleaned = _FILE_RE.sub("", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


def _safe_error_payload(message: str, code: int) -> dict:
    if code >= 500:
        return {"detail": "Server error. Please try again shortly."}
    if message:
        return {"detail": _sanitize_text(message)}
    return {"detail": "Request failed. Please verify your input and try again."}


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)

    if response is None:
        return Response(
            {"detail": "Server error. Please try again shortly."},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    status_code = response.status_code
    payload = response.data

    message = ""
    if isinstance(payload, dict):
        detail = payload.get("detail")
        if detail is not None:
            message = str(detail)
        else:
            for value in payload.values():
                if isinstance(value, list) and value:
                    message = str(value[0])
                    break
                if isinstance(value, str) and value.strip():
                    message = value
                    break
    elif isinstance(payload, list) and payload:
        message = str(payload[0])
    elif payload is not None:
        message = str(payload)

    response.data = _safe_error_payload(message, status_code)
    return response
