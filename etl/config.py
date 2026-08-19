from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


def normalize_postgres_url(value: str) -> str:
    """Remove Prisma-only query parameters while preserving PostgreSQL options."""
    value = value.strip()
    parts = urlsplit(value)
    if parts.scheme not in {"postgres", "postgresql"}:
        raise ValueError("database URLs must use postgres:// or postgresql://")
    query = urlencode([(key, val) for key, val in parse_qsl(parts.query) if key != "schema"])
    return urlunsplit(("postgresql", parts.netloc, parts.path, query, parts.fragment))


def database_identity(value: str) -> tuple[str | None, int | None, str]:
    parts = urlsplit(normalize_postgres_url(value))
    return parts.hostname, parts.port or 5432, parts.path.lstrip("/")


def _positive_int(name: str, default: int, minimum: int = 1) -> int:
    raw = os.getenv(name, str(default))
    try:
        value = int(raw)
    except ValueError as error:
        raise ValueError(f"{name} must be an integer") from error
    if value < minimum:
        raise ValueError(f"{name} must be at least {minimum}")
    return value


@dataclass(frozen=True)
class Settings:
    oltp_database_url: str
    warehouse_database_url: str
    source_system: str = "rm_oltp"
    chunk_size: int = 5000
    overlap_minutes: int = 5
    staging_retention_days: int = 30
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "Settings":
        oltp_url = os.getenv("OLTP_DATABASE_URL", "")
        warehouse_url = os.getenv("WAREHOUSE_DATABASE_URL", "")
        if not oltp_url or not warehouse_url:
            raise ValueError("OLTP_DATABASE_URL and WAREHOUSE_DATABASE_URL are required")

        settings = cls(
            oltp_database_url=normalize_postgres_url(oltp_url),
            warehouse_database_url=normalize_postgres_url(warehouse_url),
            source_system=os.getenv("ETL_SOURCE_SYSTEM", "rm_oltp").strip() or "rm_oltp",
            chunk_size=_positive_int("ETL_CHUNK_SIZE", 5000),
            overlap_minutes=_positive_int("ETL_OVERLAP_MINUTES", 5, minimum=0),
            staging_retention_days=_positive_int("ETL_STAGING_RETENTION_DAYS", 30),
            log_level=os.getenv("ETL_LOG_LEVEL", "INFO").upper(),
        )
        if database_identity(settings.oltp_database_url) == database_identity(settings.warehouse_database_url):
            raise ValueError("OLTP and warehouse must be different PostgreSQL databases")
        return settings
