from __future__ import annotations

import asyncio
from dataclasses import dataclass, field, replace
from datetime import UTC, date, datetime
from typing import Any

from app.db.session import async_session_factory
from app.services.sync_service import SyncService

FEATURE_PIPELINE_PROVIDER = "sportsapipro-football-v1"
FEATURE_PIPELINE_SCOPES = (
    "market-backfill",
    "context-backfill",
    "rating-rebuild",
    "snapshot-backfill",
)


@dataclass(slots=True)
class FeaturePipelineJobStatus:
    running: bool = False
    state: str = "idle"
    provider_slug: str = FEATURE_PIPELINE_PROVIDER
    target_date: date | None = None
    timezone_name: str | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    current_scope: str | None = None
    last_message: str | None = None
    last_error: str | None = None
    sync_run_ids: dict[str, str] = field(default_factory=dict)
    stats: dict[str, int] = field(default_factory=dict)
    events: list[str] = field(default_factory=list)


class FeaturePipelineJobManager:
    def __init__(self, *, session_factory=async_session_factory) -> None:
        self._session_factory = session_factory
        self._status = FeaturePipelineJobStatus()
        self._task: asyncio.Task[None] | None = None
        self._lock = asyncio.Lock()

    async def snapshot(self) -> FeaturePipelineJobStatus:
        async with self._lock:
            snapshot = replace(self._status)
            snapshot.sync_run_ids = dict(self._status.sync_run_ids)
            snapshot.stats = dict(self._status.stats)
            snapshot.events = list(self._status.events)
            return snapshot

    async def start(
        self,
        *,
        target_date: date,
        timezone_name: str | None,
        provider_slug: str = FEATURE_PIPELINE_PROVIDER,
    ) -> FeaturePipelineJobStatus:
        async with self._lock:
            if self._task is not None and not self._task.done():
                self._append_event_locked("Feature pipeline already running.")
                snapshot = replace(self._status)
                snapshot.sync_run_ids = dict(self._status.sync_run_ids)
                snapshot.stats = dict(self._status.stats)
                snapshot.events = list(self._status.events)
                return snapshot

            self._status = FeaturePipelineJobStatus(
                running=True,
                state="running",
                provider_slug=provider_slug,
                target_date=target_date,
                timezone_name=timezone_name,
                started_at=datetime.now(UTC),
                current_scope=FEATURE_PIPELINE_SCOPES[0],
                last_message=f"Feature pipeline started for {target_date.isoformat()}.",
            )
            self._append_event_locked(
                f"Feature pipeline started provider={provider_slug} date={target_date.isoformat()}."
            )
            self._task = asyncio.create_task(
                self._run(
                    provider_slug=provider_slug,
                    target_date=target_date,
                    timezone_name=timezone_name,
                )
            )
            snapshot = replace(self._status)
            snapshot.sync_run_ids = dict(self._status.sync_run_ids)
            snapshot.stats = dict(self._status.stats)
            snapshot.events = list(self._status.events)
            return snapshot

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
                merged_stats: dict[str, int] = {}
                for scope in FEATURE_PIPELINE_SCOPES:
                    async with self._lock:
                        self._status.current_scope = scope
                    result = await service.trigger_provider_sync(
                        provider_slug=provider_slug,
                        scope=scope,
                        target_date=target_date,
                        timezone_name=timezone_name,
                        progress_callback=lambda payload, scope=scope: self._progress_callback(scope, payload),
                    )
                    async with self._lock:
                        if result.sync_run_id is not None:
                            self._status.sync_run_ids[scope] = str(result.sync_run_id)
                        if result.stats:
                            for key, value in result.stats.items():
                                self._status.stats[key] = int(value)
                                merged_stats[key] = int(value)
                        self._status.last_message = result.message
                        self._append_event_locked(f"{scope}: {result.message}")
                    if not result.accepted:
                        raise RuntimeError(result.message)

            async with self._lock:
                self._status.running = False
                self._status.state = "succeeded"
                self._status.completed_at = datetime.now(UTC)
                self._status.current_scope = None
                self._status.last_message = "Feature pipeline completed."
                self._status.stats = merged_stats
                self._append_event_locked("Feature pipeline completed.")
        except Exception as exc:
            async with self._lock:
                self._status.running = False
                self._status.state = "failed"
                self._status.completed_at = datetime.now(UTC)
                self._status.last_error = str(exc)
                self._status.last_message = f"Feature pipeline failed: {exc}"
                self._append_event_locked(f"Feature pipeline failed: {exc}")
        finally:
            async with self._lock:
                self._task = None

    async def _progress_callback(self, scope: str, payload: dict[str, Any]) -> None:
        message = str(payload.get("message") or "").strip()
        async with self._lock:
            self._status.current_scope = scope
            if message:
                self._status.last_message = message
                self._append_event_locked(f"{scope}: {message}")
            sync_run_id = payload.get("sync_run_id")
            if sync_run_id is not None:
                self._status.sync_run_ids[scope] = str(sync_run_id)
            stats = payload.get("stats")
            if isinstance(stats, dict):
                for key, value in stats.items():
                    if isinstance(value, int):
                        self._status.stats[str(key)] = value
            error = payload.get("error")
            if error:
                self._status.last_error = str(error)

    def _append_event_locked(self, message: str) -> None:
        cleaned = message.strip()
        if not cleaned:
            return
        self._status.events.append(cleaned)
        if len(self._status.events) > 24:
            self._status.events = self._status.events[-24:]


feature_pipeline_job_manager = FeaturePipelineJobManager()
