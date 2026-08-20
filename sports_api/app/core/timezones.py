from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DEFAULT_TIMEZONE = "UTC"


def resolve_timezone(timezone_name: str | None) -> ZoneInfo:
    candidate = (timezone_name or DEFAULT_TIMEZONE).strip() or DEFAULT_TIMEZONE
    try:
        return ZoneInfo(candidate)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(
            "Invalid timezone. Use an IANA timezone like Europe/Istanbul or America/New_York."
        ) from exc


def canonical_timezone_name(timezone_name: str | None) -> str:
    return resolve_timezone(timezone_name).key


def utc_day_bounds(target_date: date, timezone_name: str | None) -> tuple[datetime, datetime]:
    tz = resolve_timezone(timezone_name)
    start_local = datetime.combine(target_date, time.min, tzinfo=tz)
    end_local = datetime.combine(target_date + timedelta(days=1), time.min, tzinfo=tz)
    return start_local.astimezone(UTC), end_local.astimezone(UTC)


def convert_datetime(value: datetime, timezone_name: str | None) -> datetime:
    return value.astimezone(resolve_timezone(timezone_name))
