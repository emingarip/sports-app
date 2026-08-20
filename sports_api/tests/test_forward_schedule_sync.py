import asyncio
import shutil
from datetime import UTC, date, datetime
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from app.core.config import Settings
from app.services.forward_schedule_sync import (
    ForwardScheduleSyncManager,
    ForwardScheduleSyncStatus,
    ForwardScheduleSyncStatusStore,
)


class DummySessionContext:
    async def __aenter__(self):
        return object()

    async def __aexit__(self, exc_type, exc, tb):
        return False


def _workspace_test_store(name: str) -> ForwardScheduleSyncStatusStore:
    root = Path("tests") / ".runtime" / f"{name}-{uuid4().hex}"
    if root.exists():
        shutil.rmtree(root)
    return ForwardScheduleSyncStatusStore(root)


async def test_forward_schedule_sync_retries_same_day_on_404(monkeypatch) -> None:
    responses = [
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 5},
            message="Day 1 synced.",
            error_code=None,
        ),
        SimpleNamespace(
            accepted=False,
            stats=None,
            message="Match sync failed: 404",
            error_code=404,
        ),
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 3},
            message="Retried day synced.",
            error_code=None,
        ),
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 0},
            message="Empty day.",
            error_code=None,
        ),
    ]
    calls: list[date] = []
    sleeps: list[float] = []

    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        category_id=None,
        tournament_id=None,
        client_override=None,
    ):
        assert provider_slug == "sportsapipro-football-v2"
        assert scope == "matches"
        calls.append(target_date)
        return responses.pop(0)

    async def fake_sleep(delay: float) -> None:
        sleeps.append(delay)

    monkeypatch.setattr(
        "app.services.sync_service.SyncService.trigger_provider_sync",
        fake_trigger_provider_sync,
    )

    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=fake_sleep,
        today_provider=lambda: date(2026, 4, 6),
    )

    await manager._run_loop("sportsapipro-football-v2", date(2026, 4, 6), "forward", 365)
    status = await manager.snapshot()

    assert calls == [
        date(2026, 4, 6),
        date(2026, 4, 7),
        date(2026, 4, 7),
        date(2026, 4, 8),
    ]
    assert sleeps == [1]
    assert status.running is False
    assert status.state == "succeeded"
    assert status.total_matches_downloaded == 8
    assert status.successful_days == 2
    assert status.retry_count == 1
    assert status.last_completed_date == date(2026, 4, 8)
    assert status.last_matches_count == 0
    assert "Schedule sync completed" in (status.last_message or "")


async def test_forward_schedule_sync_marks_failure_for_non_404(monkeypatch) -> None:
    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        category_id=None,
        tournament_id=None,
        client_override=None,
    ):
        return SimpleNamespace(
            accepted=False,
            stats=None,
            message="Match sync failed: upstream 500",
            error_code=500,
        )

    monkeypatch.setattr(
        "app.services.sync_service.SyncService.trigger_provider_sync",
        fake_trigger_provider_sync,
    )

    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
    )

    await manager._run_loop("sportsapipro-football-v2", date(2026, 4, 6), "forward", 365)
    status = await manager.snapshot()

    assert status.running is False
    assert status.state == "failed"
    assert status.current_date == date(2026, 4, 6)
    assert status.total_matches_downloaded == 0
    assert status.last_error == "Match sync failed: upstream 500"


