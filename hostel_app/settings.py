import os
import hashlib
from datetime import timedelta
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent


def _csv_env(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.getenv(name, default).split(",") if item.strip()]

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "unsafe-dev-key")
DEBUG = os.getenv("DJANGO_DEBUG", "False").lower() == "true"
ALLOWED_HOSTS = _csv_env("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost,.azurewebsites.net")
if not ALLOWED_HOSTS or ALLOWED_HOSTS == [""]:
    import warnings
    warnings.warn("DJANGO_ALLOWED_HOSTS is not set. Allowing all hosts (not recommended for production).")
    ALLOWED_HOSTS = ["*"]

raw_jwt_signing_key = (os.getenv("JWT_SIGNING_KEY", "") or SECRET_KEY).strip()
if len(raw_jwt_signing_key.encode("utf-8")) < 32:
    JWT_SIGNING_KEY = hashlib.sha256(raw_jwt_signing_key.encode("utf-8")).hexdigest()
else:
    JWT_SIGNING_KEY = raw_jwt_signing_key

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt",
    "users",
    "hostels",
    "students",
    "laundry",
    "mess",
    "complaints",
    "discipline",
    "checkout",
    "cloakroom",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "hostel_app.middleware.ApiSafeErrorMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "hostel_app.middleware.RequestAuditMiddleware",
]

ROOT_URLCONF = "hostel_app.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "hostel_app.wsgi.application"
ASGI_APPLICATION = "hostel_app.asgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.getenv("DB_NAME", "hostel_db"),
        "USER": os.getenv("DB_USER", "hostel_user"),
        "PASSWORD": os.getenv("DB_PASSWORD", "hostel_password"),
        "HOST": os.getenv("DB_HOST", "pgbouncer"),
        "PORT": int(os.getenv("DB_PORT", "5432")),
        "CONN_MAX_AGE": int(os.getenv("DB_CONN_MAX_AGE", "60")),
        "OPTIONS": {
            "sslmode": os.getenv("DB_SSLMODE", "prefer"),
        },
    }
}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = os.getenv("DJANGO_TIME_ZONE", "Asia/Kolkata")
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

# Azure Storage configuration using environment variables
DEFAULT_FILE_STORAGE = "storages.backends.azure_storage.AzureStorage"
AZURE_ACCOUNT_NAME = os.environ.get("AZURE_ACCOUNT_NAME", "hostelccstorage")
AZURE_ACCOUNT_KEY = os.environ.get("AZURE_ACCOUNT_KEY", "")
AZURE_CONTAINER = os.environ.get("AZURE_CONTAINER", "media")

STORAGES = {
    "default": {
        "BACKEND": "storages.backends.azure_storage.AzureStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedStaticFilesStorage",
    },
}
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

MAX_COMPLAINT_MEDIA_BYTES = int(os.getenv("MAX_COMPLAINT_MEDIA_MB", "20")) * 1024 * 1024
MAX_NOTIFICATION_POSTER_BYTES = int(os.getenv("MAX_NOTIFICATION_POSTER_MB", "20")) * 1024 * 1024

AUTH_USER_MODEL = "users.User"
LOGIN_REDIRECT_URL = "/"
LOGOUT_REDIRECT_URL = "/accounts/login/"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "EXCEPTION_HANDLER": "hostel_app.api_exceptions.api_exception_handler",
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.AnonRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "user": "200/min",
        "anon": "50/min",
        "auth_login": "10/min",
        "auth_otp_request": "5/min",
        "auth_otp_verify": "15/min",
        "auth_first_password": "5/min",
        "auth_signup_request": "5/min",
        "auth_signup_complete": "5/min",
        "feedback": "10/min",
        "complaints": "15/min",
    },
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.getenv("JWT_ACCESS_MINUTES", "30"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=int(os.getenv("JWT_REFRESH_DAYS", "1"))),
    "SIGNING_KEY": JWT_SIGNING_KEY,
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": True,
}

CORS_ALLOWED_ORIGINS = _csv_env("CORS_ALLOWED_ORIGINS", "http://localhost:3000")
CSRF_TRUSTED_ORIGINS = _csv_env("DJANGO_CSRF_TRUSTED_ORIGINS", "")

EMAIL_BACKEND = os.getenv("EMAIL_BACKEND", "django.core.mail.backends.smtp.EmailBackend")
EMAIL_HOST = os.getenv("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587"))
EMAIL_USE_TLS = os.getenv("EMAIL_USE_TLS", "True").lower() == "true"
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD", "")
DEFAULT_FROM_EMAIL = "1442space@gmail.com"
DEFAULT_OTP_CODE = os.getenv("DEFAULT_OTP_CODE", "").strip()

if DEFAULT_OTP_CODE and not DEBUG:
    raise ImproperlyConfigured("DEFAULT_OTP_CODE can only be set when DJANGO_DEBUG=true.")

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
SECURE_SSL_REDIRECT = not DEBUG
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
SECURE_HSTS_SECONDS = 0 if DEBUG else int(os.getenv("SECURE_HSTS_SECONDS", "3600"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
SECURE_HSTS_PRELOAD = not DEBUG

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "hostelcc-local-cache",
        "TIMEOUT": 300,
    }
}

REQUEST_AUDIT_ENABLED = os.getenv("REQUEST_AUDIT_ENABLED", "True").lower() == "true"
REQUEST_AUDIT_SAMPLE_RATE = float(os.getenv("REQUEST_AUDIT_SAMPLE_RATE", "0.1"))
REQUEST_AUDIT_LOG_SUSPICIOUS_ONLY = os.getenv("REQUEST_AUDIT_LOG_SUSPICIOUS_ONLY", "False").lower() == "true"
REQUEST_AUDIT_SKIP_PATH_PREFIXES = tuple(
    _csv_env("REQUEST_AUDIT_SKIP_PATH_PREFIXES", "/static/,/media/,/favicon.ico,/health/,/api/health/")
)
REQUEST_AUDIT_LOG_LEVEL = os.getenv("REQUEST_AUDIT_LOG_LEVEL", "WARNING").upper()

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "%(asctime)s %(levelname)s %(name)s %(message)s",
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "verbose",
        }
    },
    "loggers": {
        "request_audit": {
            "handlers": ["console"],
            "level": REQUEST_AUDIT_LOG_LEVEL,
            "propagate": False,
        }
    },
}
