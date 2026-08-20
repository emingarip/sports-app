from datetime import UTC, date, datetime
from types import SimpleNamespace
from uuid import uuid4

from fastapi.testclient import TestClient

from app.api.deps import get_db_session
from app.db.models.domain import MatchLiveStatFrame, Provider, SnapshotPhase, SyncRun, SyncRunStatus
from app.main import app
from app.providers.base import (
    ProviderBatch,
    ProviderMatchLiveStatFrameSeed,
    ProviderMatchMarketTickSeed,
    ProviderMatchSeed,
    ProviderTeamSeed,
)
from app.services.feature_pipeline_job import FeaturePipelineJobStatus
from app.services.match_context_persistence import MatchContextPersistenceService
from app.services.match_feature_snapshot_service import MatchFeatureSnapshotService
from app.services.sync_service import SyncService


def test_snapshot_service_builds_prematch_market_context() -> None:
    service = MatchFeatureSnapshotService(object())
    ticks = [
        SimpleNamespace(
            snapshot_phase=SnapshotPhase.pre,
            market_type="1x2",
            selection_key="home",
            odds_decimal=2.0,
            line_value=None,
        ),
        SimpleNamespace(
            snapshot_phase=SnapshotPhase.pre,
            market_type="1x2",
            selection_key="draw",
            odds_decimal=3.0,
            line_value=None,
        ),
        SimpleNamespace(
            snapshot_phase=SnapshotPhase.pre,
            market_type="1x2",
            selection_key="away",
            odds_decimal=4.0,
            line_value=None,
        ),
        SimpleNamespace(
            snapshot_phase=SnapshotPhase.pre,
            market_type="totals",
            selection_key="over",
            odds_decimal=1.95,
            line_value=2.5,
        ),
        SimpleNamespace(
            snapshot_phase=SnapshotPhase.pre,
            market_type="totals",
            selection_key="under",
            odds_decimal=1.95,
            line_value=2.5,
        ),
    ]

    context = service._build_pre_market_context(market_ticks=ticks)

    assert round(context["pre_home_prob"], 3) == 0.462
    assert round(context["pre_draw_prob"], 3) == 0.308
    assert round(context["pre_away_prob"], 3) == 0.231
    assert context["pre_expected_goal_line"] == 2.5
    assert context["expected_goal_line_proxy"] is False


def test_snapshot_service_builds_labels_from_future_goals() -> None:
    service = MatchFeatureSnapshotService(object())
    match = SimpleNamespace(score_home=2, score_away=1, status=SimpleNamespace(value="finished"))
    event_rows = [
        SimpleNamespace(event_type="Goal", event_subtype=None, team_side="home", minute=12, stoppage_minute=0),
        SimpleNamespace(event_type="Goal", event_subtype=None, team_side="away", minute=81, stoppage_minute=0),
    ]

    labels = service._build_labels(
        match=match,
        minute=20,
        max_minute=90,
        event_rows=event_rows,
        current_home_score=1,
        current_away_score=0,
        score_conflict_with_final=False,
    )

    assert labels["label_final_result_1x2"] == "1"
    assert labels["label_goal_next10min"] is False
    assert labels["label_next_goal_team"] == "away"
    assert labels["label_result_from_snapshot_to_end"] == "away"
    assert labels["label_over25_from_snapshot"] is True


def test_snapshot_service_builds_no_labels_until_match_is_finished() -> None:
    service = MatchFeatureSnapshotService(object())
    match = SimpleNamespace(score_home=None, score_away=None, status=SimpleNamespace(value="live"))

    labels = service._build_labels(
        match=match,
        minute=20,
        max_minute=90,
        event_rows=[],
        current_home_score=1,
        current_away_score=0,
        score_conflict_with_final=False,
    )

    assert labels["label_final_result_1x2"] is None
    assert labels["label_home_win"] is None
    assert labels["label_goal_next10min"] is None
    assert labels["label_next_goal_team"] is None
    assert labels["label_result_from_snapshot_to_end"] is None
    assert labels["label_over25_from_snapshot"] is None


