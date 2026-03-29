from django.core.cache import cache
from django.db import connection
from django.http import JsonResponse


def healthz(request):
    db_ok = True
    cache_ok = True

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except Exception:
        db_ok = False

    try:
        cache.set("healthz", "ok", timeout=5)
        cache_ok = cache.get("healthz") == "ok"
    except Exception:
        cache_ok = False

    status_code = 200 if db_ok else 503
    status_text = "ok" if status_code == 200 else "degraded"
    return JsonResponse(
        {
            "status": status_text,
            "db": db_ok,
            "cache": cache_ok,
        },
        status=status_code,
    )