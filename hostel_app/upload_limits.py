from __future__ import annotations


def upload_size_error(uploaded_file, max_bytes: int, label: str) -> str | None:
    if not uploaded_file:
        return None

    size = getattr(uploaded_file, "size", None)
    if size is None or size <= max_bytes:
        return None

    max_mb = max_bytes // (1024 * 1024)
    return f"{label} must be {max_mb} MB or smaller."