def test_snapshot_service_reconciles_finalized_score_and_marks_conflict_not_trainable() -> None:
    service = MatchFeatureSnapshotService(object())
    match = SimpleNamespace(
        id=uuid4(),
        kickoff_at=datetime(2026, 4, 7, 18, 0, tzinfo=UTC),
        score_home=0,
        score_away=2,
        status=SimpleNamespace(value="finished"),
    )
    event_rows = [
        SimpleNamespace(event_type="Goal", event_subtype=None, team_side="home", minute=61, stoppage_minute=0),
        SimpleNamespace(event_type="Goal", event_subtype=None, team_side="away", minute=72, stoppage_minute=0),
        SimpleNamespace(event_type="Goal", event_subtype=None, team_side="away", minute=88, stoppage_minute=0),
    ]
    frame = SimpleNamespace(
        home_xg=2.29,
        away_xg=0.0,
        home_shots=22,
        away_shots=0,
        home_shots_on_target=10,
        away_shots_on_target=0,
        home_corners=None,
        away_corners=None,
        home_possession=None,
        away_possession=None,
        home_dangerous_attacks=None,
        away_dangerous_attacks=None,
        home_box_entries=None,
        away_box_entries=None,
        home_pressure_index=1.2,
        away_pressure_index=0.1,
    )
    payload = service._compose_snapshot_payload(
        match=match,
        phase=SnapshotPhase.finalized,
        minute=96,
        max_minute=96,
        model=None,
        cluster_model=None,
        event_rows=event_rows,
        static_context={
            "pre_market": {
                "pre_home_prob": 0.39,
                "pre_draw_prob": 0.31,
                "pre_away_prob": 0.30,
                "pre_favorite_gap": 0.08,
                "pre_expected_goal_line": 2.5,
                "expected_goal_line_proxy": False,
            },
            "pred_home": {"strength": 49.0, "strength_diff": 1.0},
            "pred_away": {"strength": 48.0, "strength_diff": -1.0},
            "real_home": {
                "players": {uuid4()},
                "strength": 47.0,
                "strength_diff": -1.0,
                "defense_strength": 44.0,
                "mid_strength": 45.0,
                "att_strength": 46.0,
            },
            "real_away": {
                "players": {uuid4()},
                "strength": 48.0,
                "strength_diff": 1.0,
                "defense_strength": 45.0,
                "mid_strength": 46.0,
                "att_strength": 47.0,
            },
            "team_strength_diff": -0.2,
            "elo_diff": -12.0,
            "form_points_diff": -1.0,
            "xg_form_diff": -0.1,
            "xga_form_diff": 0.2,
            "rest_days_diff": 0.0,
            "fatigue_diff": 30.0,
            "lineup_surprise_score": 0.15,
            "rotation_diff": 0.0,
            "missing_strength_diff": 4.0,
            "predicted_lineup_low_history": False,
        },
        dynamic_context={
            "home_score": 1,
            "away_score": 2,
            "home_red_cards": 1,
            "away_red_cards": 0,
            "yellow_card_diff": -2,
            "subs_diff": 1,
            "time_since_last_goal": 8,
            "time_since_last_red_card": 30,
            "frame": frame,
            "frame_last5": None,
            "frame_last10": None,
            "market": {
                "live_home_prob": 0.43,
                "live_draw_prob": 0.29,
                "live_away_prob": 0.28,
                "live_over25_prob": 0.24,
                "live_under25_prob": 0.76,
                "live_next_goal_home_prob": None,
                "home_prob_change_last1": None,
                "home_prob_change_last5": None,
                "market_volatility_last5": 0.02,
                "market_time_precision": "timestamp_only",
            },
        },
    )

    assert payload["home_score"] == 0
    assert payload["away_score"] == 2
    assert payload["score_diff"] == -2
    assert payload["label_final_result_1x2"] == "2"
    assert payload["label_goal_next10min"] is None
    assert payload["quality_json"]["score_conflict_with_final"] is True
    assert payload["quality_json"]["trainable_snapshot"] is False
    assert payload["quality_json"]["score_integrity"] == "reconciled_final_score"