async def test_forward_schedule_sync_backward_stops_at_max_days(monkeypatch) -> None:
    responses = [
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 4},
            message="Back day 1 synced.",
            error_code=None,
        ),
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 0},
            message="Back day 2 empty.",
            error_code=None,
        ),
    ]
    calls: list[date] = []

    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        category_id=None,
        tournament_id=None,
        client_override=None,
    ):
        calls.append(target_date)
        return responses.pop(0)

    monkeypatch.setattr(
        "app.services.sync_service.SyncService.trigger_provider_sync",
        fake_trigger_provider_sync,
    )

    async def fake_sleep(delay: float) -> None:
        return None

    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=fake_sleep,
        today_provider=lambda: date(2026, 4, 6),
        settings=Settings(
            sofascore_request_delay_seconds=0.0,
            sofascore_request_jitter_seconds=0.0,
        ),
    )

    await manager._run_loop("sofascore-football", date(2026, 4, 6), "backward", 2)
    status = await manager.snapshot()

    assert calls == [date(2026, 4, 6), date(2026, 4, 5)]
    assert status.state == "succeeded"
    assert status.provider_slug == "sofascore-football"
    assert status.direction == "backward"
    assert status.processed_days == 2
    assert status.total_matches_downloaded == 4
    assert "Reached max_days=2" in (status.last_message or "")


async def test_forward_schedule_sync_start_initializes_running_state(monkeypatch) -> None:
    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
    )

    async def fake_run_loop(
        provider_slug: str,
        start_date: date,
        direction: str,
        max_days: int | None,
    ) -> None:
        assert provider_slug == "sofascore-football"
        assert start_date == date(2026, 4, 6)
        assert direction == "backward"
        assert max_days == 30
        await manager._finish(
            state="succeeded",
            last_message="done",
        )

    monkeypatch.setattr(manager, "_run_loop", fake_run_loop)

    status = await manager.start_with_options(
        provider_slug="sofascore-football",
        start_date=date(2026, 4, 6),
        direction="backward",
        max_days=30,
    )

    assert status.running is True
    assert status.state == "running"
    assert status.provider_slug == "sofascore-football"
    assert status.started_from == date(2026, 4, 6)
    assert status.direction == "backward"
    assert status.max_days == 30
    await manager._task
    completed = await manager.snapshot()
    assert completed.state == "succeeded"
    assert completed.completed_at is not None


async def test_forward_schedule_sync_reuses_provider_and_applies_sofascore_delay(
    monkeypatch,
) -> None:
    responses = [
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 2},
            message="Day 1 synced.",
            error_code=None,
        ),
        SimpleNamespace(
            accepted=True,
            stats={"matches_count": 0},
            message="Day 2 empty.",
            error_code=None,
        ),
    ]
    seen_clients: list[object] = []
    sleeps: list[float] = []

    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        category_id=None,
        tournament_id=None,
        client_override=None,
    ):
        assert provider_slug == "sofascore-football"
        seen_clients.append(client_override)
        return responses.pop(0)

    monkeypatch.setattr(
        "app.services.sync_service.SyncService.trigger_provider_sync",
        fake_trigger_provider_sync,
    )

    class FakeClient:
        def __init__(self) -> None:
            self.closed = False

        async def aclose(self) -> None:
            self.closed = True

    fake_client = FakeClient()

    async def fake_sleep(delay: float) -> None:
        sleeps.append(delay)

    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=fake_sleep,
        today_provider=lambda: date(2026, 4, 6),
        settings=Settings(
            sofascore_request_delay_seconds=2.0,
            sofascore_request_jitter_seconds=1.0,
        ),
        random_uniform=lambda start, end: 0.5,
    )
    monkeypatch.setattr(manager, "_build_provider_client", lambda provider_slug: fake_client)

    await manager._run_loop("sofascore-football", date(2026, 4, 6), "forward", 365)

    assert seen_clients == [fake_client, fake_client]
    assert sleeps == [2.5]
    assert fake_client.closed is True


