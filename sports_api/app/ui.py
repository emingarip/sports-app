from __future__ import annotations

from dataclasses import replace
from datetime import date, timedelta
from html import escape
from typing import Annotated
from urllib.parse import quote_plus, urlencode
from uuid import UUID

from fastapi import APIRouter, Depends, Form, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, verify_internal_token
from app.core.timezones import DEFAULT_TIMEZONE, canonical_timezone_name, convert_datetime
from app.providers.hybrid import (
    HYBRID_LINEUP_PROVIDER_NAME,
    HYBRID_LINEUP_PROVIDER_SLUG,
    expand_lineup_provider_slugs,
)
from app.providers.registry import REGISTERED_PROVIDER_CLIENTS
from app.services.catalog_service import (
    CatalogDashboardSnapshot,
    browse_matches,
    build_catalog_dashboard_snapshot,
    count_provider_match_player_sync,
    count_provider_team_mappings,
    get_competition_by_slug,
    get_country_by_slug,
    get_match_by_id,
    get_season_by_entity_uid,
    get_team_by_slug,
    list_competitions,
    list_competitions_for_country,
    list_competitions_for_season,
    list_countries,
    list_matches_for_competition,
    list_matches_for_country,
    list_matches_for_season,
    list_matches_for_team,
    list_players,
    list_seasons,
    list_sync_runs,
    list_teams,
)
from app.services.feature_pipeline_job import (
    FEATURE_PIPELINE_PROVIDER,
    feature_pipeline_job_manager,
)
from app.services.forward_schedule_sync import forward_schedule_sync_manager
from app.services.match_feature_snapshot_service import MatchFeatureSnapshotService
from app.services.match_lineup_sync_job import match_lineup_sync_job_manager
from app.services.schedule_sync_job import schedule_sync_job_manager
from app.services.sync_service import SyncService

# The /ui router drives sync triggers and provider bootstraps. It used to
# carry no authentication at all (verify_internal_token was wired only under
# /api/v1), so anyone reaching api.boskale.com could fire a sync.
ui_router = APIRouter(
    include_in_schema=False,
    dependencies=[Depends(verify_internal_token)],
)
SessionDep = Annotated[AsyncSession, Depends(get_db_session)]

DEFAULT_LIMIT = 50
MAX_LIMIT = 200
DETAIL_LIMIT = 24
MATCH_STATUS_OPTIONS = ["", "scheduled", "live", "finished", "postponed", "cancelled", "unknown"]
DEFAULT_MATCH_PROVIDER = "sportsapipro-football-v2"
MATCH_PROVIDER_OPTIONS = [
    (slug, getattr(client_cls, "display_name", slug))
    for slug, client_cls in REGISTERED_PROVIDER_CLIENTS.items()
]
SCHEDULE_MATCH_PROVIDER_OPTIONS = [
    *MATCH_PROVIDER_OPTIONS,
    (HYBRID_LINEUP_PROVIDER_SLUG, HYBRID_LINEUP_PROVIDER_NAME),
]


@ui_router.get("/", response_class=RedirectResponse)
async def root_redirect() -> RedirectResponse:
    return RedirectResponse(url="/ui", status_code=307)