async def test_snapshot_service_historical_training_rows_skip_untrainable_snapshots() -> None:
    class SnapshotResult:
        def __init__(self, rows) -> None:
            self._rows = rows

        def scalars(self):
            return self

        def all(self):
            return self._rows

    class TrainingSession:
        async def execute(self, _query):
            return SnapshotResult(
                [
                    SimpleNamespace(
                        quality_json={"trainable_snapshot": False},
                        snapshot_minute=50,
                        team_strength_diff=0.1,
                        pred_lineup_strength_diff=1.0,
                        real_lineup_strength_diff=1.0,
                        score_diff=0,
                        xg_diff_total=0.2,
                        shots_diff_total=2.0,
                        momentum_diff=0.1,
                        red_card_diff=0,
                        pre_home_prob=0.55,
                        label_home_win=True,
                    ),
                    SimpleNamespace(
                        quality_json={"trainable_snapshot": True},
                        snapshot_minute=51,
                        team_strength_diff=0.2,
                        pred_lineup_strength_diff=1.5,
                        real_lineup_strength_diff=1.0,
                        score_diff=1,
                        xg_diff_total=0.4,
                        shots_diff_total=3.0,
                        momentum_diff=0.2,
                        red_card_diff=0,
                        pre_home_prob=0.60,
                        label_home_win=False,
                    ),
                ]
            )

    service = MatchFeatureSnapshotService(TrainingSession())

    features, labels = await service._historical_training_rows(
        before=datetime(2026, 4, 7, 0, 0, tzinfo=UTC)
    )

    assert len(features) == 1
    assert len(labels) == 1
    assert labels == [0]
    assert features[0][0] == 51.0


def test_snapshot_service_comeback_score_handles_missing_momentum() -> None:
    service = MatchFeatureSnapshotService(object())

    score = service._comeback_potential_score(
        score_diff=1,
        time_remaining_norm=0.4,
        momentum_diff=None,
        favorite_fragility_score=0.2,
    )

    assert score is not None
    assert 0.0 <= score <= 1.0


class FakeResult:
    @staticmethod
    def scalar_one_or_none():
        return None


class FakeSession:
    def __init__(self) -> None:
        self.added = []
        self.lookup = {}
        self.rolled_back = False

    async def execute(self, _query):
        return FakeResult()

    def add(self, obj) -> None:
        self.added.append(obj)
        obj_id = getattr(obj, "id", None)
        if obj_id is not None:
            self.lookup[(type(obj), obj_id)] = obj

    async def flush(self) -> None:
        for obj in self.added:
            if getattr(obj, "id", None) is None:
                obj.id = uuid4()
            self.lookup[(type(obj), obj.id)] = obj

    async def commit(self) -> None:
        self.rolled_back = False
        return None

    async def refresh(self, _obj) -> None:
        return None

    async def rollback(self) -> None:
        self.rolled_back = True
        return None

    async def get(self, model, ident):
        return self.lookup.get((model, ident))


class FeatureProviderClient:
    slug = "sportsapipro-football-v1"
    display_name = "SportsAPI Pro Football V1"
    base_url = "https://v1.football.sportsapipro.com"

    async def fetch(self, *, scope, target_date):
        return ProviderBatch(
            scope=scope,
            target_date=target_date,
            matches=[
                ProviderMatchSeed(
                    provider_match_id="4001",
                    kickoff_at=datetime(2026, 4, 7, 18, 0, tzinfo=UTC),
                    status="finished",
                    provider_status="Finished",
                    home_team=ProviderTeamSeed(provider_team_id="1", name="Home FC"),
                    away_team=ProviderTeamSeed(provider_team_id="2", name="Away FC"),
                )
            ],
        )

    async def get_prematch_markets(self, match_id: str):
        assert match_id == "4001"
        return [
            ProviderMatchMarketTickSeed(
                provider_match_id=match_id,
                phase="pre",
                market_type="1x2",
                selection_key="home",
                odds_decimal=2.0,
            )
        ]

    async def get_live_markets(self, match_id: str):
        assert match_id == "4001"
        return []


