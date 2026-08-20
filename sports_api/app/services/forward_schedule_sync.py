from __future__ import annotations

import asyncio
import json
import os
import random
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, replace
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Literal

from app.core.config import get_settings
from app.db.session import async_session_factory
from app.providers.registry import REGISTERED_PROVIDER_CLIENTS
from app.services.sync_service import SyncService


@dataclass(slots=True)
class ForwardScheduleSyncStatus:
    running: bool = False
    state: str = "idle"
    provider_slug: str = "sportsapipro-football-v2"
    started_from: date | None = None
    direction: str = "forward"
    max_days: int | None = None
    current_date: date | None = None
    last_completed_date: date | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    heartbeat_at: datetime | None = None
    processed_days: int = 0
    total_matches_downloaded: int = 0
    successful_days: int = 0
    retry_count: int = 0
    last_matches_count: int | None = None
    last_message: str | None = None
    last_error: str | None = None
    pid: int | None = None


class ForwardScheduleSyncStatusStore:
    def __init__(self, root_dir: Path) -> None:
        self.root_dir = root_dir
        self.status_path = root_dir / "status.json"
        self.pid_path = root_dir / "runner.pid"
        self.stop_path = root_dir / "stop.request"
        self.stdout_log_path = root_dir / "runner.stdout.log"
        self.stderr_log_path = root_dir / "runner.stderr.log"

    @classmethod
    def default(cls) -> ForwardScheduleSyncStatusStore:
        root = _default_forward_schedule_runtime_dir()
        store = cls(root)
        store._migrate_from_legacy(
            Path(__file__).resolve().parents[2] / "runtime" / "forward_schedule_sync"
        )
        return store

    def ensure_dir(self) -> None:
        self.root_dir.mkdir(parents=True, exist_ok=True)

    def _migrate_from_legacy(self, legacy_root: Path) -> None:
        if self.status_path.exists():
            return
        legacy_status = legacy_root / "status.json"
        if not legacy_status.exists():
            return
        self.ensure_dir()
        shutil.copyfile(legacy_status, self.status_path)

    def load(self) -> ForwardScheduleSyncStatus | None:
        if not self.status_path.exists():
            return None
        payload = json.loads(self.status_path.read_text(encoding="utf-8"))
        return ForwardScheduleSyncStatus(
            running=bool(payload.get("running", False)),
            state=str(payload.get("state", "idle")),
            provider_slug=str(payload.get("provider_slug", "sportsapipro-football-v2")),
            started_from=_parse_date(payload.get("started_from")),
            direction=str(payload.get("direction", "forward")),
            max_days=_parse_int(payload.get("max_days")),
            current_date=_parse_date(payload.get("current_date")),
            last_completed_date=_parse_date(payload.get("last_completed_date")),
            started_at=_parse_datetime(payload.get("started_at")),
            completed_at=_parse_datetime(payload.get("completed_at")),
            heartbeat_at=_parse_datetime(payload.get("heartbeat_at")),
            processed_days=int(payload.get("processed_days", 0) or 0),
            total_matches_downloaded=int(payload.get("total_matches_downloaded", 0) or 0),
            successful_days=int(payload.get("successful_days", 0) or 0),
            retry_count=int(payload.get("retry_count", 0) or 0),
            last_matches_count=_parse_int(payload.get("last_matches_count")),
            last_message=_parse_optional_str(payload.get("last_message")),
            last_error=_parse_optional_str(payload.get("last_error")),
            pid=_parse_int(payload.get("pid")),
        )

    def save(self, status: ForwardScheduleSyncStatus) -> None:
        self.ensure_dir()
        payload = asdict(status)
        self.status_path.write_text(
            json.dumps(payload, ensure_ascii=True, default=_json_default, indent=2),
            encoding="utf-8",
        )

    def write_pid(self, pid: int) -> None:
        self.ensure_dir()
        self.pid_path.write_text(str(pid), encoding="utf-8")

    def read_pid(self) -> int | None:
        if not self.pid_path.exists():
            return None
        raw = self.pid_path.read_text(encoding="utf-8").strip()
        return _parse_int(raw)

    def remove_pid(self) -> None:
        if self.pid_path.exists():
            self.pid_path.unlink()

    def request_stop(self) -> None:
        self.ensure_dir()
        self.stop_path.write_text(datetime.now(UTC).isoformat(), encoding="utf-8")

    def clear_stop_request(self) -> None:
        if self.stop_path.exists():
            self.stop_path.unlink()

    def stop_requested(self) -> bool:
        return self.stop_path.exists()