async def test_forward_schedule_sync_resume_if_needed_restores_running_task(
    monkeypatch,
) -> None:
    store = _workspace_test_store("resume")
    store.save(
        ForwardScheduleSyncStatus(
            running=True,
            state="running",
            provider_slug="sportsapipro-football-v2",
            started_from=date(2026, 1, 31),
            current_date=date(2026, 1, 25),
            direction="backward",
            max_days=664,
            started_at=datetime(2026, 4, 7, tzinfo=UTC),
            processed_days=12,
            total_matches_downloaded=3456,
            successful_days=12,
        )
    )
    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
        status_store=store,
    )
    seen: list[tuple[str, date, str, int | None]] = []

    async def fake_run_loop(
        provider_slug: str,
        start_date: date,
        direction: str,
        max_days: int | None,
    ) -> None:
        seen.append((provider_slug, start_date, direction, max_days))
        await manager._finish(state="succeeded", last_message="resumed")

    monkeypatch.setattr(manager, "_run_loop", fake_run_loop)

    status = await manager.resume_if_needed()

    assert status.running is True
    assert status.current_date == date(2026, 1, 25)
    await manager._task
    assert seen == [("sportsapipro-football-v2", date(2026, 1, 25), "backward", 664)]
    completed = store.load()
    assert completed is not None
    assert completed.state == "succeeded"


async def test_forward_schedule_sync_snapshot_prefers_persisted_status() -> None:
    store = _workspace_test_store("snapshot")
    store.save(
        ForwardScheduleSyncStatus(
            running=True,
            state="running",
            provider_slug="sportsapipro-football-v2",
            started_from=date(2026, 1, 31),
            current_date=date(2026, 1, 31),
            direction="backward",
            max_days=10,
        )
    )
    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
        status_store=store,
    )

    status = await manager.snapshot()

    assert status.running is True
    assert status.direction == "backward"
    assert status.current_date == date(2026, 1, 31)


async def test_forward_schedule_sync_start_persists_running_state_before_task_progress(
    monkeypatch,
) -> None:
    store = _workspace_test_store("start-persist")
    store.save(
        ForwardScheduleSyncStatus(
            running=False,
            state="stopped",
            provider_slug="sportsapipro-football-v2",
            started_from=date(2026, 1, 31),
            current_date=date(2026, 1, 31),
            direction="backward",
            max_days=20,
            last_message="Forward sync stopped.",
        )
    )
    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
        status_store=store,
    )
    blocker = asyncio.Event()

    async def fake_run_loop(
        provider_slug: str,
        start_date: date,
        direction: str,
        max_days: int | None,
    ) -> None:
        await blocker.wait()

    monkeypatch.setattr(manager, "_run_loop", fake_run_loop)

    started = await manager.start_with_options(
        provider_slug="sportsapipro-football-v2",
        start_date=date(2026, 1, 30),
        direction="backward",
        max_days=19,
    )
    visible = await manager.snapshot()

    assert started.running is True
    assert visible.running is True
    assert visible.state == "running"
    assert visible.started_from == date(2026, 1, 30)
    assert visible.current_date == date(2026, 1, 30)
    blocker.set()
    await manager._task


async def test_forward_schedule_sync_start_clears_stale_stop_request(monkeypatch) -> None:
    store = _workspace_test_store("start-clears-stop")
    store.request_stop()
    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
        status_store=store,
    )
    blocker = asyncio.Event()

    async def fake_run_loop(
        provider_slug: str,
        start_date: date,
        direction: str,
        max_days: int | None,
    ) -> None:
        await blocker.wait()

    monkeypatch.setattr(manager, "_run_loop", fake_run_loop)

    started = await manager.start_with_options(
        provider_slug="sportsapipro-football-v2",
        start_date=date(2026, 4, 8),
        direction="forward",
        max_days=365,
    )

    assert started.running is True
    assert store.stop_requested() is False
    blocker.set()
    await manager._task


async def test_forward_schedule_sync_consume_stop_request_clears_store_flag() -> None:
    store = _workspace_test_store("consume-clears-stop")
    store.request_stop()
    manager = ForwardScheduleSyncManager(
        session_factory=lambda: DummySessionContext(),
        sleep=lambda _: None,
        today_provider=lambda: date(2026, 4, 6),
        status_store=store,
    )
    manager._status = ForwardScheduleSyncStatus(running=True, state="running")

    stopped = await manager._consume_stop_request()

    assert stopped is True
    assert store.stop_requested() is False
