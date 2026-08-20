from datetime import UTC, date, datetime
from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.api.deps import get_db_session
from app.main import app
from app.providers.hybrid import HYBRID_LINEUP_PROVIDER_SLUG
from app.schemas.sync import SyncTriggerResponse
from app.services.catalog_service import CatalogDashboardSnapshot
from app.services.forward_schedule_sync import ForwardScheduleSyncStatus
from app.services.match_lineup_sync_job import MatchLineupSyncJobStatus
from app.services.schedule_sync_job import ScheduleSyncJobStatus
from app.ui import _match_player_sync_badge, _schedule_lineup_sync_form, _schedule_timezone_form


def test_ui_overview_renders_navigation(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_snapshot(_session):
        return CatalogDashboardSnapshot(
            counts={"countries": 1, "competitions": 1, "matches": 1, "sync_runs": 1},
            providers=[],
            sync_runs=[
                SimpleNamespace(
                    scope="matches",
                    status=SimpleNamespace(value="succeeded"),
                    started_at=SimpleNamespace(isoformat=lambda: "2026-04-06T10:00:00+00:00"),
                )
            ],
            countries=[SimpleNamespace(name="England", slug="england")],
            competitions=[SimpleNamespace(name="Premier League", slug="england-premier-league")],
            seasons=[],
            competition_seasons=[],
            matches=[
                SimpleNamespace(
                    kickoff_at=SimpleNamespace(isoformat=lambda: "2026-04-06T18:00:00+00:00"),
                    competition=SimpleNamespace(name="Premier League"),
                    home_team=SimpleNamespace(name="Arsenal"),
                    away_team=SimpleNamespace(name="Chelsea"),
                )
            ],
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.build_catalog_dashboard_snapshot", fake_snapshot)

    client = TestClient(app)
    response = client.get("/ui")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "Data Explorer" in response.text
    assert "Countries" in response.text
    assert "Competitions" in response.text
    assert "Futbolcular" in response.text
    assert "Matches" in response.text
    assert "Arsenal" in response.text
    assert "Run Match Sync" in response.text


def test_ui_countries_page_filters_and_links(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_list_countries(*, session, q, limit, offset):
        assert q == "eng"
        assert limit == 20
        assert offset == 40
        return [
            SimpleNamespace(
                name="England",
                slug="england",
                iso_code2="GB",
            )
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.list_countries", fake_list_countries)

    client = TestClient(app)
    response = client.get("/ui/countries?q=eng&limit=20&offset=40")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "England" in response.text
    assert "/ui/competitions?country_slug=england" in response.text


def test_ui_matches_page_filters(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_browse_matches(
        *,
        session,
        target_date,
        competition_slug,
        team_q,
        status,
        limit,
        offset,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert competition_slug == "england-premier-league"
        assert team_q == "arsenal"
        assert status == "finished"
        assert limit == 25
        assert offset == 0
        assert timezone_name == "Europe/Istanbul"
        return [
            SimpleNamespace(
                id="match-1",
                kickoff_at=SimpleNamespace(isoformat=lambda: "2026-04-06T18:00:00+00:00"),
                competition=SimpleNamespace(name="Premier League"),
                home_team=SimpleNamespace(name="Arsenal"),
                away_team=SimpleNamespace(name="Chelsea"),
                season=SimpleNamespace(label="2025/2026"),
                status=SimpleNamespace(value="finished"),
                score_home=2,
                score_away=1,
            )
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.browse_matches", fake_browse_matches)

    client = TestClient(app)
    response = client.get(
        "/ui/matches?target_date=2026-04-06&competition_slug=england-premier-league&team_q=arsenal&status=finished&tz=Europe/Istanbul&limit=25"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "Arsenal" in response.text
    assert "Premier League" in response.text
    assert "2025/2026" in response.text
    assert 'name="tz"' in response.text
    assert "Europe/Istanbul" in response.text


def test_ui_match_detail_page_renders_snapshot_cards(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_get_match_by_id(_session, match_id):
        assert str(match_id) == "00000000-0000-0000-0000-000000000123"
        return SimpleNamespace(
            id=match_id,
            entity_uid="match:test",
            kickoff_at=datetime(2026, 4, 6, 18, 0, tzinfo=UTC),
            competition=SimpleNamespace(name="Premier League", slug="england-premier-league"),
            season=SimpleNamespace(label="2025/2026", entity_uid="season:2025-2026"),
            status=SimpleNamespace(value="finished"),
            score_home=2,
            score_away=1,
            venue_name="Test Venue",
            provider_status="Finished",
            provider_last_synced_at=datetime(2026, 4, 6, 20, 0, tzinfo=UTC),
            home_team=SimpleNamespace(
                name="Arsenal",
                slug="arsenal",
                country=SimpleNamespace(name="England"),
            ),
            away_team=SimpleNamespace(
                name="Chelsea",
                slug="chelsea",
                country=SimpleNamespace(name="England"),
            ),
        )

    async def fake_latest_snapshot(self, *, match_id):
        assert str(match_id) == "00000000-0000-0000-0000-000000000123"
        return SimpleNamespace(
            snapshot_phase=SimpleNamespace(value="finalized"),
            snapshot_minute=90,
            snapshot_ts=datetime(2026, 4, 6, 19, 50, tzinfo=UTC),
            is_finalized=True,
            availability_json={"market_available": True, "xg_available": False},
            quality_json={"state_model_method": "heuristic"},
            source_json={"feature_version": "v1"},
            expected_goal_line_proxy=True,
            predicted_lineup_low_history=False,
            betfair_unavailable=True,
            state_model_home_prob=0.61,
            score_state_class="home_leading_by_1",
            market_state_class="strong_home_live",
            state_cluster_id=12,
            pre_home_prob=0.48,
            pre_draw_prob=0.27,
            pre_away_prob=0.25,
            pre_favorite_gap=0.21,
            pre_expected_goal_line=2.5,
            team_strength_diff=4.2,
            elo_diff=33.5,
            form_points_diff=2.0,
            xg_form_diff=0.35,
            xga_form_diff=-0.2,
            rest_days_diff=1.0,
            fatigue_diff=-45.0,
            pred_lineup_strength_diff=3.1,
            real_lineup_strength_diff=2.4,
            home_defense_strength=61.0,
            away_defense_strength=57.2,
            midfield_strength_diff=1.2,
            attack_strength_diff=4.8,
            lineup_surprise_score=0.14,
            rotation_diff=1.0,
            missing_strength_diff=-2.8,
            home_score=2,
            away_score=1,
            score_diff=1,
            goal_total=3,
            minute_norm=1.0,
            time_remaining_norm=0.0,
            home_red_cards=0,
            away_red_cards=1,
            red_card_diff=1,
            yellow_card_diff=2,
            subs_diff=0,
            time_since_last_goal=12,
            time_since_last_red_card=25,
            xg_diff_total=0.85,
            shots_diff_total=6,
            sot_diff_total=3,
            corners_diff_total=2,
            possession_diff=11,
            xg_diff_last5=0.1,
            xg_diff_last10=0.22,
            shots_diff_last5=1,
            shots_diff_last10=3,
            sot_diff_last10=2,
            dangerous_attacks_diff_last10=5,
            box_entries_diff_last10=3,
            pressure_diff_last10=0.42,
            momentum_diff=0.37,
            live_home_prob=0.72,
            live_draw_prob=0.18,
            live_away_prob=0.10,
            live_over25_prob=0.81,
            live_under25_prob=0.19,
            live_next_goal_home_prob=0.64,
            home_prob_shift_from_pre=0.24,
            draw_prob_shift_from_pre=-0.09,
            away_prob_shift_from_pre=-0.15,
            home_prob_change_last1=0.02,
            home_prob_change_last5=0.05,
            market_volatility_last5=0.03,
            favorite_fragility_score=0.21,
            underdog_resistance_score=0.34,
            comeback_potential_score=0.12,
            late_goal_risk_score=0.44,
            market_overreaction_score=0.08,
            market_underreaction_score=0.02,
            label_final_result_1x2="1",
            label_home_win=True,
            label_goal_next10min=False,
            label_next_goal_team="none",
            label_result_from_snapshot_to_end="draw",
            label_over25_from_snapshot=True,
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.get_match_by_id", fake_get_match_by_id)
    monkeypatch.setattr("app.ui.MatchFeatureSnapshotService.latest_snapshot", fake_latest_snapshot)

    client = TestClient(app)
    response = client.get("/ui/matches/00000000-0000-0000-0000-000000000123?tz=UTC")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "Feature Snapshot" in response.text
    assert "Pre-Match Context" in response.text
    assert "Lineup Edge" in response.text
    assert "Derived Scores" in response.text
    assert "Labels" in response.text
    assert "Latest JSON" in response.text
    assert "Live Snapshot List" in response.text


def test_ui_players_page_filters(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_count_provider_team_mappings(*, session, provider_slug):
        assert provider_slug == "sofascore-football"
        return 4955

    async def fake_list_sync_runs(*, session, scope, provider_slug, limit, offset):
        assert scope == "players"
        assert provider_slug == "sofascore-football"
        assert limit == 5
        assert offset == 0
        return [
            SimpleNamespace(
                status=SimpleNamespace(value="succeeded"),
                stats={
                    "players_upserted": 30,
                    "players_fetched": 35,
                    "teams_total_mapped": 4955,
                    "teams_scanned": 4,
                    "teams_synced": 3,
                    "teams_missing_roster": 1,
                    "teams_failed": 0,
                },
                error_message=None,
                started_at=SimpleNamespace(isoformat=lambda: "2026-04-07T10:00:00+00:00"),
                provider=SimpleNamespace(slug="sofascore-football"),
            )
        ]

    async def fake_list_players(*, session, q, country_slug, limit, offset):
        assert q == "messi"
        assert country_slug == "argentina"
        assert limit == 20
        assert offset == 40
        return [
            SimpleNamespace(
                full_name="Lionel Messi",
                short_name="Messi",
                slug="lionel-messi",
                country=SimpleNamespace(name="Argentina"),
            )
        ]

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.count_provider_team_mappings", fake_count_provider_team_mappings)
    monkeypatch.setattr("app.ui.list_sync_runs", fake_list_sync_runs)
    monkeypatch.setattr("app.ui.list_players", fake_list_players)

    client = TestClient(app)
    response = client.get("/ui/players?q=messi&country_slug=argentina&limit=20&offset=40")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "Lionel Messi" in response.text
    assert "Argentina" in response.text
    assert "lionel-messi" in response.text
    assert "Player Sync Durumu" in response.text
    assert "players_upserted" in response.text
    assert "30" in response.text
    assert "Mapped Teams For Provider" in response.text
    assert "4955" in response.text


def test_ui_player_sync_redirects(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        timezone_name=None,
        category_id=None,
        tournament_id=None,
    ):
        assert scope == "players"
        assert provider_slug == "sofascore-football"
        return SyncTriggerResponse(
            accepted=True,
            provider_slug=provider_slug,
            scope=scope,
            message="Player sync completed.",
            stats={"players_upserted": 30},
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.SyncService.trigger_provider_sync", fake_trigger_provider_sync)

    client = TestClient(app)
    response = client.get(
        "/ui/players/run?provider_slug=sofascore-football",
        follow_redirects=False,
    )

    app.dependency_overrides.clear()

    assert response.status_code == 303
    assert response.headers["location"].startswith("/ui/players?")
    assert "provider_slug=sofascore-football" in response.headers["location"]
    assert "message=" in response.headers["location"]

def test_ui_schedule_page_bootstraps_browser_timezone_when_missing(monkeypatch) -> None:
    async def override_session():
        yield object()

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui._today", lambda: date(2026, 4, 6))

    client = TestClient(app)
    response = client.get("/ui/schedule")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "Resolving Timezone" in response.text
    assert "Intl.DateTimeFormat().resolvedOptions().timeZone" in response.text
    assert 'name="target_date" value="2026-04-06"' in response.text
    assert "Load With Default TZ" in response.text


def test_ui_schedule_page_with_timezone_renders_date_nav(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_count_provider_match_player_sync(*, session, provider_slug, match_ids):
        assert provider_slug == "sofascore-football"
        assert match_ids == ["match-1"]
        return {
            "match-1": {
                "home": {"played": 11, "listed": 23},
                "away": {"played": 9, "listed": 21},
            }
        }

    async def fake_browse_matches(
        *,
        session,
        target_date,
        competition_slug,
        team_q,
        status,
        limit,
        offset,
        timezone_name,
    ):
        assert target_date == date(2026, 4, 6)
        assert competition_slug is None
        assert team_q is None
        assert status is None
        assert limit is None
        assert offset == 0
        assert timezone_name == "UTC"
        return [
            SimpleNamespace(
                id="match-1",
                kickoff_at=SimpleNamespace(isoformat=lambda: "2026-04-06T20:00:00+00:00"),
                competition=SimpleNamespace(name="Premier League", slug="england-premier-league"),
                home_team=SimpleNamespace(id="team-1", name="Arsenal"),
                away_team=SimpleNamespace(id="team-2", name="Chelsea"),
                season=SimpleNamespace(label="2025/2026", entity_uid="season:2025-2026"),
                status=SimpleNamespace(value="scheduled"),
                score_home=None,
                score_away=None,
            )
        ]

    async def fake_schedule_sync_snapshot():
        return ScheduleSyncJobStatus(
            running=True,
            state="running",
            provider_slug="sofascore-football",
            target_date=date(2026, 4, 6),
            timezone_name="UTC",
            last_message="Sofascore returned 403. Retrying in 60.0s (1/4).",
            status_code=403,
            attempt=1,
            attempts=4,
            wait_seconds=60.0,
            events=[
                "Sync started provider=sofascore-football date=2026-04-06 tz=UTC.",
                "Sofascore request attempt 1/4 for /api/v1/sport/football/scheduled-events/2026-04-06.",
                "Sofascore returned 403 for /api/v1/sport/football/scheduled-events/2026-04-06. Retrying in 60.0s (1/4).",
            ],
        )

    async def fake_match_lineup_sync_snapshot():
        return MatchLineupSyncJobStatus()

    async def fake_forward_schedule_sync_snapshot():
        return ForwardScheduleSyncStatus(
            running=True,
            state="running",
            provider_slug="sportsapipro-football-v2",
            started_from=date(2026, 1, 31),
            direction="backward",
            max_days=800,
            current_date=date(2026, 1, 21),
            last_completed_date=date(2026, 1, 22),
            processed_days=10,
            total_matches_downloaded=2774,
            successful_days=10,
            last_matches_count=159,
            last_message="Syncing 2026-01-21 (backward)...",
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui._today", lambda: date(2026, 4, 6))
    monkeypatch.setattr("app.ui.browse_matches", fake_browse_matches)
    monkeypatch.setattr("app.ui.count_provider_match_player_sync", fake_count_provider_match_player_sync)
    monkeypatch.setattr("app.ui.forward_schedule_sync_manager.snapshot", fake_forward_schedule_sync_snapshot)
    monkeypatch.setattr("app.ui.schedule_sync_job_manager.snapshot", fake_schedule_sync_snapshot)
    monkeypatch.setattr("app.ui.match_lineup_sync_job_manager.snapshot", fake_match_lineup_sync_snapshot)

    client = TestClient(app)
    response = client.get("/ui/schedule?tz=UTC&provider_slug=sofascore-football")

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert "2026-04-06" in response.text
    assert "Previous Day" in response.text
    assert "Next Day" in response.text
    assert "Sync This Day" in response.text
    assert 'action="/ui/schedule/run"' in response.text
    assert "target_date=2026-04-05" in response.text
    assert "target_date=2026-04-07" in response.text
    assert "tz=UTC" in response.text
    assert 'name="target_date" value="2026-04-06"' in response.text
    assert 'name="limit"' not in response.text
    assert 'name="tz" value="UTC"' in response.text
    assert 'name="provider_slug"' in response.text
    assert "sofascore-football" in response.text
    assert "Arsenal" in response.text
    assert "Match Players" in response.text
    assert "Sync Match Players" in response.text
    assert "Home 11/23 | Away 9/21" in response.text
    assert "Historical Schedule Runner" in response.text
    assert "2774" in response.text
    assert "Open Runner" in response.text
    assert "Schedule Sync Status" in response.text
    assert "Retrying in 60.0s" in response.text
    assert "window.location.reload()" in response.text


def test_schedule_lineup_sync_form_uses_provider_selector() -> None:
    html = _schedule_lineup_sync_form(
        date(2026, 4, 6),
        25,
        "Europe/Istanbul",
        "sofascore-football",
    )

    assert 'action="/ui/schedule/players/run"' in html
    assert '<select class="date-nav-btn" name="provider_slug">' in html
    assert '<option value="sofascore-football" selected>' in html
    assert (
        f'<option value="{HYBRID_LINEUP_PROVIDER_SLUG}" >SportsAPI Pro -&gt; Sofascore (Hybrid)</option>'
        in html
    )
    assert '<input type="hidden" name="provider_slug"' not in html


def test_schedule_timezone_form_preserves_provider_slug() -> None:
    html = _schedule_timezone_form(
        date(2026, 4, 6),
        "Europe/Istanbul",
        25,
        "sofascore-football",
    )

    assert 'action="/ui/schedule"' in html
    assert '<input type="hidden" name="provider_slug" value="sofascore-football"' in html


def test_match_player_sync_badge_shows_no_lineup_marker() -> None:
    badge = _match_player_sync_badge(
        SimpleNamespace(
            id="match-1",
            metadata_json={
                "lineup": {
                    "status": "missing",
                    "provider_slug": "sofascore-football",
                }
            },
        ),
        {},
        provider_slug="sofascore-football",
    )

    assert "no lineup" in badge


def test_match_player_sync_badge_shows_no_lineup_marker_for_hybrid_provider() -> None:
    badge = _match_player_sync_badge(
        SimpleNamespace(
            id="match-1",
            metadata_json={
                "lineup": {
                    "status": "missing",
                    "provider_slug": "sofascore-football",
                }
            },
        ),
        {},
        provider_slug=HYBRID_LINEUP_PROVIDER_SLUG,
    )

    assert "no lineup" in badge


def test_ui_country_bootstrap_redirects(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        timezone_name=None,
        category_id=None,
        tournament_id=None,
    ):
        assert scope == "bootstrap-countries"
        return SyncTriggerResponse(
            accepted=True,
            provider_slug=provider_slug,
            scope=scope,
            message="Bootstrap completed.",
            stats={"countries_upserted": 3},
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.SyncService.trigger_provider_sync", fake_trigger_provider_sync)

    client = TestClient(app)
    response = client.post("/ui/bootstrap/countries/run", follow_redirects=False)

    app.dependency_overrides.clear()

    assert response.status_code == 303
    assert "/ui?message=" in response.headers["location"]


def test_ui_match_sync_redirects(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_trigger_provider_sync(
        self,
        *,
        provider_slug,
        scope,
        target_date,
        timezone_name=None,
        category_id=None,
        tournament_id=None,
    ):
        assert scope == "matches"
        assert str(target_date) == "2026-04-06"
        assert provider_slug == "sofascore-football"
        return SyncTriggerResponse(
            accepted=True,
            provider_slug=provider_slug,
            scope=scope,
            target_date=target_date,
            message="Match sync completed.",
            stats={"matches_count": 48},
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.SyncService.trigger_provider_sync", fake_trigger_provider_sync)

    client = TestClient(app)
    response = client.get(
        "/ui/matches/run?target_date=2026-04-06&provider_slug=sofascore-football",
        follow_redirects=False,
    )

    app.dependency_overrides.clear()

    assert response.status_code == 303
    assert "/ui?message=" in response.headers["location"]


def test_ui_schedule_sync_redirects_back_to_selected_day(monkeypatch) -> None:
    async def override_session():
        yield object()

    async def fake_start(
        *,
        provider_slug,
        target_date,
        timezone_name=None,
    ):
        assert str(target_date) == "2026-04-06"
        assert provider_slug == "sofascore-football"
        assert timezone_name == "Europe/Istanbul"
        return ScheduleSyncJobStatus(
            running=True,
            state="running",
            provider_slug=provider_slug,
            target_date=target_date,
            timezone_name=timezone_name,
            last_message="Schedule sync started.",
        )

    app.dependency_overrides[get_db_session] = override_session
    monkeypatch.setattr("app.ui.schedule_sync_job_manager.start", fake_start)

    client = TestClient(app)
    response = client.post(
        "/ui/schedule/run",
        data={
            "target_date": "2026-04-06",
            "limit": "25",
            "tz": "Europe/Istanbul",
            "provider_slug": "sofascore-football",
        },
        follow_redirects=False,
    )

    app.dependency_overrides.clear()

    assert response.status_code == 303
    assert "/ui/schedule?" in response.headers["location"]
    assert "target_date=2026-04-06" in response.headers["location"]
    assert "tz=Europe%2FIstanbul" in response.headers["location"]
    assert "provider_slug=sofascore-football" in response.headers["location"]
    assert "message=" in response.headers["location"]


def test_ui_schedule_lineup_sync_redirects_back_to_selected_day(monkeypatch) -> None:
    async def fake_start(
        *,
        provider_slug,
        target_date,
        timezone_name=None,
    ):
        assert str(target_date) == "2026-04-06"
        assert provider_slug == "sportsapipro-football-v2"
        assert timezone_name == "Europe/Istanbul"
        return MatchLineupSyncJobStatus(
            running=True,
            state="running",
            provider_slug=provider_slug,
            target_date=target_date,
            timezone_name=timezone_name,
            last_message="Match player sync started for 2026-04-06.",
        )

    monkeypatch.setattr("app.ui.match_lineup_sync_job_manager.start", fake_start)

    client = TestClient(app)
    response = client.post(
        "/ui/schedule/players/run",
        data={
            "target_date": "2026-04-06",
            "limit": "25",
            "tz": "Europe/Istanbul",
            "provider_slug": "sportsapipro-football-v2",
        },
        follow_redirects=False,
    )

    assert response.status_code == 303
    assert "/ui/schedule?" in response.headers["location"]
    assert "target_date=2026-04-06" in response.headers["location"]
    assert "tz=Europe%2FIstanbul" in response.headers["location"]
    assert "provider_slug=sportsapipro-football-v2" in response.headers["location"]
    assert "message=" in response.headers["location"]


def test_ui_forward_schedule_sync_page_renders_status(monkeypatch) -> None:
    async def fake_snapshot():
        return ForwardScheduleSyncStatus(
            running=True,
            state="running",
            provider_slug="sofascore-football",
            started_from=date(2026, 4, 6),
            direction="backward",
            max_days=30,
            current_date=date(2026, 4, 8),
            last_completed_date=date(2026, 4, 7),
            processed_days=3,
            total_matches_downloaded=128,
            successful_days=2,
            retry_count=1,
            last_matches_count=73,
            last_message="Syncing 2026-04-08...",
        )

    monkeypatch.setattr("app.ui.forward_schedule_sync_manager.snapshot", fake_snapshot)

    client = TestClient(app)
    response = client.get("/ui/schedule/forward-sync")

    assert response.status_code == 200
    assert "Schedule Runner" in response.text
    assert "2026-04-08" in response.text
    assert "128" in response.text
    assert "Stop Run" in response.text
    assert "backward" in response.text
    assert "sofascore-football" in response.text
    assert "setTimeout(() => window.location.reload(), 2500);" in response.text


def test_ui_forward_schedule_sync_start_redirects(monkeypatch) -> None:
    async def fake_start_with_options(*, provider_slug, start_date, direction, max_days):
        assert provider_slug == "sofascore-football"
        assert start_date == date(2026, 4, 5)
        assert direction == "backward"
        assert max_days == 30
        return ForwardScheduleSyncStatus(
            running=True,
            state="running",
            provider_slug="sofascore-football",
            started_from=date(2026, 4, 5),
            direction="backward",
            max_days=30,
            current_date=date(2026, 4, 5),
            last_message="Backward schedule sync started from 2026-04-05.",
        )

    monkeypatch.setattr(
        "app.ui.forward_schedule_sync_manager.start_with_options",
        fake_start_with_options,
    )

    client = TestClient(app)
    response = client.post(
        "/ui/schedule/forward-sync/start",
        data={
            "provider_slug": "sofascore-football",
            "start_date": "2026-04-05",
            "direction": "backward",
            "max_days": "30",
        },
        follow_redirects=False,
    )

    assert response.status_code == 303
    assert response.headers["location"].startswith("/ui/schedule/forward-sync?")
    assert "message=" in response.headers["location"]


def test_ui_forward_schedule_sync_stop_redirects(monkeypatch) -> None:
    async def fake_stop():
        return ForwardScheduleSyncStatus(
            running=True,
            state="running",
            started_from=date(2026, 4, 6),
            current_date=date(2026, 4, 8),
            last_message="Stop requested. Current day will finish first.",
        )

    monkeypatch.setattr("app.ui.forward_schedule_sync_manager.stop", fake_stop)

    client = TestClient(app)
    response = client.post("/ui/schedule/forward-sync/stop", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"].startswith("/ui/schedule/forward-sync?")
    assert "message=" in response.headers["location"]