class ForwardScheduleSyncManager:
    def __init__(
        self,
        *,
        session_factory=async_session_factory,
        sleep=asyncio.sleep,
        today_provider=date.today,
        settings=None,
        random_uniform=random.uniform,
        execution_mode: Literal["task", "process"] = "task",
        status_store: ForwardScheduleSyncStatusStore | None = None,
        python_executable: str | None = None,
        worker_module: str = "app.services.forward_schedule_sync_worker",
    ) -> None:
        self._session_factory = session_factory
        self._sleep = sleep
        self._today_provider = today_provider
        self._settings = settings or get_settings()
        self._random_uniform = random_uniform
        self._status = ForwardScheduleSyncStatus()
        self._task: asyncio.Task[None] | None = None
        self._lock = asyncio.Lock()
        self._stop_requested = False
        self._execution_mode = execution_mode
        self._status_store = status_store
        self._python_executable = python_executable or sys.executable
        self._worker_module = worker_module

    async def snapshot(self) -> ForwardScheduleSyncStatus:
        if self._execution_mode == "process":
            return self._read_process_status()
        if self._status_store is not None:
            persisted = self._status_store.load()
            if persisted is not None:
                return persisted
        async with self._lock:
            return replace(self._status)

    async def start(self) -> ForwardScheduleSyncStatus:
        return await self.start_with_options()

    async def start_with_options(
        self,
        *,
        provider_slug: str = "sportsapipro-football-v2",
        start_date: date | None = None,
        direction: str = "forward",
        max_days: int | None = 365,
    ) -> ForwardScheduleSyncStatus:
        if self._execution_mode == "process":
            return await self._start_process_mode(
                provider_slug=provider_slug,
                start_date=start_date,
                direction=direction,
                max_days=max_days,
            )

        async with self._lock:
            if self._task is not None and not self._task.done():
                return replace(self._status)

            normalized_direction = self._normalize_direction(direction)
            effective_start_date = start_date or self._today_provider()
            normalized_max_days = self._normalize_max_days(max_days)
            self._stop_requested = False
            if self._status_store is not None:
                self._status_store.clear_stop_request()
                self._status_store.remove_pid()
            self._status = ForwardScheduleSyncStatus(
                running=True,
                state="running",
                provider_slug=provider_slug,
                started_from=effective_start_date,
                direction=normalized_direction,
                max_days=normalized_max_days,
                current_date=effective_start_date,
                started_at=datetime.now(UTC),
                heartbeat_at=datetime.now(UTC),
                last_message=(
                    f"{normalized_direction.capitalize()} schedule sync started from "
                    f"{effective_start_date.isoformat()}."
                ),
            )
            self._persist_locked()
            self._task = asyncio.create_task(
                self._run_loop(
                    provider_slug,
                    effective_start_date,
                    normalized_direction,
                    normalized_max_days,
                )
            )
            return replace(self._status)

    async def stop(self) -> ForwardScheduleSyncStatus:
        if self._execution_mode == "process":
            store = self._require_status_store()
            store.request_stop()
            status = self._read_process_status()
            if status.running:
                status.last_message = "Stop requested. Current day will finish first."
                store.save(status)
            return status

        async with self._lock:
            self._stop_requested = True
            if self._status.running:
                self._status.last_message = "Stop requested. Current day will finish first."
            return replace(self._status)

    async def run_foreground(
        self,
        *,
        provider_slug: str,
        start_date: date,
        direction: str = "forward",
        max_days: int | None = 365,
        pid: int | None = None,
    ) -> ForwardScheduleSyncStatus:
        normalized_direction = self._normalize_direction(direction)
        normalized_max_days = self._normalize_max_days(max_days)
        async with self._lock:
            self._stop_requested = False
            if self._status_store is not None:
                self._status_store.clear_stop_request()
                self._status_store.write_pid(pid or os.getpid())
            self._status = ForwardScheduleSyncStatus(
                running=True,
                state="running",
                provider_slug=provider_slug,
                started_from=start_date,
                direction=normalized_direction,
                max_days=normalized_max_days,
                current_date=start_date,
                started_at=datetime.now(UTC),
                heartbeat_at=datetime.now(UTC),
                last_message=(
                    f"{normalized_direction.capitalize()} schedule sync started from "
                    f"{start_date.isoformat()}."
                ),
                pid=pid,
            )
            self._persist_locked()
        await self._run_loop(provider_slug, start_date, normalized_direction, normalized_max_days)
        return await self.snapshot()

    async def resume_if_needed(self) -> ForwardScheduleSyncStatus:
        if self._execution_mode != "task" or self._status_store is None:
            return await self.snapshot()

        async with self._lock:
            if self._task is not None and not self._task.done():
                return replace(self._status)

        persisted = self._status_store.load()
        if persisted is None or not persisted.running:
            return persisted or await self.snapshot()

        resume_date = persisted.current_date or persisted.started_from or self._today_provider()
        async with self._lock:
            self._status = persisted
            self._status.current_date = resume_date
            self._status.completed_at = None
            self._status.last_error = None
            self._status.last_message = (
                f"Resuming {persisted.direction} schedule sync from {resume_date.isoformat()}."
            )
            self._touch_locked()
            self._persist_locked()
            self._task = asyncio.create_task(
                self._run_loop(
                    persisted.provider_slug,
                    resume_date,
                    persisted.direction,
                    persisted.max_days,
                )
            )
            return replace(self._status)

    async def _start_process_mode(
        self,
        *,
        provider_slug: str,
        start_date: date | None,
        direction: str,
        max_days: int | None,
    ) -> ForwardScheduleSyncStatus:
        store = self._require_status_store()
        current = self._read_process_status()
        if current.running:
            return current

        normalized_direction = self._normalize_direction(direction)
        effective_start_date = start_date or self._today_provider()
        normalized_max_days = self._normalize_max_days(max_days)
        status = ForwardScheduleSyncStatus(
            running=True,
            state="running",
            provider_slug=provider_slug,
            started_from=effective_start_date,
            direction=normalized_direction,
            max_days=normalized_max_days,
            current_date=effective_start_date,
            started_at=datetime.now(UTC),
            heartbeat_at=datetime.now(UTC),
            last_message=(
                f"{normalized_direction.capitalize()} schedule sync started from "
                f"{effective_start_date.isoformat()}."
            ),
        )
        store.clear_stop_request()
        store.save(status)
        self._spawn_worker_process(
            provider_slug=provider_slug,
            start_date=effective_start_date,
            direction=normalized_direction,
            max_days=normalized_max_days,
        )
        return self._read_process_status()

    async def _run_loop(
        self,
        provider_slug: str,
        start_date: date,
        direction: str = "forward",
        max_days: int | None = None,
    ) -> None:
        client = self._build_provider_client(provider_slug)
        async with self._lock:
            self._status.provider_slug = provider_slug
            self._status.started_from = start_date
            self._status.current_date = start_date
            self._status.direction = self._normalize_direction(direction)
            self._status.max_days = self._normalize_max_days(max_days)
            self._touch_locked()
            self._persist_locked()
        cursor = start_date
        try:
            while True:
                if await self._consume_stop_request():
                    return

                if max_days is not None and (await self.snapshot()).processed_days >= max_days:
                    await self._finish(
                        state="succeeded",
                        last_message=(
                            f"Reached max_days={max_days}. "
                            f"{direction.capitalize()} schedule sync completed."
                        ),
                    )
                    return

                await self._set_progress(
                    current_date=cursor,
                    last_message=f"Syncing {cursor.isoformat()} ({direction})...",
                )
                result = await self._run_day_sync(provider_slug, cursor, client=client)

                if result.accepted:
                    matches_count = int((result.stats or {}).get("matches_count", 0))
                    await self._handle_success(
                        cursor=cursor,
                        matches_count=matches_count,
                        message=result.message,
                    )
                    if direction == "forward" and matches_count <= 0:
                        await self._finish(
                            state="succeeded",
                            last_message=(
                                f"No matches returned for {cursor.isoformat()}. "
                                "Schedule sync completed."
                            ),
                        )
                        return
                    await self._sleep_between_days(provider_slug)
                    cursor += self._direction_delta(direction)
                    continue

                if result.error_code == 404:
                    await self._handle_retry_after_404(cursor, result.message)
                    await self._sleep(1)
                    continue

                await self._finish(
                    state="failed",
                    last_message=result.message,
                    last_error=result.message,
                )
                return
        except asyncio.CancelledError:
            await self._finish(state="stopped", last_message="Forward sync was cancelled.")
            raise
        except Exception as exc:
            await self._finish(
                state="failed",
                last_message=f"Forward sync crashed: {exc}",
                last_error=str(exc),
            )
        finally:
            await client.aclose()
            async with self._lock:
                self._task = None
                self._touch_locked()
                self._persist_locked()

    async def _run_day_sync(self, provider_slug: str, target_date: date, *, client):
        async with self._session_factory() as session:
            service = SyncService(session)
            return await service.trigger_provider_sync(
                provider_slug=provider_slug,
                scope="matches",
                target_date=target_date,
                client_override=client,
            )

    async def _consume_stop_request(self) -> bool:
        stop_requested = self._stop_requested
        if not stop_requested and self._status_store is not None:
            stop_requested = self._status_store.stop_requested()
        async with self._lock:
            if not stop_requested:
                return False
            self._stop_requested = False
            if self._status_store is not None:
                self._status_store.clear_stop_request()
            self._status.running = False
            self._status.state = "stopped"
            self._status.completed_at = datetime.now(UTC)
            self._status.last_message = "Forward sync stopped."
            self._touch_locked()
            self._persist_locked()
            return True

    async def _set_progress(
        self,
        *,
        current_date: date,
        last_message: str,
    ) -> None:
        async with self._lock:
            self._status.current_date = current_date
            self._status.last_message = last_message
            self._touch_locked()
            self._persist_locked()

    async def _handle_success(
        self,
        *,
        cursor: date,
        matches_count: int,
        message: str,
    ) -> None:
        async with self._lock:
            self._status.current_date = cursor
            self._status.last_completed_date = cursor
            self._status.last_matches_count = matches_count
            self._status.processed_days += 1
            self._status.last_message = message
            if matches_count > 0:
                self._status.successful_days += 1
                self._status.total_matches_downloaded += matches_count
            self._touch_locked()
            self._persist_locked()

    async def _handle_retry_after_404(self, failed_date: date, message: str) -> None:
        async with self._lock:
            self._status.retry_count += 1
            self._status.current_date = failed_date
            self._status.last_matches_count = None
            self._status.last_error = message
            self._status.last_message = (
                f"404 on {failed_date.isoformat()}. Retrying the same day until it succeeds."
            )
            self._touch_locked()
            self._persist_locked()

    async def _sleep_between_days(self, provider_slug: str) -> None:
        if provider_slug != "sofascore-football":
            return

        delay = max(self._settings.sofascore_request_delay_seconds, 0.0)
        jitter = max(self._settings.sofascore_request_jitter_seconds, 0.0)
        if jitter > 0:
            delay += self._random_uniform(0.0, jitter)
        if delay > 0:
            await self._sleep(delay)

    def _build_provider_client(self, provider_slug: str):
        client_cls = REGISTERED_PROVIDER_CLIENTS.get(provider_slug)
        if client_cls is None:
            raise ValueError(f"Unsupported provider: {provider_slug}")
        return client_cls(settings=self._settings)

    @staticmethod
    def _normalize_direction(direction: str) -> str:
        normalized = (direction or "forward").strip().lower()
        if normalized not in {"forward", "backward"}:
            return "forward"
        return normalized

    @staticmethod
    def _normalize_max_days(max_days: int | None) -> int | None:
        if max_days is None:
            return None
        return max(1, int(max_days))

    @staticmethod
    def _direction_delta(direction: str) -> timedelta:
        if direction == "backward":
            return timedelta(days=-1)
        return timedelta(days=1)

    async def _finish(
        self,
        *,
        state: str,
        last_message: str,
        last_error: str | None = None,
    ) -> None:
        async with self._lock:
            self._status.running = False
            self._status.state = state
            self._status.completed_at = datetime.now(UTC)
            self._status.last_message = last_message
            self._status.last_error = last_error
            if self._status_store is not None:
                self._status_store.remove_pid()
            self._touch_locked()
            self._persist_locked()

    def _read_process_status(self) -> ForwardScheduleSyncStatus:
        store = self._require_status_store()
        status = store.load() or ForwardScheduleSyncStatus()
        pid = store.read_pid()
        if pid is not None:
            status.pid = pid
        if status.running and pid is not None and not _pid_is_running(pid):
            status.running = False
            status.state = "failed"
            status.completed_at = datetime.now(UTC)
            status.last_error = status.last_error or "Schedule runner process exited unexpectedly."
            status.last_message = status.last_error
            store.save(status)
            store.remove_pid()
        return status

    def _spawn_worker_process(
        self,
        *,
        provider_slug: str,
        start_date: date,
        direction: str,
        max_days: int | None,
    ) -> None:
        store = self._require_status_store()
        store.ensure_dir()
        args = [
            self._python_executable,
            "-m",
            self._worker_module,
            "--provider-slug",
            provider_slug,
            "--start-date",
            start_date.isoformat(),
            "--direction",
            direction,
        ]
        if max_days is not None:
            args.extend(["--max-days", str(max_days)])
        creationflags = 0
        if os.name == "nt":
            creationflags = (
                subprocess.CREATE_NEW_PROCESS_GROUP
                | subprocess.DETACHED_PROCESS
                | subprocess.CREATE_NO_WINDOW
            )
        stdout_handle = store.stdout_log_path.open("ab")
        stderr_handle = store.stderr_log_path.open("ab")
        try:
            process = subprocess.Popen(
                args,
                cwd=str(Path(__file__).resolve().parents[2]),
                stdout=stdout_handle,
                stderr=stderr_handle,
                close_fds=True,
                creationflags=creationflags,
                start_new_session=(os.name != "nt"),
            )
        finally:
            stdout_handle.close()
            stderr_handle.close()
        store.write_pid(process.pid)

    def _require_status_store(self) -> ForwardScheduleSyncStatusStore:
        if self._status_store is None:
            raise RuntimeError("Forward schedule sync status store is not configured.")
        return self._status_store

    def _touch_locked(self) -> None:
        self._status.heartbeat_at = datetime.now(UTC)

    def _persist_locked(self) -> None:
        if self._status_store is not None:
            self._status_store.save(self._status)


def _parse_date(value: object) -> date | None:
    if value in (None, ""):
        return None
    return date.fromisoformat(str(value))


def _parse_datetime(value: object) -> datetime | None:
    if value in (None, ""):
        return None
    return datetime.fromisoformat(str(value))


def _parse_int(value: object) -> int | None:
    if value in (None, ""):
        return None
    return int(value)


def _parse_optional_str(value: object) -> str | None:
    if value is None:
        return None
    text = str(value)
    return text if text else None


def _json_default(value: object) -> str:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    raise TypeError(f"Object of type {type(value)!r} is not JSON serializable")


def _pid_is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _default_forward_schedule_runtime_dir() -> Path:
    local_app_data = os.getenv("LOCALAPPDATA")
    if local_app_data:
        return Path(local_app_data) / "SportsApi" / "runtime" / "forward_schedule_sync"
    return Path.home() / ".sports_api_runtime" / "forward_schedule_sync"


forward_schedule_sync_manager = ForwardScheduleSyncManager(
    execution_mode="task",
    status_store=ForwardScheduleSyncStatusStore.default(),
)