@ui_router.get("/ui", response_class=HTMLResponse)
async def overview_page(
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    try:
        snapshot = await build_catalog_dashboard_snapshot(session)
    except Exception as exc:
        snapshot = _empty_snapshot()
        extra = f"Database is not ready yet: {exc}"
        message = f"{message} | {extra}" if message else extra

    metrics = [
        ("Countries", snapshot.counts.get("countries", 0), "/ui/countries"),
        ("Competitions", snapshot.counts.get("competitions", 0), "/ui/competitions"),
        ("Seasons", snapshot.counts.get("seasons", 0), "/ui/seasons"),
        ("Teams", snapshot.counts.get("teams", 0), "/ui/teams"),
        ("Futbolcular", snapshot.counts.get("players", 0), "/ui/players"),
        ("Matches", snapshot.counts.get("matches", 0), "/ui/matches"),
        ("Sync Runs", snapshot.counts.get("sync_runs", 0), "/ui/sync-runs"),
    ]
    metric_cards = "".join(
        f'<a class="metric" href="{href}"><span>{escape(label)}</span><strong>{value}</strong></a>'
        for label, value, href in metrics
    )
    sync_rows = "".join(
        f"<tr><td>{escape(item.scope)}</td><td>{escape(item.status.value)}</td>"
        f"<td>{escape(item.started_at.isoformat())}</td></tr>"
        for item in snapshot.sync_runs[:8]
    ) or '<tr><td colspan="3">Kayit yok.</td></tr>'
    match_rows = "".join(
        f"<tr><td>{escape(item.kickoff_at.isoformat())}</td>"
        f'<td>{_competition_link(getattr(item, "competition", None))}</td>'
        f"<td>{escape(item.home_team.name)} vs {escape(item.away_team.name)}</td>"
        f"<td>{_match_open_link(item)}</td></tr>"
        for item in snapshot.matches[:8]
    ) or '<tr><td colspan="4">Kayit yok.</td></tr>'
    country_links = "".join(
        f'<a class="tag" href="/ui/countries/{quote_plus(item.slug)}">{escape(item.name)}</a>'
        for item in snapshot.countries[:10]
    ) or '<span class="muted">Kayit yok.</span>'
    competition_links = "".join(
        f'<a class="tag" href="/ui/competitions/{quote_plus(item.slug)}">{escape(item.name)}</a>'
        for item in snapshot.competitions[:10]
    ) or '<span class="muted">Kayit yok.</span>'
    content = f"""
    <section class="metrics">{metric_cards}</section>
    <section class="grid">
      <article class="card">
        <h2>Quick Browse</h2>
        <p>Ulke ve competition listelerinden iliskili sayfalara gec.</p>
        <div class="stack"><div>{country_links}</div><div>{competition_links}</div></div>
      </article>
      <article class="card">
        <div class="head"><h2>Recent Sync Runs</h2><a href="/ui/sync-runs">Open</a></div>
        <table><thead><tr><th>Scope</th><th>Status</th><th>Started</th></tr></thead><tbody>{sync_rows}</tbody></table>
      </article>
      <article class="card wide">
        <div class="head"><h2>Recent Matches</h2><a href="/ui/matches">Open</a></div>
        <table><thead><tr><th>Kickoff</th><th>Competition</th><th>Fixture</th><th>Open</th></tr></thead><tbody>{match_rows}</tbody></table>
      </article>
    </section>
    """
    return HTMLResponse(_layout("Overview", "Veri icinde gezmek icin sayfa bazli explorer.", "overview", content, message))


@ui_router.get("/ui/schedule", response_class=HTMLResponse)
async def schedule_page(
    target_date: date | None = None,
    limit: int | None = None,
    tz: str | None = None,
    provider_slug: str = DEFAULT_MATCH_PROVIDER,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    if tz is None:
        selected_date = target_date or _today()
        content = _schedule_timezone_bootstrap(selected_date, limit, provider_slug)
        return HTMLResponse(
            _layout(
                "Schedule",
                "Gun bazli mac akisini tarihler arasinda gez.",
                "schedule",
                content + _schedule_provider_hint(provider_slug),
                message,
            )
        )

    normalized_timezone, message = _normalize_ui_timezone(tz, message)
    normalized_limit = _limit(limit) if limit is not None else None
    selected_date = target_date or _today()
    items = await browse_matches(
        session=session,
        target_date=selected_date,
        competition_slug=None,
        team_q=None,
        status=None,
        limit=normalized_limit,
        offset=0,
        timezone_name=normalized_timezone,
    )
    match_ids = [
        item.id
        for item in items
        if getattr(item, "id", None) is not None
    ]
    player_sync_counts = await count_provider_match_player_sync(
        session=session,
        provider_slug=provider_slug,
        match_ids=match_ids,
    )
    forward_schedule_status = await forward_schedule_sync_manager.snapshot()
    schedule_sync_status = await schedule_sync_job_manager.snapshot()
    lineup_sync_status = await match_lineup_sync_job_manager.snapshot()
    feature_pipeline_status = await feature_pipeline_job_manager.snapshot()
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Selected Date</span><strong>{escape(selected_date.isoformat())}</strong></article>'
        f'<article class="metric"><span>Timezone</span><strong>{escape(normalized_timezone)}</strong></article>'
        f'<article class="metric"><span>Matches</span><strong>{len(items)}</strong></article>'
        "</section>"
    )
    content = (
        _date_navigation(
            "/ui/schedule",
            selected_date,
            {"limit": normalized_limit, "tz": normalized_timezone, "provider_slug": provider_slug},
            extra_actions=(
                _schedule_timezone_form(
                    selected_date,
                    normalized_timezone,
                    normalized_limit,
                    provider_slug,
                )
                + _schedule_sync_form(
                    selected_date,
                    normalized_limit,
                    normalized_timezone,
                    provider_slug,
                )
                + _schedule_lineup_sync_form(
                    selected_date,
                    normalized_limit,
                    normalized_timezone,
                    provider_slug,
                )
                + _schedule_feature_pipeline_form(
                    selected_date,
                    normalized_limit,
                    normalized_timezone,
                    provider_slug,
                )
                + _schedule_forward_sync_link(provider_slug)
            ),
        )
        + metrics
        + _forward_schedule_inline_panel(forward_schedule_status)
        + _schedule_sync_status_panel(
            schedule_sync_status,
            selected_date=selected_date,
            timezone_name=normalized_timezone,
            provider_slug=provider_slug,
        )
        + _lineup_sync_status_panel(
            lineup_sync_status,
            selected_date=selected_date,
            timezone_name=normalized_timezone,
            provider_slug=provider_slug,
        )
        + _feature_pipeline_status_panel(
            feature_pipeline_status,
            selected_date=selected_date,
            timezone_name=normalized_timezone,
        )
        + _table_card(
            "Daily Schedule",
            (
                "Secili gunun maclarini ileri geri tarih oklarindan gez. "
                + "Sync Match Players secili provider icin o gunun eslenmis maclarini tarar, "
                + (
                    "Hibrit seciliyse once SportsAPI Pro, sonra gerekirse Sofascore dener. "
                    if provider_slug == HYBRID_LINEUP_PROVIDER_SLUG
                    else ""
                )
                + "lineup endpoint'ini dener, oyuncu/appearance verisini yazar ve veri yoksa "
                + "'no lineup' olarak isaretler. Feature Pipeline ise market/context/rating/snapshot "
                + "zincirini arka planda kosar. Match Players kolonu da bu sonucu gosterir."
            ),
            "",
            "<tr><th>Kickoff</th><th>Competition</th><th>Fixture</th><th>Season</th><th>Status</th><th>Score</th><th>Match Players</th><th>Open</th></tr>",
            _match_rows(
                items,
                show_competition=True,
                show_season=True,
                timezone_name=normalized_timezone,
                show_player_sync=True,
                player_sync_counts=player_sync_counts,
                player_sync_provider_slug=provider_slug,
            ),
            "",
        )
    )
    return HTMLResponse(_layout("Schedule", "Gun bazli mac akisini tarihler arasinda gez.", "schedule", content, message))


@ui_router.post("/ui/schedule/run")
async def run_schedule_sync_from_ui(
    target_date: Annotated[date, Form()],
    limit: Annotated[int | None, Form()] = None,
    tz: Annotated[str, Form()] = DEFAULT_TIMEZONE,
    provider_slug: Annotated[str, Form()] = DEFAULT_MATCH_PROVIDER,
    session: SessionDep = None,
) -> RedirectResponse:
    normalized_timezone, _ = _normalize_ui_timezone(tz, None)
    normalized_limit = _limit(limit) if limit is not None else None
    status = await schedule_sync_job_manager.start(
        provider_slug=provider_slug,
        target_date=target_date,
        timezone_name=normalized_timezone,
    )
    params = {
        "target_date": target_date.isoformat(),
        "limit": normalized_limit,
        "tz": normalized_timezone,
        "provider_slug": provider_slug,
        "message": status.last_message or "Schedule sync started.",
    }
    return RedirectResponse(
        url=f"/ui/schedule?{_query(params)}",
        status_code=303,
    )


@ui_router.post("/ui/schedule/players/run")
async def run_schedule_lineup_sync_from_ui(
    target_date: Annotated[date, Form()],
    limit: Annotated[int | None, Form()] = None,
    tz: Annotated[str, Form()] = DEFAULT_TIMEZONE,
    provider_slug: Annotated[str, Form()] = DEFAULT_MATCH_PROVIDER,
) -> RedirectResponse:
    normalized_timezone, _ = _normalize_ui_timezone(tz, None)
    normalized_limit = _limit(limit) if limit is not None else None
    status = await match_lineup_sync_job_manager.start(
        provider_slug=provider_slug,
        target_date=target_date,
        timezone_name=normalized_timezone,
    )
    params = {
        "target_date": target_date.isoformat(),
        "limit": normalized_limit,
        "tz": normalized_timezone,
        "provider_slug": provider_slug,
        "message": (
            status.last_message
            or "Match player sync started. Open the status panel for live progress."
        ),
    }
    return RedirectResponse(
        url=f"/ui/schedule?{_query(params)}",
        status_code=303,
    )


@ui_router.post("/ui/schedule/features/run")
async def run_feature_pipeline_from_ui(
    target_date: Annotated[date, Form()],
    limit: Annotated[int | None, Form()] = None,
    tz: Annotated[str, Form()] = DEFAULT_TIMEZONE,
    provider_slug: Annotated[str, Form()] = DEFAULT_MATCH_PROVIDER,
) -> RedirectResponse:
    normalized_timezone, _ = _normalize_ui_timezone(tz, None)
    normalized_limit = _limit(limit) if limit is not None else None
    status = await feature_pipeline_job_manager.start(
        provider_slug=FEATURE_PIPELINE_PROVIDER,
        target_date=target_date,
        timezone_name=normalized_timezone,
    )
    params = {
        "target_date": target_date.isoformat(),
        "limit": normalized_limit,
        "tz": normalized_timezone,
        "provider_slug": provider_slug,
        "message": status.last_message or "Feature pipeline started.",
    }
    return RedirectResponse(url=f"/ui/schedule?{_query(params)}", status_code=303)


@ui_router.get("/ui/schedule/forward-sync", response_class=HTMLResponse)
async def forward_schedule_sync_page(
    provider_slug: str = DEFAULT_MATCH_PROVIDER,
    message: str | None = None,
) -> HTMLResponse:
    status = await forward_schedule_sync_manager.snapshot()
    if not status.running:
        status = replace(status, provider_slug=provider_slug)
    content = _forward_schedule_sync_panel(status)
    return HTMLResponse(
        _layout(
            "Schedule Runner",
            "Secilen tarihten ileri veya geri schedule sync kosusu baslat.",
            "schedule-runner",
            content,
            message,
        )
    )


@ui_router.post("/ui/schedule/forward-sync/start")
async def start_forward_schedule_sync(
    start_date: Annotated[date, Form()],
    provider_slug: Annotated[str, Form()] = DEFAULT_MATCH_PROVIDER,
    direction: Annotated[str, Form()] = "forward",
    max_days: Annotated[int | None, Form()] = 365,
) -> RedirectResponse:
    status = await forward_schedule_sync_manager.start_with_options(
        provider_slug=provider_slug,
        start_date=start_date,
        direction=direction,
        max_days=max_days,
    )
    message = status.last_message or "Schedule runner started."
    return RedirectResponse(
        url=f'/ui/schedule/forward-sync?{_query({"message": message})}',
        status_code=303,
    )


@ui_router.post("/ui/schedule/forward-sync/stop")
async def stop_forward_schedule_sync() -> RedirectResponse:
    status = await forward_schedule_sync_manager.stop()
    message = status.last_message or "Schedule runner stop requested."
    return RedirectResponse(
        url=f'/ui/schedule/forward-sync?{_query({"message": message})}',
        status_code=303,
    )


@ui_router.get("/ui/countries", response_class=HTMLResponse)
async def countries_page(
    q: str | None = None,
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    limit = _limit(limit)
    offset = _offset(offset)
    items = await list_countries(session=session, q=q, limit=limit, offset=offset)
    rows = "".join(
        f'<tr><td><a href="/ui/countries/{quote_plus(item.slug)}">{escape(item.name)}</a></td>'
        f"<td>{escape(item.slug)}</td><td>{escape(item.iso_code2 or '-')}</td>"
        f'<td><a href="/ui/competitions?country_slug={quote_plus(item.slug)}">Competitions</a></td></tr>'
        for item in items
    ) or '<tr><td colspan="4">Sonuc yok.</td></tr>'
    controls = _filters(
        "/ui/countries",
        [_text("q", q, "Country or slug"), _number("limit", limit)],
    )
    content = _table_card(
        "Countries",
        "Ulke listesinden competition katmanina gec.",
        controls,
        "<tr><th>Name</th><th>Slug</th><th>Code</th><th>Browse</th></tr>",
        rows,
        _pager("/ui/countries", {"q": q, "limit": limit}, offset, limit, len(items) == limit),
    )
    return HTMLResponse(_layout("Countries", "Ulke kayitlarini ara ve ilgili competition listesine git.", "countries", content, message))


@ui_router.get("/ui/countries/{country_slug}", response_class=HTMLResponse)
async def country_detail_page(
    country_slug: str,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    country = await get_country_by_slug(session, country_slug)
    if country is None:
        raise HTTPException(status_code=404, detail="Country not found.")

    competitions = await list_competitions_for_country(session, country.slug, limit=DETAIL_LIMIT)
    matches = await list_matches_for_country(session, country.slug, limit=DETAIL_LIMIT)
    competition_rows = "".join(
        f'<tr><td><a href="/ui/competitions/{quote_plus(item.slug)}">{escape(item.name)}</a></td>'
        f"<td>{escape(item.competition_type.value)}</td>"
        f'<td><a href="/ui/seasons?competition_slug={quote_plus(item.slug)}">Seasons</a></td>'
        f'<td><a href="/ui/matches?competition_slug={quote_plus(item.slug)}">Matches</a></td></tr>'
        for item in competitions
    ) or '<tr><td colspan="4">Kayit yok.</td></tr>'
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Country</span><strong>{escape(country.name)}</strong></article>'
        f'<article class="metric"><span>Slug</span><strong>{escape(country.slug)}</strong></article>'
        f'<article class="metric"><span>Competitions</span><strong>{len(competitions)}</strong></article>'
        f'<article class="metric"><span>Recent Matches</span><strong>{len(matches)}</strong></article>'
        "</section>"
    )
    content = (
        metrics
        + _table_card(
            "Competitions",
            "Bu ulkeye bagli competition kayitlari.",
            "",
            "<tr><th>Name</th><th>Type</th><th>Seasons</th><th>Matches</th></tr>",
            competition_rows,
            "",
        )
        + _table_card(
            "Recent Matches",
            "Ulkeye bagli competition'lardan son maclar.",
            "",
            "<tr><th>Kickoff</th><th>Competition</th><th>Fixture</th><th>Status</th><th>Score</th><th>Open</th></tr>",
            _match_rows(matches, show_competition=True, show_season=False),
            "",
        )
    )
    return HTMLResponse(_layout(country.name, "Ulke bazinda competition ve match kayitlarini ac.", "countries", content, message))


@ui_router.get("/ui/competitions", response_class=HTMLResponse)
async def competitions_page(
    q: str | None = None,
    country_slug: str | None = None,
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    limit = _limit(limit)
    offset = _offset(offset)
    items = await list_competitions(
        session=session,
        q=q,
        country_slug=country_slug,
        limit=limit,
        offset=offset,
    )
    rows = "".join(
        f'<tr><td><a href="/ui/competitions/{quote_plus(item.slug)}">{escape(item.name)}</a></td>'
        f"<td>{escape(item.country.name if item.country else '-')}</td>"
        f"<td>{escape(item.slug)}</td><td>{escape(item.competition_type.value)}</td>"
        f'<td><a href="/ui/seasons?competition_slug={quote_plus(item.slug)}">Seasons</a> '
        f'<a href="/ui/matches?competition_slug={quote_plus(item.slug)}">Matches</a></td></tr>'
        for item in items
    ) or '<tr><td colspan="5">Sonuc yok.</td></tr>'
    controls = _filters(
        "/ui/competitions",
        [
            _text("q", q, "Competition or slug"),
            _text("country_slug", country_slug, "Country slug"),
            _number("limit", limit),
        ],
    )
    content = _table_card(
        "Competitions",
        "Ulkeye gore filtrele, sonra sezon ve maclara gec.",
        controls,
        "<tr><th>Name</th><th>Country</th><th>Slug</th><th>Type</th><th>Browse</th></tr>",
        rows,
        _pager(
            "/ui/competitions",
            {"q": q, "country_slug": country_slug, "limit": limit},
            offset,
            limit,
            len(items) == limit,
        ),
    )
    return HTMLResponse(_layout("Competitions", "Competition katalogunda ulke ve isim bazli gez.", "competitions", content, message))


@ui_router.get("/ui/competitions/{competition_slug}", response_class=HTMLResponse)
async def competition_detail_page(
    competition_slug: str,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    competition = await get_competition_by_slug(session, competition_slug)
    if competition is None:
        raise HTTPException(status_code=404, detail="Competition not found.")

    seasons = await list_seasons(
        session=session,
        competition_slug=competition.slug,
        current_only=False,
        limit=DETAIL_LIMIT,
        offset=0,
    )
    matches = await list_matches_for_competition(session, competition.slug, limit=DETAIL_LIMIT)
    season_rows = "".join(
        f'<tr><td><a href="/ui/seasons/{quote_plus(item.entity_uid)}">{escape(item.label)}</a></td>'
        f"<td>{escape(str(item.start_date or '-'))}</td>"
        f"<td>{escape(str(item.end_date or '-'))}</td>"
        f"<td>{'yes' if item.is_current else 'no'}</td></tr>"
        for item in seasons
    ) or '<tr><td colspan="4">Kayit yok.</td></tr>'
    country_name = competition.country.name if competition.country else "-"
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Competition</span><strong>{escape(competition.name)}</strong></article>'
        f'<article class="metric"><span>Country</span><strong>{escape(country_name)}</strong></article>'
        f'<article class="metric"><span>Seasons</span><strong>{len(seasons)}</strong></article>'
        f'<article class="metric"><span>Recent Matches</span><strong>{len(matches)}</strong></article>'
        "</section>"
    )
    content = (
        metrics
        + _table_card(
            "Seasons",
            "Bu competition'e bagli sezon kayitlari.",
            "",
            "<tr><th>Label</th><th>Start</th><th>End</th><th>Current</th></tr>",
            season_rows,
            "",
        )
        + _table_card(
            "Recent Matches",
            "Competition altindaki son maclar.",
            "",
            "<tr><th>Kickoff</th><th>Fixture</th><th>Season</th><th>Status</th><th>Score</th><th>Open</th></tr>",
            _match_rows(matches, show_competition=False, show_season=True),
            "",
        )
    )
    return HTMLResponse(_layout(competition.name, "Competition detayinda sezon ve mac kayitlarini ac.", "competitions", content, message))


@ui_router.get("/ui/seasons", response_class=HTMLResponse)
async def seasons_page(
    competition_slug: str | None = None,
    current_only: bool = False,
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    limit = _limit(limit)
    offset = _offset(offset)
    items = await list_seasons(
        session=session,
        competition_slug=competition_slug,
        current_only=current_only,
        limit=limit,
        offset=offset,
    )
    rows = "".join(
        f'<tr><td><a href="/ui/seasons/{quote_plus(item.entity_uid)}">{escape(item.label)}</a></td>'
        f"<td>{'yes' if item.is_current else 'no'}</td>"
        f"<td>{escape(item.entity_uid)}</td></tr>"
        for item in items
    ) or '<tr><td colspan="3">Sonuc yok.</td></tr>'
    controls = _filters(
        "/ui/seasons",
        [
            _text("competition_slug", competition_slug, "Competition slug"),
            _checkbox("current_only", current_only, "Current only"),
            _number("limit", limit),
        ],
    )
    content = _table_card(
        "Seasons",
        "Competition baglaminda sezonlari gor.",
        controls,
        "<tr><th>Label</th><th>Current</th><th>Entity UID</th></tr>",
        rows,
        _pager(
            "/ui/seasons",
            {"competition_slug": competition_slug, "current_only": "true" if current_only else None, "limit": limit},
            offset,
            limit,
            len(items) == limit,
        ),
    )
    return HTMLResponse(_layout("Seasons", "Competition slug ile sezon akisini filtrele.", "seasons", content, message))


@ui_router.get("/ui/seasons/{entity_uid}", response_class=HTMLResponse)
async def season_detail_page(
    entity_uid: str,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    season = await get_season_by_entity_uid(session, entity_uid)
    if season is None:
        raise HTTPException(status_code=404, detail="Season not found.")

    competitions = await list_competitions_for_season(session, season.entity_uid, limit=DETAIL_LIMIT)
    matches = await list_matches_for_season(session, season.entity_uid, limit=DETAIL_LIMIT)
    competition_rows = "".join(
        f'<tr><td><a href="/ui/competitions/{quote_plus(item.slug)}">{escape(item.name)}</a></td>'
        f"<td>{escape(item.country.name if item.country else '-')}</td>"
        f"<td>{escape(item.competition_type.value)}</td></tr>"
        for item in competitions
    ) or '<tr><td colspan="3">Kayit yok.</td></tr>'
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Season</span><strong>{escape(season.label)}</strong></article>'
        f'<article class="metric"><span>Current</span><strong>{"yes" if season.is_current else "no"}</strong></article>'
        f'<article class="metric"><span>Competitions</span><strong>{len(competitions)}</strong></article>'
        f'<article class="metric"><span>Recent Matches</span><strong>{len(matches)}</strong></article>'
        "</section>"
    )
    content = (
        metrics
        + _table_card(
            "Competitions",
            "Bu sezon ile iliskili competition kayitlari.",
            "",
            "<tr><th>Name</th><th>Country</th><th>Type</th></tr>",
            competition_rows,
            "",
        )
        + _table_card(
            "Recent Matches",
            "Bu sezon icin bulunan son maclar.",
            "",
            "<tr><th>Kickoff</th><th>Competition</th><th>Fixture</th><th>Status</th><th>Score</th><th>Open</th></tr>",
            _match_rows(matches, show_competition=True, show_season=False),
            "",
        )
    )
    return HTMLResponse(_layout(season.label, "Season detayinda competition ve mac iliskilerini ac.", "seasons", content, message))


@ui_router.get("/ui/teams", response_class=HTMLResponse)
async def teams_page(
    q: str | None = None,
    country_slug: str | None = None,
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    limit = _limit(limit)
    offset = _offset(offset)
    items = await list_teams(
        session=session,
        q=q,
        country_slug=country_slug,
        limit=limit,
        offset=offset,
    )
    rows = "".join(
        f'<tr><td><a href="/ui/teams/{quote_plus(item.slug)}">{escape(item.name)}</a></td>'
        f"<td>{escape(item.short_name or '-')}</td>"
        f"<td>{escape(item.country.name if item.country else '-')}</td>"
        f"<td>{escape(item.slug)}</td></tr>"
        for item in items
    ) or '<tr><td colspan="4">Sonuc yok.</td></tr>'
    controls = _filters(
        "/ui/teams",
        [
            _text("q", q, "Team or slug"),
            _text("country_slug", country_slug, "Country slug"),
            _number("limit", limit),
        ],
    )
    content = _table_card(
        "Teams",
        "Takim secip detay ve son maclara gec.",
        controls,
        "<tr><th>Name</th><th>Short</th><th>Country</th><th>Slug</th></tr>",
        rows,
        _pager(
            "/ui/teams",
            {"q": q, "country_slug": country_slug, "limit": limit},
            offset,
            limit,
            len(items) == limit,
        ),
    )
    return HTMLResponse(_layout("Teams", "Takim verisi icinde ulke ve isim bazli gez.", "teams", content, message))


@ui_router.get("/ui/teams/{team_slug}", response_class=HTMLResponse)
async def team_detail_page(
    team_slug: str,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    team = await get_team_by_slug(session, team_slug)
    if team is None:
        raise HTTPException(status_code=404, detail="Team not found.")

    matches = await list_matches_for_team(session, team.id, limit=DETAIL_LIMIT)
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Team</span><strong>{escape(team.name)}</strong></article>'
        f'<article class="metric"><span>Country</span><strong>{escape(team.country.name if team.country else "-")}</strong></article>'
        f'<article class="metric"><span>Short</span><strong>{escape(team.short_name or "-")}</strong></article>'
        f'<article class="metric"><span>Recent Matches</span><strong>{len(matches)}</strong></article>'
        "</section>"
    )
    content = metrics + _table_card(
        "Recent Matches",
        "Bu takim icin bulunan son maclar.",
        "",
        "<tr><th>Kickoff</th><th>Competition</th><th>Fixture</th><th>Season</th><th>Status</th><th>Score</th><th>Open</th></tr>",
        _match_rows(matches, show_competition=True, show_season=True),
        "",
    )
    return HTMLResponse(_layout(team.name, "Takim detayindan match ve country baglamina git.", "teams", content, message))


@ui_router.get("/ui/players", response_class=HTMLResponse)
async def players_page(
    q: str | None = None,
    country_slug: str | None = None,
    provider_slug: str = "sofascore-football",
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    limit = _limit(limit)
    offset = _offset(offset)
    mapped_teams_count = await count_provider_team_mappings(
        session=session,
        provider_slug=provider_slug,
    )
    recent_sync_runs = await list_sync_runs(
        session=session,
        scope="players",
        provider_slug=provider_slug,
        limit=5,
        offset=0,
    )
    items = await list_players(
        session=session,
        q=q,
        country_slug=country_slug,
        limit=limit,
        offset=offset,
    )
    rows = "".join(
        f"<tr><td>{escape(item.full_name)}</td>"
        f"<td>{escape(item.short_name or '-')}</td>"
        f"<td>{escape(item.country.name if item.country else '-')}</td>"
        f"<td>{escape(item.slug)}</td></tr>"
        for item in items
    ) or '<tr><td colspan="4">Sonuc yok.</td></tr>'
    controls = _filters(
        "/ui/players",
        [
            _text("q", q, "Player or slug"),
            _text("country_slug", country_slug, "Country slug"),
            _number("limit", limit),
        ],
    )
    sync_form = (
        '<form class="filters" method="get" action="/ui/players/run">'
        f'<label class="field"><span>provider</span><select name="provider_slug">{_provider_option_tags(provider_slug)}</select></label>'
        '<button class="btn" type="submit">Sync Players</button>'
        "</form>"
    )
    content = _table_card(
        "Player Sync Durumu",
        "Provider dashboard'daki basarili API cagrilari sadece roster endpoint'ine ulasildigini gosterir; bu sayfa yalnizca DB'ye yazilan oyunculari listeler.",
        "",
        "<tr><th>Field</th><th>Value</th></tr>",
        _player_sync_rows(
            provider_slug=provider_slug,
            mapped_teams_count=mapped_teams_count,
            items=items,
            q=q,
            country_slug=country_slug,
            sync_runs=recent_sync_runs,
        ),
        "",
    ) + _table_card(
        "Futbolcular",
        "Database icindeki oyuncu kayitlarini listele.",
        sync_form + controls,
        "<tr><th>Ad Soyad</th><th>Kisa Ad</th><th>Ulke</th><th>Slug</th></tr>",
        rows,
        _pager(
            "/ui/players",
            {
                "q": q,
                "country_slug": country_slug,
                "provider_slug": provider_slug,
                "limit": limit,
            },
            offset,
            limit,
            len(items) == limit,
        ),
    )
    return HTMLResponse(
        _layout(
            "Futbolcular",
            "Oyuncu verisi icinde isim ve ulke bazli gez.",
            "players",
            content,
            message,
        )
    )


@ui_router.get("/ui/players/run")
async def run_player_sync_from_ui(
    provider_slug: str = "sofascore-football",
    session: SessionDep = None,
) -> RedirectResponse:
    return await _run_sync_stage(
        session=session,
        provider_slug=provider_slug,
        scope="players",
        redirect_path="/ui/players",
        redirect_params={"provider_slug": provider_slug},
    )


@ui_router.get("/ui/matches", response_class=HTMLResponse)
async def matches_page(
    target_date: date | None = None,
    competition_slug: str | None = None,
    team_q: str | None = None,
    status: str | None = None,
    tz: str = DEFAULT_TIMEZONE,
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    normalized_timezone, message = _normalize_ui_timezone(tz, message)
    limit = _limit(limit)
    offset = _offset(offset)
    items = await browse_matches(
        session=session,
        target_date=target_date,
        competition_slug=competition_slug,
        team_q=team_q,
        status=status,
        limit=limit,
        offset=offset,
        timezone_name=normalized_timezone,
    )
    controls = _filters(
        "/ui/matches",
        [
            _date("target_date", target_date),
            _text("competition_slug", competition_slug, "Competition slug"),
            _text("team_q", team_q, "Team"),
            _select("status", status, MATCH_STATUS_OPTIONS),
            _text("tz", normalized_timezone, "IANA timezone"),
            _number("limit", limit),
        ],
    )
    content = _table_card(
        "Matches",
        "Tarih, competition, takim ve status ile filtrele.",
        controls,
        "<tr><th>Kickoff</th><th>Competition</th><th>Fixture</th><th>Season</th><th>Status</th><th>Score</th><th>Open</th></tr>",
        _match_rows(
            items,
            show_competition=True,
            show_season=True,
            timezone_name=normalized_timezone,
        ),
        _pager(
            "/ui/matches",
            {
                "target_date": target_date.isoformat() if target_date else None,
                "competition_slug": competition_slug,
                "team_q": team_q,
                "status": status,
                "tz": normalized_timezone,
                "limit": limit,
            },
            offset,
            limit,
            len(items) == limit,
        ),
    )
    return HTMLResponse(_layout("Matches", "Mac verisi icinde tarih ve iliski bazli gez.", "matches", content, message))


@ui_router.get("/ui/matches/run")
async def run_match_sync_from_ui(
    target_date: date | None = None,
    provider_slug: str = DEFAULT_MATCH_PROVIDER,
    session: SessionDep = None,
) -> RedirectResponse:
    return await _run_sync_stage(
        session=session,
        provider_slug=provider_slug,
        scope="matches",
        target_date=target_date,
    )


@ui_router.get("/ui/matches/{match_id}", response_class=HTMLResponse)
async def match_detail_page(
    match_id: UUID,
    tz: str = DEFAULT_TIMEZONE,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    normalized_timezone, message = _normalize_ui_timezone(tz, message)
    match = await get_match_by_id(session, match_id)
    if match is None:
        raise HTTPException(status_code=404, detail="Match not found.")
    latest_snapshot = await MatchFeatureSnapshotService(session).latest_snapshot(match_id=match_id)

    fixture = f"{match.home_team.name} vs {match.away_team.name}"
    participant_rows = (
        f'<tr><td>Home</td><td><a href="/ui/teams/{quote_plus(match.home_team.slug)}">{escape(match.home_team.name)}</a></td>'
        f"<td>{escape(match.home_team.country.name if match.home_team.country else '-')}</td></tr>"
        f'<tr><td>Away</td><td><a href="/ui/teams/{quote_plus(match.away_team.slug)}">{escape(match.away_team.name)}</a></td>'
        f"<td>{escape(match.away_team.country.name if match.away_team.country else '-')}</td></tr>"
    )
    info_rows = (
        f"<tr><td>Kickoff</td><td>{escape(_format_datetime(match.kickoff_at, normalized_timezone))}</td></tr>"
        f"<tr><td>Timezone</td><td>{escape(normalized_timezone)}</td></tr>"
        f"<tr><td>Competition</td><td>{_competition_link(match.competition)}</td></tr>"
        f"<tr><td>Season</td><td>{_season_link(match.season)}</td></tr>"
        f"<tr><td>Status</td><td>{escape(match.status.value)}</td></tr>"
        f"<tr><td>Score</td><td>{escape(_score(match))}</td></tr>"
        f"<tr><td>Venue</td><td>{escape(match.venue_name or '-')}</td></tr>"
        f"<tr><td>Provider Status</td><td>{escape(match.provider_status or '-')}</td></tr>"
        f"<tr><td>Entity UID</td><td>{escape(match.entity_uid)}</td></tr>"
        f"<tr><td>Last Synced</td><td>{escape(str(match.provider_last_synced_at or '-'))}</td></tr>"
    )
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Competition</span><strong>{escape(match.competition.name if match.competition else "-")}</strong></article>'
        f'<article class="metric"><span>Season</span><strong>{escape(match.season.label if match.season else "-")}</strong></article>'
        f'<article class="metric"><span>Status</span><strong>{escape(match.status.value)}</strong></article>'
        f'<article class="metric"><span>Score</span><strong>{escape(_score(match))}</strong></article>'
        "</section>"
    )
    content = (
        metrics
        + _table_card(
            fixture,
            "Mac detay kaydi.",
            "",
            "<tr><th>Field</th><th>Value</th></tr>",
            info_rows,
            "",
        )
        + _table_card(
            "Participants",
            "Bu fixture icindeki takimlar.",
            "",
            "<tr><th>Role</th><th>Team</th><th>Country</th></tr>",
            participant_rows,
            "",
        )
        + _match_feature_snapshot_panel(latest_snapshot, match_id)
    )
    return HTMLResponse(_layout(fixture, "Mac detayindan takim, competition ve sezon kayitlarina gec.", "matches", content, message))


@ui_router.get("/ui/sync-runs", response_class=HTMLResponse)
async def sync_runs_page(
    scope: str | None = None,
    provider_slug: str | None = None,
    limit: int = DEFAULT_LIMIT,
    offset: int = 0,
    message: str | None = None,
    session: SessionDep = None,
) -> HTMLResponse:
    limit = _limit(limit)
    offset = _offset(offset)
    items = await list_sync_runs(
        session=session,
        scope=scope,
        provider_slug=provider_slug,
        limit=limit,
        offset=offset,
    )
    rows = "".join(
        f"<tr><td>{escape(item.started_at.isoformat())}</td><td>{escape(item.scope)}</td>"
        f"<td>{escape(item.status.value)}</td><td>{escape(item.provider.slug)}</td>"
        f"<td>{escape(str(item.target_date or '-'))}</td><td><code>{escape(str(item.stats))}</code></td></tr>"
        for item in items
    ) or '<tr><td colspan="6">Sonuc yok.</td></tr>'
    controls = _filters(
        "/ui/sync-runs",
        [_text("scope", scope, "Scope"), _text("provider_slug", provider_slug, "Provider slug"), _number("limit", limit)],
    )
    content = _table_card(
        "Sync Runs",
        "Hangi import ne zaman ne yazmis, buradan izle.",
        controls,
        "<tr><th>Started</th><th>Scope</th><th>Status</th><th>Provider</th><th>Date</th><th>Stats</th></tr>",
        rows,
        _pager(
            "/ui/sync-runs",
            {"scope": scope, "provider_slug": provider_slug, "limit": limit},
            offset,
            limit,
            len(items) == limit,
        ),
    )
    return HTMLResponse(_layout("Sync Runs", "Import gecmisini filtrele ve istatistiklerini incele.", "sync-runs", content, message))


async def _run_sync_stage(
    *,
    session: AsyncSession,
    provider_slug: str = DEFAULT_MATCH_PROVIDER,
    scope: str,
    target_date: date | None = None,
    timezone_name: str | None = None,
    tournament_id: str | None = None,
    category_id: str | None = None,
    redirect_path: str = "/ui",
    redirect_params: dict[str, object | None] | None = None,
) -> RedirectResponse:
    service = SyncService(session)
    try:
        result = await service.trigger_provider_sync(
            provider_slug=provider_slug,
            scope=scope,
            target_date=target_date,
            timezone_name=timezone_name,
            category_id=category_id,
            tournament_id=tournament_id,
        )
        message = result.message
        if result.stats:
            message = f"{message} " + ", ".join(f"{k}={v}" for k, v in result.stats.items())
    except Exception as exc:
        message = f"Sync failed before persistence completed: {exc}"
    params = dict(redirect_params or {})
    params["message"] = message
    return RedirectResponse(url=f"{redirect_path}?{_query(params)}", status_code=303)


@ui_router.post("/ui/bootstrap/countries/run")
async def run_country_bootstrap_from_ui(
    session: SessionDep = None,
) -> RedirectResponse:
    return await _run_sync_stage(session=session, scope="bootstrap-countries")


@ui_router.post("/ui/bootstrap/tournaments/run")
async def run_tournament_bootstrap_from_ui(
    session: SessionDep = None,
) -> RedirectResponse:
    return await _run_sync_stage(session=session, scope="bootstrap-tournaments")


@ui_router.get("/ui/bootstrap/seasons/run")
async def run_season_bootstrap_from_ui(
    tournament_id: str,
    session: SessionDep = None,
) -> RedirectResponse:
    return await _run_sync_stage(session=session, scope="bootstrap-seasons", tournament_id=tournament_id.strip())


def _empty_snapshot() -> CatalogDashboardSnapshot:
    return CatalogDashboardSnapshot(
        counts={
            "providers": 0,
            "countries": 0,
            "competitions": 0,
            "seasons": 0,
            "competition_seasons": 0,
            "teams": 0,
            "players": 0,
            "matches": 0,
            "mappings": 0,
            "raw_payloads": 0,
            "sync_runs": 0,
        },
        providers=[],
        sync_runs=[],
        countries=[],
        competitions=[],
        seasons=[],
        competition_seasons=[],
        matches=[],
    )


def _layout(title: str, subtitle: str, active: str, content: str, message: str | None) -> str:
    note = f'<div class="notice">{escape(message)}</div>' if message else ""
    return f"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Sports API Explorer</title>
        <style>
          :root {{ --bg:#eef3ec; --card:#fbfcf8; --line:#d6dfd0; --ink:#142015; --muted:#5f6d60; --accent:#0f7b46; }}
          * {{ box-sizing:border-box; }} body {{ margin:0; font-family:"Segoe UI",sans-serif; color:var(--ink); background:linear-gradient(180deg,#f6f8f1,#ecf1ea); }}
          a {{ color:var(--accent); text-decoration:none; }} .app {{ min-height:100vh; display:grid; grid-template-columns:280px 1fr; }}
          .side {{ border-right:1px solid var(--line); padding:26px 20px; background:rgba(251,252,248,.86); }}
          .brand small,.field span,.muted,th {{ color:var(--muted); text-transform:uppercase; letter-spacing:.08em; font-size:11px; }}
          .brand h1 {{ margin:8px 0 0; font-size:28px; }} .nav {{ display:grid; gap:8px; margin:24px 0; }}
          .nav a {{ padding:12px 14px; border-radius:14px; color:var(--muted); }} .nav a.active {{ background:#e0f0da; color:var(--ink); font-weight:700; }}
          .box,.card,.metric,.date-nav {{ background:var(--card); border:1px solid var(--line); border-radius:18px; box-shadow:0 12px 28px rgba(20,32,21,.04); }}
          .box {{ padding:14px; margin-bottom:14px; }} .box form {{ display:grid; gap:8px; margin-bottom:10px; }}
          .box input {{ width:100%; padding:10px 12px; border:1px solid var(--line); border-radius:12px; }}
          .btn {{ border:0; border-radius:12px; background:var(--accent); color:#fff; padding:11px 14px; font-weight:700; cursor:pointer; }}
          .main {{ padding:32px; }} .head h1 {{ margin:0 0 8px; font-size:38px; }} .head p,.box p,.card p {{ margin:0 0 12px; color:var(--muted); }}
          .notice {{ margin:18px 0; background:#e4f4de; border:1px solid #bdd8b6; border-radius:14px; padding:14px 16px; color:#14482a; }}
          .metrics {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:14px; margin:20px 0; }}
          .metric {{ padding:18px; display:grid; gap:8px; color:inherit; }} .metric span {{ color:var(--muted); text-transform:uppercase; font-size:11px; }} .metric strong {{ font-size:32px; }}
          .grid {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:18px; }} .wide {{ grid-column:1/-1; }} .card {{ padding:18px; }}
          .detail-grid {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:18px; margin-top:18px; }}
          .snapshot-card {{ min-height:100%; }}
          .snapshot-metric strong {{ font-size:26px; }}
          .kv-list {{ display:grid; gap:10px; }}
          .kv-item {{ display:flex; justify-content:space-between; gap:16px; padding:10px 0; border-bottom:1px solid var(--line); }}
          .kv-item:last-child {{ border-bottom:0; padding-bottom:0; }}
          .kv-item strong {{ text-align:right; }}
          .kv-empty {{ color:var(--muted); padding:10px 0 0; }}
          .pill-row {{ display:flex; flex-wrap:wrap; gap:8px; margin:8px 0 16px; }}
          .pill {{ display:inline-flex; align-items:center; gap:6px; padding:8px 10px; border-radius:999px; border:1px solid var(--line); background:#eff5ea; color:var(--ink); font-size:12px; }}
          .pill-good {{ background:#e4f4de; border-color:#bdd8b6; color:#14482a; }}
          .pill-bad {{ background:#f7ebe2; border-color:#e3c5b1; color:#7b3b1f; }}
          .stack,.filters,.pager,.date-nav,.date-nav-actions {{ display:flex; gap:10px; flex-wrap:wrap; }} .head,.pager {{ justify-content:space-between; align-items:end; }} .tag {{ background:#eff5ea; border:1px solid var(--line); padding:8px 10px; border-radius:999px; color:var(--ink); }}
          .date-nav {{ align-items:center; justify-content:space-between; padding:18px; margin:20px 0; }}
          .date-nav-current {{ display:grid; gap:6px; text-align:center; }}
          .date-nav-current strong {{ font-size:28px; }}
          .date-nav-btn {{ padding:11px 14px; border:1px solid var(--line); border-radius:12px; background:#fff; color:var(--ink); font-weight:700; }}
          .inline-form {{ margin:0; }}
          .filters {{ margin:14px 0 16px; align-items:end; }} .field {{ display:grid; gap:6px; min-width:160px; }} .field input,.field select {{ padding:11px 12px; border:1px solid var(--line); border-radius:12px; min-height:44px; background:#fff; }}
          .check {{ display:flex; gap:8px; align-items:center; min-height:44px; color:var(--muted); }} .table-wrap {{ overflow:auto; }} table {{ width:100%; border-collapse:collapse; font-size:14px; }}
          th,td {{ text-align:left; padding:11px 8px; border-bottom:1px solid var(--line); vertical-align:top; }} .pager a {{ padding:10px 12px; border:1px solid var(--line); border-radius:12px; background:#fff; color:var(--ink); }}
          code {{ white-space:pre-wrap; font-size:12px; }} @media (max-width:1024px) {{ .app {{ grid-template-columns:1fr; }} .grid,.detail-grid {{ grid-template-columns:1fr; }} .date-nav {{ flex-direction:column; align-items:stretch; }} .date-nav-current {{ text-align:left; }} .kv-item {{ flex-direction:column; }} .kv-item strong {{ text-align:left; }} }}
        </style>
      </head>
      <body>
        <div class="app">
          <aside class="side">
            <div class="brand"><small>Sports API</small><h1>Data Explorer</h1></div>
            <nav class="nav">
              {_nav("Overview", "/ui", active == "overview")}
              {_nav("Countries", "/ui/countries", active == "countries")}
              {_nav("Competitions", "/ui/competitions", active == "competitions")}
              {_nav("Seasons", "/ui/seasons", active == "seasons")}
              {_nav("Teams", "/ui/teams", active == "teams")}
              {_nav("Futbolcular", "/ui/players", active == "players")}
              {_nav("Schedule", "/ui/schedule", active == "schedule")}
              {_nav("Schedule Runner", "/ui/schedule/forward-sync", active == "schedule-runner")}
              {_nav("Matches", "/ui/matches", active == "matches")}
              {_nav("Sync Runs", "/ui/sync-runs", active == "sync-runs")}
            </nav>
            {_sidebar_sync()}
          </aside>
          <main class="main">
            <header class="head"><small class="muted">Sports Canonical DB</small><h1>{escape(title)}</h1><p>{escape(subtitle)}</p></header>
            {note}
            {content}
          </main>
        </div>
      </body>
    </html>
    """


def _sidebar_sync() -> str:
    provider_options = _provider_option_tags(DEFAULT_MATCH_PROVIDER)
    today_value = escape(_today().isoformat())
    return f"""
    <section class="box">
      <h2>Bootstrap</h2>
      <p>Discovery adimlarini kontrollu tetikle.</p>
      <form method="post" action="/ui/bootstrap/countries/run"><button class="btn" type="submit">Load Countries</button></form>
      <form method="post" action="/ui/bootstrap/tournaments/run"><button class="btn" type="submit">Load Tournaments</button></form>
      <form method="get" action="/ui/bootstrap/seasons/run"><input name="tournament_id" placeholder="Tournament ID" /><button class="btn" type="submit">Load Seasons</button></form>
    </section>
    <section class="box">
      <h2>Match Sync</h2>
      <p>Takvim verisini canonical match tablolarina yaz.</p>
      <form method="get" action="/ui/matches/run"><input name="target_date" type="date" value="{today_value}" /><select name="provider_slug">{provider_options}</select><button class="btn" type="submit">Run Match Sync</button></form>
      <form method="get" action="/ui/schedule/forward-sync"><button class="btn" type="submit">Open Forward Sync</button></form>
    </section>
    """


def _table_card(title: str, subtitle: str, controls: str, header: str, rows: str, footer: str) -> str:
    return f'<section class="card"><h2>{escape(title)}</h2><p>{escape(subtitle)}</p>{controls}<div class="table-wrap"><table><thead>{header}</thead><tbody>{rows}</tbody></table></div>{footer}</section>'


def _match_feature_snapshot_panel(snapshot: object | None, match_id: UUID) -> str:
    latest_json_href = f"/api/v1/matches/{escape(str(match_id))}/snapshots/latest"
    all_json_href = f"/api/v1/matches/{escape(str(match_id))}/snapshots?phase=live&limit=250"
    if snapshot is None:
        return _table_card(
            "Feature Snapshot",
            "Feature pipeline bu mac icin henuz snapshot uretmemis.",
            "",
            "<tr><th>Field</th><th>Value</th></tr>",
            (
                "<tr><td>Status</td><td>Snapshot yok.</td></tr>"
                f'<tr><td>API</td><td><a href="{latest_json_href}">Latest JSON</a></td></tr>'
            ),
            "",
        )

    metric_cards = "".join(
        [
            _snapshot_metric_card("Phase", _snapshot_display(snapshot, "snapshot_phase", "enum")),
            _snapshot_metric_card("Minute", _snapshot_display(snapshot, "snapshot_minute", "int")),
            _snapshot_metric_card(
                "Trainable",
                _snapshot_json_display(snapshot, "quality_json", "trainable_snapshot", "bool"),
            ),
            _snapshot_metric_card(
                "Score Integrity",
                _snapshot_json_display(snapshot, "quality_json", "score_integrity", "text"),
            ),
            _snapshot_metric_card(
                "Score State",
                _snapshot_display(snapshot, "score_state_class", "text"),
            ),
            _snapshot_metric_card(
                "Market State",
                _snapshot_display(snapshot, "market_state_class", "text"),
            ),
            _snapshot_metric_card(
                "Model Home Prob",
                _snapshot_display(snapshot, "state_model_home_prob", "pct1"),
            ),
            _snapshot_metric_card("Cluster", _snapshot_display(snapshot, "state_cluster_id", "int")),
        ]
    )
    availability_pills = _snapshot_pills("Availability", getattr(snapshot, "availability_json", None))
    quality_pills = _snapshot_pills("Quality", getattr(snapshot, "quality_json", None))
    source_pills = _snapshot_pills("Source", getattr(snapshot, "source_json", None))

    cards = "".join(
        [
            _snapshot_data_card(
                "Snapshot Status",
                "Bu snapshot hangi anda alindi ve pipeline nasil degerlendirdi.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Snapshot Time", "snapshot_ts", "datetime"),
                        ("Finalized", "is_finalized", "bool"),
                        ("Expected Goal Line", "pre_expected_goal_line", "float1"),
                        ("Expected Goal Proxy", "expected_goal_line_proxy", "bool"),
                        ("Predicted Lineup Low History", "predicted_lineup_low_history", "bool"),
                        ("Betfair Available", "betfair_unavailable", "negated_bool"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Pre-Match Context",
                "Match basindaki piyasa beklentisi ve takim edge'i.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Home Win Prob", "pre_home_prob", "pct1"),
                        ("Draw Prob", "pre_draw_prob", "pct1"),
                        ("Away Win Prob", "pre_away_prob", "pct1"),
                        ("Favorite Gap", "pre_favorite_gap", "pct1"),
                        ("Team Strength Diff", "team_strength_diff", "signed2"),
                        ("Elo Diff", "elo_diff", "signed1"),
                        ("Form Points Diff", "form_points_diff", "signed1"),
                        ("xG Form Diff", "xg_form_diff", "signed2"),
                        ("xGA Form Diff", "xga_form_diff", "signed2"),
                        ("Rest Days Diff", "rest_days_diff", "signed1"),
                        ("Fatigue Diff", "fatigue_diff", "signed1"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Lineup Edge",
                "Tahmini ve gercek kadrolar arasindaki kalite farki. Pozitif degerler home edge demek.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Pred Lineup Strength Diff", "pred_lineup_strength_diff", "signed2"),
                        ("Real Lineup Strength Diff", "real_lineup_strength_diff", "signed2"),
                        ("Home Defense Strength", "home_defense_strength", "float1"),
                        ("Away Defense Strength", "away_defense_strength", "float1"),
                        ("Midfield Strength Diff", "midfield_strength_diff", "signed2"),
                        ("Attack Strength Diff", "attack_strength_diff", "signed2"),
                        ("Lineup Surprise Score", "lineup_surprise_score", "float2"),
                        ("Rotation Diff", "rotation_diff", "signed1"),
                        ("Missing Strength Diff", "missing_strength_diff", "signed2"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Match State",
                "Skor, kart ve zaman baglami.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Home Score", "home_score", "int"),
                        ("Away Score", "away_score", "int"),
                        ("Score Diff", "score_diff", "signed1"),
                        ("Goal Total", "goal_total", "int"),
                        ("Minute Norm", "minute_norm", "pct1"),
                        ("Time Remaining", "time_remaining_norm", "pct1"),
                        ("Home Red Cards", "home_red_cards", "int"),
                        ("Away Red Cards", "away_red_cards", "int"),
                        ("Red Card Diff", "red_card_diff", "signed1"),
                        ("Yellow Card Diff", "yellow_card_diff", "signed1"),
                        ("Subs Diff", "subs_diff", "signed1"),
                        ("Since Last Goal", "time_since_last_goal", "minutes"),
                        ("Since Last Red Card", "time_since_last_red_card", "minutes"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Flow",
                "Macin toplam akisi ve son bolum baskisi.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("xG Diff Total", "xg_diff_total", "signed2"),
                        ("Shots Diff Total", "shots_diff_total", "signed1"),
                        ("SOT Diff Total", "sot_diff_total", "signed1"),
                        ("Corners Diff Total", "corners_diff_total", "signed1"),
                        ("Possession Diff", "possession_diff", "signed1"),
                        ("xG Diff Last 5", "xg_diff_last5", "signed2"),
                        ("xG Diff Last 10", "xg_diff_last10", "signed2"),
                        ("Shots Diff Last 5", "shots_diff_last5", "signed1"),
                        ("Shots Diff Last 10", "shots_diff_last10", "signed1"),
                        ("SOT Diff Last 10", "sot_diff_last10", "signed1"),
                        ("Dangerous Attacks Last 10", "dangerous_attacks_diff_last10", "signed1"),
                        ("Box Entries Last 10", "box_entries_diff_last10", "signed1"),
                        ("Pressure Diff Last 10", "pressure_diff_last10", "signed2"),
                        ("Momentum Diff", "momentum_diff", "signed2"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Live Market",
                "Canli oranlar varsa marketin o andaki fikri.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Live Home Prob", "live_home_prob", "pct1"),
                        ("Live Draw Prob", "live_draw_prob", "pct1"),
                        ("Live Away Prob", "live_away_prob", "pct1"),
                        ("Live Over 2.5", "live_over25_prob", "pct1"),
                        ("Live Under 2.5", "live_under25_prob", "pct1"),
                        ("Next Goal Home", "live_next_goal_home_prob", "pct1"),
                        ("Home Shift From Pre", "home_prob_shift_from_pre", "signed_pct1"),
                        ("Draw Shift From Pre", "draw_prob_shift_from_pre", "signed_pct1"),
                        ("Away Shift From Pre", "away_prob_shift_from_pre", "signed_pct1"),
                        ("Home Change Last 1m", "home_prob_change_last1", "signed_pct1"),
                        ("Home Change Last 5m", "home_prob_change_last5", "signed_pct1"),
                        ("Market Volatility Last 5", "market_volatility_last5", "float2"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Derived Scores",
                "Heuristic/model tarafinin bu an icin olusturdugu ust seviye sinyaller.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Favorite Fragility", "favorite_fragility_score", "float2"),
                        ("Underdog Resistance", "underdog_resistance_score", "float2"),
                        ("Comeback Potential", "comeback_potential_score", "float2"),
                        ("Late Goal Risk", "late_goal_risk_score", "float2"),
                        ("Market Overreaction", "market_overreaction_score", "float2"),
                        ("Market Underreaction", "market_underreaction_score", "float2"),
                    ],
                ),
            ),
            _snapshot_data_card(
                "Labels",
                "Bu snapshot'tan sonra ogrenilecek hedefler.",
                _snapshot_rows(
                    snapshot,
                    [
                        ("Final Result 1X2", "label_final_result_1x2", "text"),
                        ("Home Win", "label_home_win", "bool"),
                        ("Goal Next 10m", "label_goal_next10min", "bool"),
                        ("Next Goal Team", "label_next_goal_team", "text"),
                        ("Result To End", "label_result_from_snapshot_to_end", "text"),
                        ("Over 2.5 From Snapshot", "label_over25_from_snapshot", "bool"),
                    ],
                ),
            ),
        ]
    )

    return (
        '<section class="card wide">'
        "<h2>Feature Snapshot</h2>"
        "<p>Feature pipeline'in bu mac icin urettigi son analytics gorunumu. Bos alanlar provider coverage yoklugu demektir.</p>"
        f'<section class="metrics">{metric_cards}</section>'
        f'<div class="pill-row">{availability_pills}{quality_pills}{source_pills}</div>'
        '<div class="stack">'
        f'<a class="tag" href="{latest_json_href}">Latest JSON</a>'
        f'<a class="tag" href="{all_json_href}">Live Snapshot List</a>'
        "</div>"
        f'<section class="detail-grid">{cards}</section>'
        "</section>"
    )


def _snapshot_metric_card(label: str, value: str) -> str:
    return f'<article class="metric snapshot-metric"><span>{escape(label)}</span><strong>{escape(value)}</strong></article>'


def _snapshot_data_card(title: str, subtitle: str, rows: list[tuple[str, str]]) -> str:
    body = (
        "".join(
            f'<div class="kv-item"><span>{escape(label)}</span><strong>{escape(value)}</strong></div>'
            for label, value in rows
        )
        if rows
        else '<div class="kv-empty">Data yok.</div>'
    )
    return (
        '<article class="card snapshot-card">'
        f"<h2>{escape(title)}</h2>"
        f"<p>{escape(subtitle)}</p>"
        f'<div class="kv-list">{body}</div>'
        "</article>"
    )


def _snapshot_rows(snapshot: object, fields: list[tuple[str, str, str]]) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for label, attr, style in fields:
        value = getattr(snapshot, attr, None)
        rendered = _snapshot_format_value(value, style)
        if rendered is None:
            continue
        rows.append((label, rendered))
    return rows


def _snapshot_display(snapshot: object, attr: str, style: str) -> str:
    rendered = _snapshot_format_value(getattr(snapshot, attr, None), style)
    return rendered or "-"


def _snapshot_json_display(snapshot: object, attr: str, key: str, style: str) -> str:
    payload = getattr(snapshot, attr, None)
    if not isinstance(payload, dict):
        return "-"
    rendered = _snapshot_format_value(payload.get(key), style)
    return rendered or "-"


def _snapshot_pills(prefix: str, payload: object) -> str:
    if not isinstance(payload, dict) or not payload:
        return ""
    items: list[str] = []
    for key, value in payload.items():
        label = f"{prefix}: {key.replace('_', ' ')}"
        if isinstance(value, bool):
            items.append(
                f'<span class="pill {"pill-good" if value else "pill-bad"}">{escape(label)} = {escape("yes" if value else "no")}</span>'
            )
        else:
            items.append(f'<span class="pill">{escape(label)} = {escape(str(value))}</span>')
    return "".join(items)


def _snapshot_format_value(value: object | None, style: str) -> str | None:
    if style == "negated_bool":
        if value is None:
            return None
        return "yes" if not bool(value) else "no"
    if value is None:
        return None
    if style == "enum":
        return str(getattr(value, "value", value))
    if style == "text":
        text = str(value).strip()
        return text or None
    if style == "bool":
        return "yes" if bool(value) else "no"
    if style == "datetime":
        return _display_datetime(value)
    if style == "minutes":
        return f"{int(float(value))}m"
    if style == "int":
        return str(int(float(value)))
    if style == "float1":
        return f"{float(value):.1f}"
    if style == "float2":
        return f"{float(value):.2f}"
    if style == "signed1":
        return f"{float(value):+.1f}"
    if style == "signed2":
        return f"{float(value):+.2f}"
    if style == "pct1":
        return f"{float(value) * 100:.1f}%"
    if style == "signed_pct1":
        return f"{float(value) * 100:+.1f}%"
    return str(value)


def _player_sync_rows(
    *,
    provider_slug: str,
    mapped_teams_count: int,
    items: list[object],
    q: str | None,
    country_slug: str | None,
    sync_runs: list[object],
) -> str:
    latest = sync_runs[0] if sync_runs else None
    latest_stats = getattr(latest, "stats", {}) if latest is not None else {}
    latest_status = getattr(getattr(latest, "status", None), "value", "-")
    latest_started = _display_datetime(getattr(latest, "started_at", None))
    latest_error = getattr(latest, "error_message", None) or "-"
    latest_provider = getattr(getattr(latest, "provider", None), "slug", provider_slug)

    rows = [
        f"<tr><th>Selected Provider</th><td>{escape(provider_slug)}</td></tr>",
        f"<tr><th>Mapped Teams For Provider</th><td>{mapped_teams_count}</td></tr>",
        f"<tr><th>Visible Players On This Page</th><td>{len(items)}</td></tr>",
        f"<tr><th>Active Filters</th><td>q={escape(q or '-')} | country_slug={escape(country_slug or '-')}</td></tr>",
        f"<tr><th>Latest Player Sync Status</th><td>{escape(str(latest_status))}</td></tr>",
        f"<tr><th>Latest Player Sync Started</th><td>{escape(latest_started)}</td></tr>",
        f"<tr><th>Latest Player Sync Provider</th><td>{escape(str(latest_provider))}</td></tr>",
        f"<tr><th>players_upserted</th><td>{latest_stats.get('players_upserted', 0)}</td></tr>",
        f"<tr><th>players_fetched</th><td>{latest_stats.get('players_fetched', 0)}</td></tr>",
        f"<tr><th>teams_total_mapped</th><td>{latest_stats.get('teams_total_mapped', mapped_teams_count)}</td></tr>",
        f"<tr><th>teams_scanned</th><td>{latest_stats.get('teams_scanned', 0)}</td></tr>",
        f"<tr><th>teams_synced</th><td>{latest_stats.get('teams_synced', 0)}</td></tr>",
        f"<tr><th>teams_missing_roster</th><td>{latest_stats.get('teams_missing_roster', 0)}</td></tr>",
        f"<tr><th>teams_failed</th><td>{latest_stats.get('teams_failed', 0)}</td></tr>",
        f"<tr><th>Latest Error</th><td>{escape(str(latest_error))}</td></tr>",
    ]

    if not items:
        rows.extend(
            [
                "<tr><th>Note</th><td>Bu sayfa sadece DB'ye yazilmis oyunculari listeler.</td></tr>",
                "<tr><th>Note</th><td>Provider dashboard'da basarili roster cagrilari gorunse bile players_upserted sifir olabilir.</td></tr>",
                "<tr><th>Note</th><td>Secili provider ile once match sync calisip takim mapping'leri olusmus olmalidir.</td></tr>",
                "<tr><th>Note</th><td>Player sync secili provider icin tum mapped takimlari tarar; binlerce takim varsa islem uzun surebilir.</td></tr>",
                "<tr><th>Note</th><td>Yeni akista veriler takim takim commit edilir; sync surerken baska bir sekmeden sayfayi yenilersen artis gorebilirsin.</td></tr>",
                "<tr><th>Note</th><td>Bazi takimlarin roster endpoint'i 404 donerse onlar skip edilir; tum sync artik fail olmaz.</td></tr>",
            ]
        )

    return "".join(rows)


def _date_navigation(
    path: str,
    target_date: date,
    params: dict[str, object | None] | None = None,
    extra_actions: str = "",
) -> str:
    query_params = params or {}
    prev_date = target_date - timedelta(days=1)
    next_date = target_date + timedelta(days=1)
    today = _today()
    prev_href = f'{path}?{_query({**query_params, "target_date": prev_date.isoformat()})}'
    today_href = f'{path}?{_query({**query_params, "target_date": today.isoformat()})}'
    next_href = f'{path}?{_query({**query_params, "target_date": next_date.isoformat()})}'
    return (
        '<section class="date-nav">'
        f'<a class="date-nav-btn" href="{prev_href}">&larr; Previous Day</a>'
        f'<div class="date-nav-current"><span class="muted">Selected Date</span><strong>{escape(target_date.isoformat())}</strong></div>'
        f'<div class="date-nav-actions"><a class="date-nav-btn" href="{today_href}">Today</a><a class="date-nav-btn" href="{next_href}">Next Day &rarr;</a>{extra_actions}</div>'
        "</section>"
    )


def _schedule_sync_form(
    target_date: date,
    limit: int | None,
    timezone_name: str,
    provider_slug: str,
) -> str:
    hidden_limit = (
        f'<input type="hidden" name="limit" value="{limit}" />'
        if limit is not None
        else ""
    )
    return (
        '<form class="inline-form stack" method="post" action="/ui/schedule/run">'
        f'<input type="hidden" name="target_date" value="{escape(target_date.isoformat())}" />'
        f'<input type="hidden" name="tz" value="{escape(timezone_name)}" />'
        f"{hidden_limit}"
        f'<select class="date-nav-btn" name="provider_slug">{_schedule_provider_option_tags(provider_slug)}</select>'
        '<button class="btn" type="submit">Sync This Day</button>'
        "</form>"
    )


def _schedule_lineup_sync_form(
    target_date: date,
    limit: int | None,
    timezone_name: str,
    provider_slug: str,
) -> str:
    hidden_limit = (
        f'<input type="hidden" name="limit" value="{limit}" />'
        if limit is not None
        else ""
    )
    return (
        '<form class="inline-form stack" method="post" action="/ui/schedule/players/run">'
        f'<input type="hidden" name="target_date" value="{escape(target_date.isoformat())}" />'
        f'<input type="hidden" name="tz" value="{escape(timezone_name)}" />'
        f"{hidden_limit}"
        f'<select class="date-nav-btn" name="provider_slug">{_schedule_provider_option_tags(provider_slug)}</select>'
        '<button class="btn" type="submit">Sync Match Players</button>'
        "</form>"
    )


def _schedule_forward_sync_link(provider_slug: str) -> str:
    return (
        f'<a class="date-nav-btn" href="/ui/schedule/forward-sync?{_query({"provider_slug": provider_slug})}">'
        "Schedule Runner"
        "</a>"
    )


def _schedule_sync_status_panel(status, *, selected_date: date, timezone_name: str, provider_slug: str) -> str:
    relevant = (
        status.running
        or status.started_at is not None
        or status.target_date == selected_date
        or status.provider_slug == provider_slug
    )
    if not relevant:
        return ""

    auto_refresh = ""
    if status.running:
        auto_refresh = """
        <script>
          window.setTimeout(() => {
            window.location.reload();
          }, 3000);
        </script>
        """

    events = "".join(f"<li>{escape(item)}</li>" for item in status.events[-8:]) or "<li>No events yet.</li>"
    wait_text = (
        f"{status.wait_seconds:.1f}s"
        if isinstance(status.wait_seconds, (int, float))
        else "-"
    )
    attempt_text = (
        f"{status.attempt}/{status.attempts}"
        if status.attempt is not None and status.attempts is not None
        else "-"
    )
    stats_text = ", ".join(f"{key}={value}" for key, value in status.stats.items()) or "-"
    current_marker = ""
    if (
        status.target_date == selected_date
        and status.provider_slug == provider_slug
        and (status.timezone_name or timezone_name) == timezone_name
    ):
        current_marker = '<p class="muted">This panel belongs to the currently selected day/provider.</p>'

    return f"""
    {auto_refresh}
    <section class="card">
      <div class="head"><h2>Schedule Sync Status</h2><span class="muted">{escape(status.state)}</span></div>
      {current_marker}
      <table>
        <tbody>
          <tr><th>Provider</th><td>{escape(status.provider_slug)}</td></tr>
          <tr><th>Target Date</th><td>{escape(_display_date(status.target_date))}</td></tr>
          <tr><th>Timezone</th><td>{escape(status.timezone_name or '-')}</td></tr>
          <tr><th>Started</th><td>{escape(_display_datetime(status.started_at))}</td></tr>
          <tr><th>Completed</th><td>{escape(_display_datetime(status.completed_at))}</td></tr>
          <tr><th>Attempt</th><td>{escape(attempt_text)}</td></tr>
          <tr><th>Status Code</th><td>{escape(str(status.status_code or '-'))}</td></tr>
          <tr><th>Wait</th><td>{escape(wait_text)}</td></tr>
          <tr><th>Last Message</th><td>{escape(str(status.last_message or '-'))}</td></tr>
          <tr><th>Last Error</th><td>{escape(str(status.last_error or '-'))}</td></tr>
          <tr><th>Stats</th><td>{escape(stats_text)}</td></tr>
        </tbody>
      </table>
      <div class="table-wrap">
        <h3>Recent Events</h3>
        <ul>{events}</ul>
      </div>
    </section>
    """


def _lineup_sync_status_panel(status, *, selected_date: date, timezone_name: str, provider_slug: str) -> str:
    relevant = (
        status.running
        or status.started_at is not None
        or (
            status.target_date == selected_date
            and status.provider_slug == provider_slug
        )
    )
    if not relevant:
        return ""

    auto_refresh = ""
    if status.running:
        auto_refresh = """
        <script>
          window.setTimeout(() => {
            window.location.reload();
          }, 2000);
        </script>
        """

    events = "".join(f"<li>{escape(item)}</li>" for item in status.events[-8:]) or "<li>No events yet.</li>"
    wait_text = (
        f"{status.wait_seconds:.1f}s"
        if isinstance(status.wait_seconds, (int, float))
        else "-"
    )
    attempt_text = (
        f"{status.attempt}/{status.attempts}"
        if status.attempt is not None and status.attempts is not None
        else "-"
    )
    stats_text = ", ".join(f"{key}={value}" for key, value in status.stats.items()) or "-"
    current_marker = ""
    if (
        status.target_date == selected_date
        and status.provider_slug == provider_slug
        and (status.timezone_name or timezone_name) == timezone_name
    ):
        current_marker = (
            '<p class="muted">Bu panel Sync Match Players kosusunun ne yaptigini canli gosterir: '
            'maclari tarar, lineup bulursa oyunculari yazar, bulamazsa no lineup isaretler.</p>'
        )

    return f"""
    {auto_refresh}
    <section class="card">
      <div class="head"><h2>Match Player Sync Status</h2><span class="muted">{escape(status.state)}</span></div>
      {current_marker}
      <table>
        <tbody>
          <tr><th>Provider</th><td>{escape(status.provider_slug)}</td></tr>
          <tr><th>Target Date</th><td>{escape(_display_date(status.target_date))}</td></tr>
          <tr><th>Timezone</th><td>{escape(status.timezone_name or '-')}</td></tr>
          <tr><th>Started</th><td>{escape(_display_datetime(status.started_at))}</td></tr>
          <tr><th>Completed</th><td>{escape(_display_datetime(status.completed_at))}</td></tr>
          <tr><th>Attempt</th><td>{escape(attempt_text)}</td></tr>
          <tr><th>Status Code</th><td>{escape(str(status.status_code or '-'))}</td></tr>
          <tr><th>Wait</th><td>{escape(wait_text)}</td></tr>
          <tr><th>Last Message</th><td>{escape(str(status.last_message or '-'))}</td></tr>
          <tr><th>Last Error</th><td>{escape(str(status.last_error or '-'))}</td></tr>
          <tr><th>Stats</th><td>{escape(stats_text)}</td></tr>
        </tbody>
      </table>
      <div class="table-wrap">
        <h3>Recent Events</h3>
        <ul>{events}</ul>
      </div>
    </section>
    """


def _feature_pipeline_status_panel(status, *, selected_date: date, timezone_name: str) -> str:
    relevant = (
        status.running
        or status.started_at is not None
        or status.target_date == selected_date
    )
    if not relevant:
        return ""

    auto_refresh = ""
    if status.running:
        auto_refresh = """
        <script>
          window.setTimeout(() => {
            window.location.reload();
          }, 2500);
        </script>
        """

    events = "".join(f"<li>{escape(item)}</li>" for item in status.events[-10:]) or "<li>No events yet.</li>"
    sync_rows = "".join(
        f"<tr><th>{escape(scope)}</th><td>{escape(sync_run_id)}</td></tr>"
        for scope, sync_run_id in status.sync_run_ids.items()
    ) or '<tr><th>Sync Runs</th><td>-</td></tr>'
    current_marker = ""
    if status.target_date == selected_date and (status.timezone_name or timezone_name) == timezone_name:
        current_marker = (
            '<p class="muted">Bu pipeline market/context ingest, rating rebuild ve snapshot materialization '
            'asamalarini tek kosuda calistirir.</p>'
        )

    return f"""
    {auto_refresh}
    <section class="card">
      <div class="head"><h2>Feature Pipeline Status</h2><span class="muted">{escape(status.state)}</span></div>
      {current_marker}
      <table>
        <tbody>
          <tr><th>Provider</th><td>{escape(status.provider_slug)}</td></tr>
          <tr><th>Target Date</th><td>{escape(_display_date(status.target_date))}</td></tr>
          <tr><th>Timezone</th><td>{escape(status.timezone_name or '-')}</td></tr>
          <tr><th>Current Scope</th><td>{escape(status.current_scope or '-')}</td></tr>
          <tr><th>Started</th><td>{escape(_display_datetime(status.started_at))}</td></tr>
          <tr><th>Completed</th><td>{escape(_display_datetime(status.completed_at))}</td></tr>
          <tr><th>Last Message</th><td>{escape(str(status.last_message or '-'))}</td></tr>
          <tr><th>Last Error</th><td>{escape(str(status.last_error or '-'))}</td></tr>
          <tr><th>Stats</th><td>{escape(', '.join(f'{key}={value}' for key, value in status.stats.items()) or '-')}</td></tr>
          {sync_rows}
        </tbody>
      </table>
      <div class="table-wrap">
        <h3>Recent Events</h3>
        <ul>{events}</ul>
      </div>
    </section>
    """


def _schedule_timezone_form(
    target_date: date,
    timezone_name: str,
    limit: int | None,
    provider_slug: str,
) -> str:
    hidden_limit = (
        f'<input type="hidden" name="limit" value="{limit}" />'
        if limit is not None
        else ""
    )
    return (
        '<form class="inline-form stack" method="get" action="/ui/schedule">'
        f'<input type="hidden" name="target_date" value="{escape(target_date.isoformat())}" />'
        f'<input type="hidden" name="provider_slug" value="{escape(provider_slug)}" />'
        f"{hidden_limit}"
        f'<input class="date-nav-btn" type="text" name="tz" value="{escape(timezone_name)}" placeholder="Europe/Istanbul" />'
        '<button class="date-nav-btn" type="submit">Apply TZ</button>'
        "</form>"
    )


def _schedule_feature_pipeline_form(
    target_date: date,
    limit: int | None,
    timezone_name: str,
    provider_slug: str,
) -> str:
    hidden_limit = (
        f'<input type="hidden" name="limit" value="{limit}" />'
        if limit is not None
        else ""
    )
    return (
        '<form class="inline-form stack" method="post" action="/ui/schedule/features/run">'
        f'<input type="hidden" name="target_date" value="{escape(target_date.isoformat())}" />'
        f'<input type="hidden" name="tz" value="{escape(timezone_name)}" />'
        f'<input type="hidden" name="provider_slug" value="{escape(provider_slug)}" />'
        f"{hidden_limit}"
        '<button class="date-nav-btn" type="submit">Run Feature Pipeline</button>'
        "</form>"
    )


def _schedule_timezone_bootstrap(
    target_date: date,
    limit: int | None,
    provider_slug: str,
) -> str:
    hidden_limit = (
        f'<input type="hidden" name="limit" value="{limit}" />'
        if limit is not None
        else ""
    )
    return f"""
    <script>
      (() => {{
        const url = new URL(window.location.href);
        if (url.searchParams.get("tz")) {{
          return;
        }}
        const browserTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
        if (!browserTz) {{
          url.searchParams.set("tz", "{DEFAULT_TIMEZONE}");
        }} else {{
          url.searchParams.set("tz", browserTz);
        }}
        if (!url.searchParams.get("target_date")) {{
          const now = new Date();
          const year = now.getFullYear();
          const month = String(now.getMonth() + 1).padStart(2, "0");
          const day = String(now.getDate()).padStart(2, "0");
          url.searchParams.set("target_date", `${{year}}-${{month}}-${{day}}`);
        }}
        window.location.replace(url.toString());
      }})();
    </script>
    <section class="card">
      <h2>Resolving Timezone</h2>
      <p>Tarayici timezone bilgisi okunup secili gun buna gore yeniden yukleniyor.</p>
      <form class="filters" method="get" action="/ui/schedule">
        <input type="hidden" name="target_date" value="{escape(target_date.isoformat())}" />
        <input type="hidden" name="provider_slug" value="{escape(provider_slug)}" />
        {hidden_limit}
        <button class="btn" type="submit">Load With Default TZ</button>
      </form>
    </section>
    """


def _forward_schedule_sync_panel(status) -> str:
    auto_refresh = (
        """
        <script>
          setTimeout(() => window.location.reload(), 2500);
        </script>
        """
        if status.running
        else ""
    )
    action_form = (
        '<form class="inline-form" method="post" action="/ui/schedule/forward-sync/stop">'
        '<button class="btn" type="submit">Stop Run</button>'
        "</form>"
        if status.running
        else _schedule_runner_start_form(status)
    )
    metrics = (
        '<section class="metrics">'
        f'<article class="metric"><span>Status</span><strong>{escape(status.state)}</strong></article>'
        f'<article class="metric"><span>Provider</span><strong>{escape(status.provider_slug)}</strong></article>'
        f'<article class="metric"><span>Direction</span><strong>{escape(status.direction)}</strong></article>'
        f'<article class="metric"><span>Current Day</span><strong>{escape(_display_date(status.current_date))}</strong></article>'
        f'<article class="metric"><span>Processed Days</span><strong>{status.processed_days}</strong></article>'
        f'<article class="metric"><span>Matches Downloaded</span><strong>{status.total_matches_downloaded}</strong></article>'
        f'<article class="metric"><span>Successful Days</span><strong>{status.successful_days}</strong></article>'
        f'<article class="metric"><span>404 Retries</span><strong>{status.retry_count}</strong></article>'
        f'<article class="metric"><span>Last Day Count</span><strong>{status.last_matches_count if status.last_matches_count is not None else "-"}</strong></article>'
        "</section>"
    )
    detail_rows = "".join(
        [
            f"<tr><th>Started From</th><td>{escape(_display_date(status.started_from))}</td></tr>",
            f"<tr><th>Provider</th><td>{escape(status.provider_slug)}</td></tr>",
            f"<tr><th>Direction</th><td>{escape(status.direction)}</td></tr>",
            f"<tr><th>Max Days</th><td>{escape(str(status.max_days) if status.max_days is not None else '-')}</td></tr>",
            f"<tr><th>Last Completed Day</th><td>{escape(_display_date(status.last_completed_date))}</td></tr>",
            f"<tr><th>Started At</th><td>{escape(_display_datetime(status.started_at))}</td></tr>",
            f"<tr><th>Completed At</th><td>{escape(_display_datetime(status.completed_at))}</td></tr>",
            f"<tr><th>Last Message</th><td>{escape(status.last_message or '-')}</td></tr>",
            f"<tr><th>Last Error</th><td>{escape(status.last_error or '-')}</td></tr>",
        ]
    )
    return (
        auto_refresh
        + _table_card(
            "Schedule Runner",
            (
                "Secilen tarihten ileri veya geri gunleri tarar. "
                "404 olursa ayni gunu basarili olana kadar tekrar dener."
            ),
            action_form,
            "<tr><th>Field</th><th>Value</th></tr>",
            detail_rows,
            "",
        )
        + metrics
    )


def _forward_schedule_inline_panel(status) -> str:
    relevant = (
        status.running
        or status.started_at is not None
        or status.completed_at is not None
        or status.last_message is not None
    )
    if not relevant:
        return ""

    auto_refresh = (
        """
        <script>
          setTimeout(() => window.location.reload(), 2500);
        </script>
        """
        if status.running
        else ""
    )
    action = (
        '<a class="date-nav-btn" href="/ui/schedule/forward-sync">Open Runner</a>'
        if not status.running
        else (
            '<div class="stack">'
            '<a class="date-nav-btn" href="/ui/schedule/forward-sync">Open Runner</a>'
            '<form class="inline-form" method="post" action="/ui/schedule/forward-sync/stop">'
            '<button class="date-nav-btn" type="submit">Stop Runner</button>'
            "</form>"
            "</div>"
        )
    )
    return f"""
    {auto_refresh}
    <section class="card">
      <div class="head"><h2>Historical Schedule Runner</h2>{action}</div>
      <p>Gun gun historical match takvimi indirir. Ayrica <a href="/ui/schedule/forward-sync">Schedule Runner</a> sayfasindan detayli izlenebilir.</p>
      <table>
        <tbody>
          <tr><th>Status</th><td>{escape(status.state)}</td></tr>
          <tr><th>Provider</th><td>{escape(status.provider_slug)}</td></tr>
          <tr><th>Started From</th><td>{escape(_display_date(status.started_from))}</td></tr>
          <tr><th>Direction</th><td>{escape(status.direction)}</td></tr>
          <tr><th>Current Day</th><td>{escape(_display_date(status.current_date))}</td></tr>
          <tr><th>Processed Days</th><td>{status.processed_days}</td></tr>
          <tr><th>Matches Downloaded</th><td>{status.total_matches_downloaded}</td></tr>
          <tr><th>Successful Days</th><td>{status.successful_days}</td></tr>
          <tr><th>Last Message</th><td>{escape(status.last_message or '-')}</td></tr>
          <tr><th>Last Error</th><td>{escape(status.last_error or '-')}</td></tr>
        </tbody>
      </table>
    </section>
    """


def _schedule_runner_start_form(status) -> str:
    start_date = _display_date(status.started_from if status.started_from is not None else _today())
    max_days = status.max_days if status.max_days is not None else 365
    forward_selected = "selected" if status.direction != "backward" else ""
    backward_selected = "selected" if status.direction == "backward" else ""
    return (
        '<form class="filters" method="post" action="/ui/schedule/forward-sync/start">'
        f'<label class="field"><span>provider</span><select name="provider_slug">{_provider_option_tags(status.provider_slug)}</select></label>'
        f'<label class="field"><span>start_date</span><input type="date" name="start_date" value="{escape(start_date)}" /></label>'
        '<label class="field"><span>direction</span><select name="direction">'
        f'<option value="forward" {forward_selected}>forward</option>'
        f'<option value="backward" {backward_selected}>backward</option>'
        "</select></label>"
        f'<label class="field"><span>max_days</span><input type="number" name="max_days" min="1" value="{escape(str(max_days))}" /></label>'
        '<button class="btn" type="submit">Start Run</button>'
        "</form>"
    )


def _provider_option_tags(selected_slug: str) -> str:
    return "".join(
        f'<option value="{escape(slug)}" {"selected" if slug == selected_slug else ""}>{escape(label)}</option>'
        for slug, label in MATCH_PROVIDER_OPTIONS
    )


def _schedule_provider_option_tags(selected_slug: str) -> str:
    return "".join(
        f'<option value="{escape(slug)}" {"selected" if slug == selected_slug else ""}>{escape(label)}</option>'
        for slug, label in SCHEDULE_MATCH_PROVIDER_OPTIONS
    )


def _schedule_provider_hint(provider_slug: str) -> str:
    return (
        '<section class="card"><p>'
        f"Active sync provider: <strong>{escape(provider_slug)}</strong>"
        "</p></section>"
    )


def _filters(action: str, fields: list[str]) -> str:
    return f'<form class="filters" method="get" action="{action}">{"".join(fields)}<button class="btn" type="submit">Filter</button></form>'


def _text(name: str, value: str | None, placeholder: str) -> str:
    return f'<label class="field"><span>{escape(name)}</span><input type="text" name="{escape(name)}" value="{escape(value or "")}" placeholder="{escape(placeholder)}" /></label>'


def _number(name: str, value: int) -> str:
    return f'<label class="field"><span>{escape(name)}</span><input type="number" name="{escape(name)}" min="10" max="{MAX_LIMIT}" value="{value}" /></label>'


def _date(name: str, value: date | None) -> str:
    return f'<label class="field"><span>{escape(name)}</span><input type="date" name="{escape(name)}" value="{value.isoformat() if value else ""}" /></label>'


def _checkbox(name: str, checked: bool, label: str) -> str:
    return f'<label class="check"><input type="checkbox" name="{escape(name)}" value="true" {"checked" if checked else ""} /><span>{escape(label)}</span></label>'


def _select(name: str, value: str | None, options: list[str]) -> str:
    tags = "".join(f'<option value="{escape(opt)}" {"selected" if opt == (value or "") else ""}>{escape(opt or "all")}</option>' for opt in options)
    return f'<label class="field"><span>{escape(name)}</span><select name="{escape(name)}">{tags}</select></label>'


def _pager(path: str, params: dict[str, object | None], offset: int, limit: int, has_next: bool) -> str:
    prev_link = ""
    if offset > 0:
        prev_link = f'<a href="{path}?{_query({**params, "offset": max(offset - limit, 0)})}">Previous</a>'
    next_link = ""
    if has_next:
        next_link = f'<a href="{path}?{_query({**params, "offset": offset + limit})}">Next</a>'
    return f'<div class="pager"><span class="muted">Page {offset // limit + 1}</span><div class="stack">{prev_link}{next_link}</div></div>'


def _query(params: dict[str, object | None]) -> str:
    clean = {k: str(v) for k, v in params.items() if v not in (None, "", False)}
    return urlencode(clean)


def _competition_link(competition: object | None) -> str:
    if competition is None:
        return "-"
    name = getattr(competition, "name", None)
    if not name:
        return "-"
    slug = getattr(competition, "slug", None)
    if slug:
        return f'<a href="/ui/competitions/{quote_plus(str(slug))}">{escape(str(name))}</a>'
    return escape(str(name))


def _season_link(season: object | None) -> str:
    if season is None:
        return "-"
    label = getattr(season, "label", None)
    if not label:
        return "-"
    entity_uid = getattr(season, "entity_uid", None)
    if entity_uid:
        return f'<a href="/ui/seasons/{quote_plus(str(entity_uid))}">{escape(str(label))}</a>'
    return escape(str(label))


def _score(match: object) -> str:
    home = getattr(match, "score_home", None)
    away = getattr(match, "score_away", None)
    if home is None and away is None:
        return "-"
    return f"{home if home is not None else '-'} - {away if away is not None else '-'}"


def _match_open_link(match: object, timezone_name: str | None = None) -> str:
    match_id = getattr(match, "id", None)
    if match_id is None:
        return "-"
    query = _query({"tz": timezone_name})
    suffix = f"?{query}" if query else ""
    return f'<a href="/ui/matches/{escape(str(match_id))}{suffix}">Open</a>'


def _match_rows(
    matches: list[object],
    *,
    show_competition: bool,
    show_season: bool,
    timezone_name: str | None = None,
    show_player_sync: bool = False,
    player_sync_counts: dict[UUID, dict[str, dict[str, int]]] | None = None,
    player_sync_provider_slug: str | None = None,
) -> str:
    column_count = 5 + int(show_competition) + int(show_season) + int(show_player_sync)
    if not matches:
        return f'<tr><td colspan="{column_count}">Kayit yok.</td></tr>'

    rows: list[str] = []
    for item in matches:
        row = [f"<tr><td>{escape(_format_datetime(item.kickoff_at, timezone_name))}</td>"]
        if show_competition:
            row.append(f'<td>{_competition_link(getattr(item, "competition", None))}</td>')
        row.append(
            f"<td>{escape(item.home_team.name)} vs {escape(item.away_team.name)}</td>"
        )
        if show_season:
            row.append(f'<td>{_season_link(getattr(item, "season", None))}</td>')
        row.append(f"<td>{escape(item.status.value)}</td>")
        row.append(f"<td>{escape(_score(item))}</td>")
        if show_player_sync:
            row.append(
                f"<td>{_match_player_sync_badge(item, player_sync_counts or {}, provider_slug=player_sync_provider_slug)}</td>"
            )
        row.append(f"<td>{_match_open_link(item, timezone_name)}</td></tr>")
        rows.append("".join(row))
    return "".join(rows)


def _match_player_sync_badge(
    match: object,
    counts: dict[UUID, dict[str, dict[str, int]]],
    *,
    provider_slug: str | None = None,
) -> str:
    match_id = getattr(match, "id", None)
    if match_id is None:
        return '<span class="muted">not synced</span>'

    side_counts = counts.get(match_id, {})
    home_counts = side_counts.get("home", {"played": 0, "listed": 0})
    away_counts = side_counts.get("away", {"played": 0, "listed": 0})
    home_listed = int(home_counts.get("listed", 0))
    away_listed = int(away_counts.get("listed", 0))
    home_played = int(home_counts.get("played", 0))
    away_played = int(away_counts.get("played", 0))

    if home_listed == 0 and away_listed == 0:
        metadata = getattr(match, "metadata_json", {}) or {}
        lineup_metadata = metadata.get("lineup") if isinstance(metadata, dict) else None
        allowed_provider_slugs = None
        if provider_slug is not None:
            allowed_provider_slugs = set(expand_lineup_provider_slugs(provider_slug))
            allowed_provider_slugs.add(None)
        if (
            isinstance(lineup_metadata, dict)
            and lineup_metadata.get("status") == "missing"
            and (
                provider_slug is None
                or lineup_metadata.get("provider_slug") in allowed_provider_slugs
            )
        ):
            return '<span class="muted">no lineup</span>'
        return '<span class="muted">not synced</span>'

    return (
        f"Home {home_played}/{home_listed} | Away {away_played}/{away_listed}"
    )


def _format_datetime(value: object, timezone_name: str | None) -> str:
    if not hasattr(value, "tzinfo"):
        return str(value)
    return convert_datetime(value, timezone_name).isoformat()


def _normalize_ui_timezone(
    timezone_name: str | None,
    message: str | None,
) -> tuple[str, str | None]:
    try:
        return canonical_timezone_name(timezone_name), message
    except ValueError as exc:
        fallback = DEFAULT_TIMEZONE
        extra = f"{exc} Falling back to {fallback}."
        return fallback, f"{message} | {extra}" if message else extra


def _nav(label: str, href: str, active: bool) -> str:
    return f'<a class="{"active" if active else ""}" href="{href}">{escape(label)}</a>'


def _display_date(value: date | None) -> str:
    return value.isoformat() if value is not None else "-"


def _display_datetime(value: object | None) -> str:
    if value is None:
        return "-"
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _today() -> date:
    return date.today()


def _limit(value: int) -> int:
    return max(10, min(value, MAX_LIMIT))


def _offset(value: int) -> int:
    return max(0, value)
