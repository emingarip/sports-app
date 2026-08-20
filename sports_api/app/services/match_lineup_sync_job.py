from __future__ import annotations

import asyncio
from dataclasses import dataclass, field, replace
from datetime import UTC, date, datetime
from typing import Any

from app.db.session import async_session_factory
from app.services.sync_service import SyncService


@dataclass(slots=True)
class MatchLineupSyncJobStatus:
    running: bool = False
    state: str = "idle"
    provider_slug: str = "sportsapipro-football-v2"
    target_date: date | None = None
    timezone_name: str | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    sync_run_id: str | None = None
    last_message: str | None = None
    last_error: str | None = None
    status_code: int | None = None
    attempt: int | None = None
    attempts: int | None = None
    wait_seconds: float | None = None
    stats: dict[str, int] = field(default_factory=dict)
    events: list[str] = field(default_factory=list)


class MatchLineupSyncJobManager:
    def __init__(self, *, session_factory=async_session_factory) -> None:
        self._session_factory = session_factory
        self._status = MatchLineupSyncJobStatus()
        self._task: asyncio.Task[None] | None = None
        self._lock = asyncio.Lock()

    async def snapshot(self) -> MatchLineupSyncJobStatus:
        async with self._lock:
            return self._copy_status_locked()

    async def start(
        self,
        *,
        provider_slug: str,
        target_date: date,
        timezone_name: str | None,
    ) -> MatchLineupSyncJobStatus:
        async with self._lock:
            if self._task is not None and not self._task.done():
                self._append_event_locked(
                    "Match player sync already running for "
                    f"{self._status.provider_slug} {self._status.target_date}."
                )
                return self._copy_status_locked()

            self._status = MatchLineupSyncJobStatus(
                running=True,
                state="running",
                provider_slug=provider_slug,
                target_date=target_date,
                timezone_name=timezone_name,
                started_at=datetime.now(UTC),
                last_message=f"Match player sync started for {target_date.isoformat()}.",
            )
            self._append_event_locked(
                "Match player sync started "
                f"provider={provider_slug} date={target_date.isoformat()} tz={timezone_name or '-'}."
            )
            self._task = asyncio.create_task(
                self._run(
                    provider_slug=provider_slug,
                    target_date=target_date,
                    timezone_name=timezone_name,
                )
            )
            return self._copy_status_locked()

    async def _run(
        self,
        *,
        provider_slug: str,
        target_date: date,
        timezone_name: str | None,
    ) -> None:
        try:
            async with self._session_factory() as session:
                service = SyncService(session)
                result = await service.trigger_provider_sync(
                    provider_slug=provider_slug,
                    scope="match-lineups",
                    target_date=target_date,
                    timezone_name=timezone_name,
                    progress_callback=self._progress_callback,
                )

            async with self._lock:
                self._status.running = False
                self._status.state = "succeeded" if result.accepted else "failed"
                self._status.completed_at = datetime.now(UTC)
                self._status.sync_run_id = (
                    str(result.sync_run_id) if result.sync_run_id is not None else None
                )
                self._status.stats = dict(result.stats or {})
                self._status.last_message = result.message
                self._status.status_code = result.error_code
                if not result.accepted:
                    self._status.last_error = result.message
                self._append_event_locked(result.message)
        except Exception as exc:
            async with self._lock:
                self._status.running = False
                self._status.state = "failed"
                self._status.completed_at = datetime.now(UTC)
                self._status.last_error = str(exc)
                self._status.last_message = f"Match player sync crashed: {exc}"
                self._append_event_locked(f"Match player sync crashed: {exc}")
        finally:
            async with self._lock:
                self._task = None

    async def _progress_callback(self, payload: dict[str, Any]) -> None:
        message = str(payload.get("message") or "").strip()
        async with self._lock:
            if message:
                self._status.last_message = message
                self._append_event_locked(message)
            if payload.get("error"):
                self._status.last_error = str(payload["error"])
            if isinstance(payload.get("status_code"), int):
                self._status.status_code = int(payload["status_code"])
            if isinstance(payload.get("attempt"), int):
                self._status.attempt = int(payload["attempt"])
            if isinstance(payload.get("attempts"), int):
                self._status.attempts = int(payload["attempts"])
            wait_seconds = payload.get("wait_seconds")
            if isinstance(wait_seconds, (int, float)):
                self._status.wait_seconds = float(wait_seconds)
            sync_run_id = payload.get("sync_run_id")
            if sync_run_id is not None:
                self._status.sync_run_id = str(sync_run_id)
            stats = payload.get("stats")
            if isinstance(stats, dict):
                self._status.stats = {
                    str(key): int(value)
                    for key, value in stats.items()
                    if isinstance(value, int)
                }

    def _append_event_locked(self, message: str) -> None:
        cleaned = message.strip()
        if not cleaned:
            return
        self._status.events.append(cleaned)
        if len(self._status.events) > 16:
            self._status.events = self._status.events[-16:]

    def _copy_status_locked(self) -> MatchLineupSyncJobStatus:
        snapshot = replace(self._status)
        snapshot.stats = dict(self._status.stats)
        snapshot.events = list(self._status.events)
        return snapshot


match_lineup_sync_job_manager = MatchLineupSyncJobManager()
