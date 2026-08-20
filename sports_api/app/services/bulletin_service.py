"""Bulletin query service.

Serves the daily iddaa bulletin (matches + current odds with movement) and the
per-match odds history, both backed by the canonical ``MatchMarketTick`` time
series. Aggregation is implemented as pure functions over tick rows so it can
be unit-tested without a database.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.timezones import utc_day_bounds
from app.db.models.domain import Match, MatchMarketTick, SnapshotPhase
from app.domain.iddaa_markets import (
    IDDAA_MARKETS,
    get_market_for_tick,
    selection_label_tr,
)
from app.schemas.bulletin import (
    BulletinMarketOdds,
    BulletinMatch,
    BulletinResponse,
    BulletinSelectionOdds,
    MatchOddsResponse,
    OddsHistoryPoint,
    SelectionOddsHistory,
)

_MARKET_ORDER = {market.code: index for index, market in enumerate(IDDAA_MARKETS)}
_SELECTION_ORDER: dict[str, dict[str, int]] = {
    market.code: {key: index for index, key in enumerate(market.selections)}
    for market in IDDAA_MARKETS
}


@dataclass(slots=True)
class TickRow:
    """Provider-agnostic view of one odds tick used by the aggregators."""

    market_type: str
    selection_key: str
    line_value: float | None
    odds_decimal: float | None
    implied_prob: float | None
    normalized_prob: float | None
    tick_time: datetime
    suspended: bool = False

    @classmethod
    def from_model(cls, tick: MatchMarketTick) -> TickRow:
        return cls(
            market_type=tick.market_type,
            selection_key=tick.selection_key,
            line_value=tick.line_value,
            odds_decimal=tick.odds_decimal,
            implied_prob=tick.implied_prob,
            normalized_prob=tick.normalized_prob,
            tick_time=tick.tick_time,
            suspended=bool(tick.suspended),
        )


def build_market_views(
    ticks: list[TickRow],
    *,
    market_codes: set[str] | None = None,
) -> list[BulletinMarketOdds]:
    """Aggregate raw ticks into per-market current odds with movement.

    For each iddaa market/selection the earliest tick is the opening odds and
    the latest tick is the current one. Non-iddaa markets (unknown type or
    line) are dropped.
    """
    grouped: dict[tuple[str, str], dict[str, list[TickRow]]] = {}
    for tick in ticks:
        if tick.odds_decimal is None or tick.odds_decimal <= 1.0:
            continue
        market = get_market_for_tick(tick.market_type, tick.line_value)
        if market is None:
            continue
        if market_codes is not None and market.code not in market_codes:
            continue
        market_group = grouped.setdefault((market.code, market.market_type), {})
        market_group.setdefault(tick.selection_key, []).append(tick)

    views: list[BulletinMarketOdds] = []
    for (market_code, market_type), selections in grouped.items():
        market = next(m for m in IDDAA_MARKETS if m.code == market_code)
        selection_views: list[BulletinSelectionOdds] = []
        last_tick_at: datetime | None = None
        for selection_key, selection_ticks in selections.items():
            ordered = sorted(selection_ticks, key=lambda item: item.tick_time)
            opening, latest = ordered[0], ordered[-1]
            if last_tick_at is None or latest.tick_time > last_tick_at:
                last_tick_at = latest.tick_time
            movement_pct: float | None = None
            if opening.odds_decimal and latest.odds_decimal and opening is not latest:
                movement_pct = (
                    (latest.odds_decimal - opening.odds_decimal) / opening.odds_decimal * 100.0
                )
            selection_views.append(
                BulletinSelectionOdds(
                    selection_key=selection_key,
                    label_tr=selection_label_tr(market_type, selection_key, market.line_value),
                    odds=latest.odds_decimal,
                    opening_odds=(
                        opening.odds_decimal if opening is not latest else latest.odds_decimal
                    ),
                    implied_prob=latest.implied_prob,
                    normalized_prob=latest.normalized_prob,
                    movement_pct=movement_pct,
                    is_dropping=bool(movement_pct is not None and movement_pct < 0),
                    suspended=latest.suspended,
                )
            )

        selection_order = _SELECTION_ORDER.get(market_code, {})
        selection_views.sort(
            key=lambda view: selection_order.get(view.selection_key, len(selection_order))
        )
        views.append(
            BulletinMarketOdds(
                market_code=market_code,
                market_type=market_type,
                name_tr=market.name_tr,
                line_value=market.line_value,
                last_tick_at=last_tick_at,
                selections=selection_views,
            )
        )

    views.sort(key=lambda view: _MARKET_ORDER.get(view.market_code, len(_MARKET_ORDER)))
    return views


def build_selection_histories(ticks: list[TickRow]) -> list[SelectionOddsHistory]:
    """Group ticks into per-selection time series for odds movement charts."""
    grouped: dict[tuple[str, str], list[TickRow]] = {}
    for tick in ticks:
        if tick.odds_decimal is None or tick.odds_decimal <= 1.0:
            continue
        market = get_market_for_tick(tick.market_type, tick.line_value)
        if market is None:
            continue
        grouped.setdefault((market.code, tick.selection_key), []).append(tick)

    histories: list[SelectionOddsHistory] = []
    for (market_code, selection_key), selection_ticks in grouped.items():
        market = next(m for m in IDDAA_MARKETS if m.code == market_code)
        ordered = sorted(selection_ticks, key=lambda item: item.tick_time)
        histories.append(
            SelectionOddsHistory(
                market_code=market_code,
                market_type=market.market_type,
                name_tr=market.name_tr,
                line_value=market.line_value,
                selection_key=selection_key,
                label_tr=market.selection_label(selection_key),
                points=[
                    OddsHistoryPoint(
                        tick_time=tick.tick_time,
                        odds=tick.odds_decimal,
                        implied_prob=tick.implied_prob,
                    )
                    for tick in ordered
                ],
            )
        )

    selection_orders = _SELECTION_ORDER
    histories.sort(
        key=lambda history: (
            _MARKET_ORDER.get(history.market_code, len(_MARKET_ORDER)),
            selection_orders.get(history.market_code, {}).get(history.selection_key, 99),
        )
    )
    return histories


def extract_mbs(match: Match) -> int | None:
    metadata = getattr(match, "metadata_json", None)
    if not isinstance(metadata, dict):
        return None
    raw = metadata.get("raw")
    if isinstance(raw, dict):
        value = raw.get("_mbs")
        if isinstance(value, int):
            return value
    value = metadata.get("_mbs")
    return value if isinstance(value, int) else None


class BulletinService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_bulletin(
        self,
        *,
        target_date: date,
        timezone_name: str,
        competition_query: str | None = None,
        market_codes: set[str] | None = None,
        limit: int = 500,
    ) -> BulletinResponse:
        start_at, end_at = utc_day_bounds(target_date, timezone_name)
        query = (
            select(Match)
            .options(
                selectinload(Match.home_team),
                selectinload(Match.away_team),
                selectinload(Match.competition),
            )
            .where(Match.kickoff_at >= start_at, Match.kickoff_at < end_at)
            .order_by(Match.kickoff_at.asc())
            .limit(limit)
        )
        result = await self.session.execute(query)
        matches = list(result.scalars().unique().all())

        if competition_query:
            needle = competition_query.strip().casefold()
            matches = [
                match
                for match in matches
                if match.competition is not None
                and needle in (match.competition.name or "").casefold()
            ]

        ticks_by_match = await self._load_ticks(
            [match.id for match in matches], phase=SnapshotPhase.pre
        )

        bulletin_matches: list[BulletinMatch] = []
        for match in matches:
            match_ticks = ticks_by_match.get(match.id, [])
            markets = build_market_views(match_ticks, market_codes=market_codes)
            bulletin_matches.append(
                BulletinMatch(
                    match_id=str(match.id),
                    kickoff_at=match.kickoff_at,
                    status=match.status.value,
                    competition_name=(
                        match.competition.name if match.competition is not None else None
                    ),
                    home_team=match.home_team.name,
                    away_team=match.away_team.name,
                    mbs=extract_mbs(match),
                    markets=markets,
                )
            )

        return BulletinResponse(
            target_date=target_date,
            timezone=timezone_name,
            match_count=len(bulletin_matches),
            matches=bulletin_matches,
        )

    async def get_match_odds(self, *, match_id: uuid.UUID) -> MatchOddsResponse | None:
        query = (
            select(Match)
            .options(
                selectinload(Match.home_team),
                selectinload(Match.away_team),
            )
            .where(Match.id == match_id)
        )
        result = await self.session.execute(query)
        match = result.scalars().unique().one_or_none()
        if match is None:
            return None

        ticks_by_match = await self._load_ticks([match.id], phase=None)
        ticks = ticks_by_match.get(match.id, [])
        return MatchOddsResponse(
            match_id=str(match.id),
            home_team=match.home_team.name,
            away_team=match.away_team.name,
            kickoff_at=match.kickoff_at,
            markets=build_market_views(ticks),
            history=build_selection_histories(ticks),
        )

    async def _load_ticks(
        self,
        match_ids: list[uuid.UUID],
        *,
        phase: SnapshotPhase | None,
    ) -> dict[uuid.UUID, list[TickRow]]:
        if not match_ids:
            return {}
        query = select(MatchMarketTick).where(MatchMarketTick.match_id.in_(match_ids))
        if phase is not None:
            query = query.where(MatchMarketTick.snapshot_phase == phase)
        query = query.order_by(MatchMarketTick.tick_time.asc())
        result = await self.session.execute(query)

        grouped: dict[uuid.UUID, list[TickRow]] = {}
        for tick in result.scalars().all():
            grouped.setdefault(tick.match_id, []).append(TickRow.from_model(tick))
        return grouped