async def test_sync_service_market_backfill_returns_stats(monkeypatch) -> None:
    session = FakeSession()
    service = SyncService(session)
    provider = Provider(
        id=uuid4(),
        slug="sportsapipro-football-v1",
        name="SportsAPI Pro Football V1",
        base_url="https://v1.football.sportsapipro.com",
        is_active=True,
        metadata_json={},
    )
    match_id = uuid4()
    match_record = SimpleNamespace(id=match_id, metadata_json={})

    async def fake_get_or_create_provider(*, provider_slug, client):
        assert provider_slug == "sportsapipro-football-v1"
        return provider

    async def fake_persist_batch(self, *, provider, sync_run, batch):
        assert len(batch.matches) == 1
        return {"matches_upserted": 1}

    async def fake_get_provider_match_mappings(*, provider, target_date, timezone_name):
        assert target_date == date(2026, 4, 7)
        return [(match_record, "4001")]

    async def fake_get_match_for_lineup_sync(match_id):
        assert match_id == match_record.id
        return match_record

    async def fake_persist_markets(
        self,
        *,
        provider,
        sync_run,
        match,
        provider_match_id,
        prematch_ticks,
        live_ticks,
    ):
        assert provider_match_id == "4001"
        assert len(prematch_ticks) == 1
        self.stats.market_ticks_upserted = 1
        self.stats.raw_payloads_written = 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        "app.services.match_persistence.MatchPersistenceService.persist_batch",
        fake_persist_batch,
    )
    monkeypatch.setattr(service, "_get_provider_match_mappings", fake_get_provider_match_mappings)
    monkeypatch.setattr(service, "_get_match_for_lineup_sync", fake_get_match_for_lineup_sync)
    monkeypatch.setattr(
        "app.services.match_context_persistence.MatchContextPersistenceService.persist_markets",
        fake_persist_markets,
    )

    response = await service.trigger_provider_sync(
        provider_slug="sportsapipro-football-v1",
        scope="market-backfill",
        target_date=date(2026, 4, 7),
        timezone_name="Europe/Istanbul",
        client_override=FeatureProviderClient(),
    )

    assert response.accepted is True
    assert response.status == SyncRunStatus.succeeded
    assert response.stats["matches_total"] == 1
    assert response.stats["matches_synced"] == 1
    assert response.stats["market_ticks_upserted"] == 1


async def test_match_context_persistence_dedupes_duplicate_live_frames() -> None:
    session = FakeSession()
    service = MatchContextPersistenceService(session)
    provider = Provider(
        id=uuid4(),
        slug="sportsapipro-football-v1",
        name="SportsAPI Pro Football V1",
        base_url="https://v1.football.sportsapipro.com",
        is_active=True,
        metadata_json={},
    )
    match = SimpleNamespace(
        id=uuid4(),
        kickoff_at=datetime(2026, 4, 7, 18, 0, tzinfo=UTC),
    )

    await service.persist_context(
        provider=provider,
        sync_run=None,
        match=match,
        provider_match_id="4001",
        incidents=[],
        live_frames=[
            ProviderMatchLiveStatFrameSeed(
                provider_match_id="4001",
                minute=58,
                frame_time=datetime(2026, 4, 7, 18, 58, tzinfo=UTC),
                home_xg=0.5,
                home_shots=5,
                raw={"seq": 1},
            ),
            ProviderMatchLiveStatFrameSeed(
                provider_match_id="4001",
                minute=58,
                frame_time=datetime(2026, 4, 7, 18, 58, tzinfo=UTC),
                home_xg=0.7,
                home_shots=6,
                raw={"seq": 2},
            ),
        ],
        shots=[],
    )

    frames = [obj for obj in session.added if isinstance(obj, MatchLiveStatFrame)]
    assert len(frames) == 1
    assert frames[0].home_xg == 0.7
    assert frames[0].home_shots == 6
    assert service.stats.live_stat_frames_upserted == 1


