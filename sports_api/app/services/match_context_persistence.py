from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.domain import (
    EntityType,
    Match,
    MatchEventTimeline,
    MatchLiveStatFrame,
    MatchMarketTick,
    Player,
    Provider,
    ProviderEntityMapping,
    RawProviderPayload,
    SnapshotPhase,
    SyncRun,
)
from app.providers.base import (
    ProviderMatchIncidentSeed,
    ProviderMatchLiveStatFrameSeed,
    ProviderMatchMarketTickSeed,
    ProviderShotEventSeed,
)


@dataclass(slots=True)
class MatchContextPersistStats:
    events_upserted: int = 0
    market_ticks_upserted: int = 0
    live_stat_frames_upserted: int = 0
    raw_payloads_written: int = 0

    def to_dict(self) -> dict[str, int]:
        return {
            "events_upserted": self.events_upserted,
            "market_ticks_upserted": self.market_ticks_upserted,
            "live_stat_frames_upserted": self.live_stat_frames_upserted,
            "raw_payloads_written": self.raw_payloads_written,
        }


class MatchContextPersistenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.stats = MatchContextPersistStats()

    async def persist_markets(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        match: Match,
        provider_match_id: str,
        prematch_ticks: list[ProviderMatchMarketTickSeed],
        live_ticks: list[ProviderMatchMarketTickSeed],
    ) -> dict[str, int]:
        await self.session.execute(
            delete(MatchMarketTick).where(
                MatchMarketTick.provider_id == provider.id,
                MatchMarketTick.match_id == match.id,
            )
        )

        combined_ticks = [*prematch_ticks, *live_ticks]
        for tick in combined_ticks:
            self.session.add(
                MatchMarketTick(
                    provider_id=provider.id,
                    match_id=match.id,
                    snapshot_phase=SnapshotPhase(tick.phase),
                    market_type=tick.market_type,
                    selection_key=tick.selection_key,
                    tick_time=tick.tick_time or datetime.now(UTC),
                    minute=tick.minute,
                    line_value=tick.line_value,
                    odds_decimal=tick.odds_decimal,
                    implied_prob=tick.implied_prob,
                    normalized_prob=tick.normalized_prob,
                    bookmaker_key=tick.bookmaker_key,
                    suspended=bool(tick.suspended),
                    metadata_json={"raw": tick.raw},
                )
            )
            self.stats.market_ticks_upserted += 1

        await self.session.flush()
        self.stats.raw_payloads_written += await self._store_raw_payload(
            provider=provider,
            sync_run=sync_run,
            provider_entity_id=f"{provider_match_id}:markets",
            payload={
                "prematch": [tick.raw for tick in prematch_ticks],
                "live": [tick.raw for tick in live_ticks],
            },
        )
        return self.stats.to_dict()

    async def persist_context(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        match: Match,
        provider_match_id: str,
        incidents: list[ProviderMatchIncidentSeed],
        live_frames: list[ProviderMatchLiveStatFrameSeed],
        shots: list[ProviderShotEventSeed],
    ) -> dict[str, int]:
        await self.session.execute(
            delete(MatchEventTimeline).where(
                MatchEventTimeline.provider_id == provider.id,
                MatchEventTimeline.match_id == match.id,
            )
        )
        await self.session.execute(
            delete(MatchLiveStatFrame).where(
                MatchLiveStatFrame.provider_id == provider.id,
                MatchLiveStatFrame.match_id == match.id,
            )
        )

        player_map = await self._load_player_map(
            provider=provider,
            provider_player_ids={
                player_id
                for item in incidents
                for player_id in (item.player_provider_id, item.related_player_provider_id)
                if player_id
            },
        )

        for incident in incidents:
            self.session.add(
                MatchEventTimeline(
                    provider_id=provider.id,
                    match_id=match.id,
                    provider_event_id=incident.provider_event_id,
                    event_type=incident.incident_type,
                    event_subtype=incident.incident_subtype,
                    team_side=incident.team_side,
                    minute=incident.minute,
                    stoppage_minute=incident.stoppage_minute,
                    sort_order=incident.sort_order,
                    player_id=player_map.get(incident.player_provider_id),
                    related_player_id=player_map.get(incident.related_player_provider_id),
                    player_name=incident.player_name,
                    related_player_name=incident.related_player_name,
                    score_home=incident.score_home,
                    score_away=incident.score_away,
                    occurred_at=incident.occurred_at,
                    metadata_json={"raw": incident.raw},
                )
            )
            self.stats.events_upserted += 1

        for frame in self._dedupe_live_frames(match=match, live_frames=live_frames):
            self.session.add(
                MatchLiveStatFrame(
                    provider_id=provider.id,
                    match_id=match.id,
                    tick_time=self._resolve_frame_time(match=match, frame=frame),
                    minute=frame.minute,
                    home_xg=frame.home_xg,
                    away_xg=frame.away_xg,
                    home_shots=frame.home_shots,
                    away_shots=frame.away_shots,
                    home_shots_on_target=frame.home_shots_on_target,
                    away_shots_on_target=frame.away_shots_on_target,
                    home_corners=frame.home_corners,
                    away_corners=frame.away_corners,
                    home_possession=frame.home_possession,
                    away_possession=frame.away_possession,
                    home_dangerous_attacks=frame.home_dangerous_attacks,
                    away_dangerous_attacks=frame.away_dangerous_attacks,
                    home_box_entries=frame.home_box_entries,
                    away_box_entries=frame.away_box_entries,
                    home_pressure_index=frame.home_pressure_index,
                    away_pressure_index=frame.away_pressure_index,
                    metadata_json={"raw": frame.raw},
                )
            )
            self.stats.live_stat_frames_upserted += 1

        await self.session.flush()
        self.stats.raw_payloads_written += await self._store_raw_payload(
            provider=provider,
            sync_run=sync_run,
            provider_entity_id=f"{provider_match_id}:context",
            payload={
                "incidents": [incident.raw for incident in incidents],
                "live_frames": [frame.raw for frame in live_frames],
                "shots": [shot.raw for shot in shots],
            },
        )
        return self.stats.to_dict()

    async def _load_player_map(
        self,
        *,
        provider: Provider,
        provider_player_ids: set[str],
    ) -> dict[str, object]:
        if not provider_player_ids:
            return {}

        result = await self.session.execute(
            select(ProviderEntityMapping.provider_entity_id, Player.id)
            .join(Player, Player.entity_uid == ProviderEntityMapping.canonical_entity_uid)
            .where(
                ProviderEntityMapping.provider_id == provider.id,
                ProviderEntityMapping.entity_type == EntityType.player,
                ProviderEntityMapping.provider_entity_id.in_(provider_player_ids),
            )
        )
        return {str(provider_entity_id): player_id for provider_entity_id, player_id in result.all()}

    async def _store_raw_payload(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        provider_entity_id: str,
        payload: dict,
    ) -> int:
        checksum = hashlib.sha256(
            json.dumps(payload, sort_keys=True, ensure_ascii=True).encode("utf-8")
        ).hexdigest()
        existing = await self.session.execute(
            select(RawProviderPayload).where(
                RawProviderPayload.provider_id == provider.id,
                RawProviderPayload.entity_type == EntityType.match,
                RawProviderPayload.provider_entity_id == provider_entity_id,
                RawProviderPayload.checksum == checksum,
            )
        )
        if existing.scalar_one_or_none() is not None:
            return 0

        raw_payload = RawProviderPayload(
            provider_id=provider.id,
            sync_run_id=sync_run.id if sync_run is not None else None,
            entity_type=EntityType.match,
            provider_entity_id=provider_entity_id,
            checksum=checksum,
            payload=payload,
            fetched_at=datetime.now(UTC),
        )
        self.session.add(raw_payload)
        await self.session.flush()
        return 1

    def _dedupe_live_frames(
        self,
        *,
        match: Match,
        live_frames: list[ProviderMatchLiveStatFrameSeed],
    ) -> list[ProviderMatchLiveStatFrameSeed]:
        deduped: dict[tuple[int | None, datetime], ProviderMatchLiveStatFrameSeed] = {}
        for frame in live_frames:
            tick_time = self._resolve_frame_time(match=match, frame=frame)
            deduped[(frame.minute, tick_time)] = ProviderMatchLiveStatFrameSeed(
                provider_match_id=frame.provider_match_id,
                frame_time=tick_time,
                minute=frame.minute,
                home_xg=frame.home_xg,
                away_xg=frame.away_xg,
                home_shots=frame.home_shots,
                away_shots=frame.away_shots,
                home_shots_on_target=frame.home_shots_on_target,
                away_shots_on_target=frame.away_shots_on_target,
                home_corners=frame.home_corners,
                away_corners=frame.away_corners,
                home_possession=frame.home_possession,
                away_possession=frame.away_possession,
                home_dangerous_attacks=frame.home_dangerous_attacks,
                away_dangerous_attacks=frame.away_dangerous_attacks,
                home_box_entries=frame.home_box_entries,
                away_box_entries=frame.away_box_entries,
                home_pressure_index=frame.home_pressure_index,
                away_pressure_index=frame.away_pressure_index,
                raw=frame.raw,
            )
        return list(deduped.values())

    def _resolve_frame_time(
        self,
        *,
        match: Match,
        frame: ProviderMatchLiveStatFrameSeed,
    ) -> datetime:
        if frame.frame_time is not None:
            return frame.frame_time
        if frame.minute is not None:
            return match.kickoff_at + timedelta(minutes=max(frame.minute, 0))
        return datetime.now(UTC)