async def test_sync_service_context_backfill_rolls_back_failed_match_and_continues(monkeypatch) -> None:
    session = FakeSession()
    service = SyncService(session)
    provider = Provider(
        id=uuid4(),
        slug="sportsapipro-football-v1",
        name="SportsAPI Pro Football V1",
        base_url="https://v1.football.sportsapipro.com",
        is_active=True,
        metadata_json={},
    )
    first_match = SimpleNamespace(id=uuid4(), metadata_json={})
    second_match = SimpleNamespace(id=uuid4(), metadata_json={})

    class ContextProviderClient(FeatureProviderClient):
        async def get_match_incidents(self, match_id: str):
            return []

        async def get_match_live_stats(self, match_id: str):
            return []

        async def get_match_shotmap(self, match_id: str):
            return []

    async def fake_get_or_create_provider(*, provider_slug, client):
        assert provider_slug == "sportsapipro-football-v1"
        return provider

    async def fake_persist_batch(self, *, provider, sync_run, batch):
        assert len(batch.matches) == 1
        return {"matches_upserted": 1}

    async def fake_get_provider_match_mappings(*, provider, target_date, timezone_name):
        return [(first_match, "4001"), (second_match, "4002")]

    async def fake_get_match_for_lineup_sync(match_id):
        if match_id == first_match.id:
            return first_match
        if match_id == second_match.id:
            return second_match
        return None

    async def fake_persist_context(
        self,
        *,
        provider,
        sync_run,
        match,
        provider_match_id,
        incidents,
        live_frames,
        shots,
    ):
        if provider_match_id == "4001":
            raise RuntimeError("frame conflict")
        self.stats.live_stat_frames_upserted += 1
        return {}

    monkeypatch.setattr(service, "_get_or_create_provider", fake_get_or_create_provider)
    monkeypatch.setattr(
        "app.services.match_persistence.MatchPersistenceService.persist_batch",
        fake_persist_batch,
    )
    monkeypatch.setattr(service, "_get_provider_match_mappings", fake_get_provider_match_mappings)
    monkeypatch.setattr(service, "_get_match_for_lineup_sync", fake_get_match_for_lineup_sync)
    monkeypatch.setattr(
        "app.services.match_context_persistence.MatchContextPersistenceService.persist_context",
        fake_persist_context,
    )

    response = await service.trigger_provider_sync(
        provider_slug="sportsapipro-football-v1",
        scope="context-backfill",
        target_date=date(2026, 4, 7),
        timezone_name="Europe/Istanbul",
        client_override=ContextProviderClient(),
    )

    assert response.accepted is True
    assert response.status == SyncRunStatus.succeeded
    assert response.stats["matches_total"] == 2
    assert response.stats["matches_synced"] == 1
    assert response.stats["matches_failed"] == 1
    assert session.rolled_back is False


async def test_sync_service_market_backfill_uses_cached_sync_run_id_after_rollback(
    monkeypatch,
) -> None:
    class PoisonedSyncRun:
        def __init__(self, sync_run_id, started_at):
            self._id = sync_run_id
            self._poisoned = False
            self.status = SyncRunStatus.running
            self.started_at = started_at
            self.completed_at = None
            self.error_message = None
            self.stats = None

        @property
        def id(self):
            if self._poisoned:
                raise RuntimeError("expired sync_run.id accessed after rollback")
            return self._id

        @id.setter
        def id(self, value):
            self._id = value

    class ExpiringFakeSession(FakeSession):
        def __init__(self, original_sync_run, replacement_sync_run) -> None:
            super().__init__()
            self.original_sync_run = original_sync_run
            self.lookup[(SyncRun, replacement_sync_run.id)] = replacement_sync_run

        async def rollback(self) -> None:
            self.original_sync_run._poisoned = True
            await super().rollback()

    sync_started_at = datetime(2026, 4, 7, 18, 0, tzinfo=UTC)
    sync_run_id = uuid4()
    poisoned_sync_run = PoisonedSyncRun(sync_run_id, sync_started_at)
    replacement_sync_run = SimpleNamespace(
        id=sync_run_id,
        status=SyncRunStatus.running,
        started_at=sync_started_at,
        completed_at=None,
        error_message=None,
        stats=None,
    )
    session = ExpiringFakeSession(poisoned_sync_run, replacement_sync_run)
    service = SyncService(session)
    provider = Provider(
        id=uuid4(),
        slug="sportsapipro-football-v1",
        name="SportsAPI Pro Football V1",
        base_url="https://v1.football.sportsapipro.com",
        is_active=True,
        metadata_json={},
    )
    first_match = SimpleNamespace(id=uuid4(), metadata_json={})
    second_match = SimpleNamespace(id=uuid4(), metadata_json={})

    class ContextProviderClient(FeatureProviderClient):
        async def get_prematch_markets(self, match_id: str):
            return []

        async def get_live_markets(self, match_id: str):
            return []

    async def fake_persist_batch(self, *, provider, sync_run, batch):
        assert len(batch.matches) == 1
        return {"matches_upserted": 1}

    async def fake_get_provider_match_mappings(*, provider, target_date, timezone_name):
        return [(first_match, "4001"), (second_match, "4002")]

    async def fake_get_match_for_lineup_sync(match_id):
        if match_id == first_match.id:
            return first_match
        if match_id == second_match.id:
            return second_match
        return None

    async def fake_persist_markets(
        self,
        *,
        provider,
        sync_run,
        match,
        provider_match_id,
        prematch_ticks,
        live_ticks,
    ):
        if provider_match_id == "4001":
            raise RuntimeError("market conflict")
        self.stats.market_ticks_upserted += 1
        return {}

    monkeypatch.setattr(
        "app.services.match_persistence.MatchPersistenceService.persist_batch",
        fake_persist_batch,
    )
    monkeypatch.setattr(service, "_get_provider_match_mappings", fake_get_provider_match_mappings)
    monkeypatch.setattr(service, "_get_match_for_lineup_sync", fake_get_match_for_lineup_sync)
    monkeypatch.setattr(
        "app.services.match_context_persistence.MatchContextPersistenceService.persist_markets",
        fake_persist_markets,
    )

    response = await service._trigger_match_context_sync(
        provider=provider,
        client=ContextProviderClient(),
        scope="market-backfill",
        sync_run=poisoned_sync_run,
        target_date=date(2026, 4, 7),
        timezone_name="Europe/Istanbul",
        progress_callback=None,
        sync_started_at=sync_started_at,
    )

    assert response.accepted is True
    assert response.status == SyncRunStatus.succeeded
    assert response.stats["matches_synced"] == 1
    assert response.stats["matches_failed"] == 1


def test_matches_snapshot_route_returns_rows(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_snapshots(self, *, match_id, phase, limit):
        assert phase == "live"
        assert limit == 50
        return [
            SimpleNamespace(
                __table__=SimpleNamespace(columns=[SimpleNamespace(name="snapshot_minute"), SimpleNamespace(name="market_state_class")]),
                snapshot_minute=55,
                market_state_class="balanced_live",
            )
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr(
        "app.api.routes.matches.MatchFeatureSnapshotService.list_snapshots",
        fake_list_snapshots,
    )

    client = TestClient(app)
    response = client.get(f"/api/v1/matches/{uuid4()}/snapshots?phase=live&limit=50")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()[0]["snapshot_minute"] == 55
    assert response.json()[0]["market_state_class"] == "balanced_live"


def test_serialize_snapshot_uses_column_keys_for_metadata_alias() -> None:
    from app.api.routes.matches import _serialize_snapshot

    snapshot = SimpleNamespace(
        __table__=SimpleNamespace(
            columns=[
                SimpleNamespace(name="metadata", key="metadata_json"),
                SimpleNamespace(name="snapshot_minute", key="snapshot_minute"),
            ]
        ),
        metadata_json={"available": True},
        snapshot_minute=55,
    )

    payload = _serialize_snapshot(snapshot)

    assert payload["metadata_json"] == {"available": True}
    assert payload["snapshot_minute"] == 55


def test_ui_schedule_feature_pipeline_redirects(monkeypatch) -> None:
    async def fake_start(*, provider_slug, target_date, timezone_name):
        assert provider_slug == "sportsapipro-football-v1"
        assert target_date == date(2026, 4, 7)
        assert timezone_name == "Europe/Istanbul"
        return FeaturePipelineJobStatus(
            running=True,
            state="running",
            provider_slug=provider_slug,
            target_date=target_date,
            timezone_name=timezone_name,
            current_scope="market-backfill",
            last_message="Feature pipeline started for 2026-04-07.",
        )

    monkeypatch.setattr("app.ui.feature_pipeline_job_manager.start", fake_start)

    client = TestClient(app)
    response = client.post(
        "/ui/schedule/features/run",
        data={
            "target_date": "2026-04-07",
            "limit": "25",
            "tz": "Europe/Istanbul",
            "provider_slug": "sofascore-football",
        },
        follow_redirects=False,
    )

    assert response.status_code == 303
    assert "target_date=2026-04-07" in response.headers["location"]
    assert "tz=Europe%2FIstanbul" in response.headers["location"]
    assert "provider_slug=sofascore-football" in response.headers["location"]
    assert "message=" in response.headers["location"]


def test_matches_latest_snapshot_route_returns_404(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_latest_snapshot(self, *, match_id):
        return None

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr(
        "app.api.routes.matches.MatchFeatureSnapshotService.latest_snapshot",
        fake_latest_snapshot,
    )

    client = TestClient(app)
    response = client.get(f"/api/v1/matches/{uuid4()}/snapshots/latest")

    app.dependency_overrides.clear()

    assert response.status_code == 404
