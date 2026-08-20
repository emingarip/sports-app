from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.domain import (
    EntityType,
    Match,
    MatchPlayerAppearance,
    Player,
    Provider,
    RawProviderPayload,
    SyncRun,
    Team,
)
from app.providers.base import ProviderMatchLineupEntrySeed, ProviderMatchLineupSeed
from app.services.player_persistence import PlayerPersistenceService


@dataclass(slots=True)
class MatchLineupPersistStats:
    appearances_upserted: int = 0
    appearances_deleted: int = 0
    matches_marked_no_lineup: int = 0
    raw_payloads_written: int = 0

    def to_dict(self) -> dict[str, int]:
        return {
            "appearances_upserted": self.appearances_upserted,
            "appearances_deleted": self.appearances_deleted,
            "matches_marked_no_lineup": self.matches_marked_no_lineup,
            "raw_payloads_written": self.raw_payloads_written,
        }


class MatchLineupPersistenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.player_service = PlayerPersistenceService(session)
        self.stats = MatchLineupPersistStats()

    async def persist_match_lineup(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        match: Match,
        lineup: ProviderMatchLineupSeed,
        source_provider_slug: str | None = None,
        source_provider_match_id: str | None = None,
    ) -> dict[str, int]:
        home_team = match.home_team
        away_team = match.away_team
        self._promote_starters_when_match_has_no_participation_data(match=match, lineup=lineup)
        existing_appearances = await self._get_existing_appearances(
            provider=provider,
            match=match,
        )

        for entry in lineup.home_players:
            await self._upsert_entry(
                provider=provider,
                sync_run=sync_run,
                match=match,
                team=home_team,
                entry=entry,
                existing_appearances=existing_appearances,
            )

        for entry in lineup.away_players:
            await self._upsert_entry(
                provider=provider,
                sync_run=sync_run,
                match=match,
                team=away_team,
                entry=entry,
                existing_appearances=existing_appearances,
            )

        for stale_appearance in existing_appearances.values():
            await self.session.delete(stale_appearance)
            self.stats.appearances_deleted += 1

        match.metadata_json = {
            **match.metadata_json,
            "lineup": {
                "provider_slug": provider.slug,
                "provider_match_id": lineup.provider_match_id,
                "source_provider_slug": source_provider_slug or provider.slug,
                "source_provider_match_id": source_provider_match_id or lineup.provider_match_id,
                "status": "available",
                "missing_reason": None,
                "confirmed": lineup.confirmed,
                "home_formation": lineup.home_formation,
                "away_formation": lineup.away_formation,
                "home_listed_players": len(lineup.home_players),
                "away_listed_players": len(lineup.away_players),
                "checked_at": datetime.now(UTC).isoformat(),
            },
        }
        await self.session.flush()

        self.stats.raw_payloads_written += await self._store_raw_payload(
            provider=provider,
            sync_run=sync_run,
            provider_match_id=lineup.provider_match_id,
            payload=lineup.raw,
        )

        merged = self.player_service.catalog.stats.to_dict()
        for key, value in self.player_service.stats.to_dict().items():
            merged[key] = merged.get(key, 0) + value
        for key, value in self.stats.to_dict().items():
            merged[key] = merged.get(key, 0) + value
        return merged

    async def persist_missing_match_lineup(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        match: Match,
        provider_match_id: str,
        reason: str = "no_lineup",
        source_provider_slug: str | None = None,
        source_provider_match_id: str | None = None,
    ) -> dict[str, int]:
        match.metadata_json = {
            **match.metadata_json,
            "lineup": {
                "provider_slug": provider.slug,
                "provider_match_id": provider_match_id,
                "source_provider_slug": source_provider_slug,
                "source_provider_match_id": source_provider_match_id or provider_match_id,
                "status": "missing",
                "missing_reason": reason,
                "confirmed": None,
                "home_formation": None,
                "away_formation": None,
                "home_listed_players": 0,
                "away_listed_players": 0,
                "checked_at": datetime.now(UTC).isoformat(),
            },
        }
        await self.session.flush()

        self.stats.matches_marked_no_lineup += 1

        merged = self.player_service.catalog.stats.to_dict()
        for key, value in self.player_service.stats.to_dict().items():
            merged[key] = merged.get(key, 0) + value
        for key, value in self.stats.to_dict().items():
            merged[key] = merged.get(key, 0) + value
        return merged

    async def _upsert_entry(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        match: Match,
        team: Team,
        entry: ProviderMatchLineupEntrySeed,
        existing_appearances: dict[tuple[str, str], MatchPlayerAppearance],
    ) -> None:
        player = await self.player_service._upsert_player(
            provider=provider,
            sync_run=sync_run,
            seed=entry.player,
        )
        await self.player_service._upsert_team_membership(
            player=player,
            team=team,
            seed=entry.player,
        )

        appearance_key = (entry.team_side, player.entity_uid)
        appearance = existing_appearances.pop(appearance_key, None)
        created = appearance is None
        if appearance is None:
            appearance = MatchPlayerAppearance(
                provider_id=provider.id,
                match_id=match.id,
                player_id=player.id,
                team_id=team.id,
                side=entry.team_side,
                is_starter=entry.is_starter,
                is_substitute=entry.is_substitute,
                played=entry.played,
                minutes_played=entry.minutes_played,
                position=entry.position,
                squad_number=entry.squad_number,
                metadata_json={},
            )
            self.session.add(appearance)
        else:
            appearance.player_id = player.id
            appearance.team_id = team.id
            appearance.side = entry.team_side
            appearance.is_starter = entry.is_starter
            appearance.is_substitute = entry.is_substitute
            appearance.played = entry.played
            appearance.minutes_played = entry.minutes_played
            appearance.position = entry.position
            appearance.squad_number = entry.squad_number

        appearance.metadata_json = {
            **appearance.metadata_json,
            "statistics": entry.statistics,
            "normalized_statistics": self._normalize_statistics_payload(entry.statistics),
            "raw": entry.raw,
        }
        await self.session.flush()

        if created:
            self.stats.appearances_upserted += 1

    async def _get_existing_appearances(
        self,
        *,
        provider: Provider,
        match: Match,
    ) -> dict[tuple[str, str], MatchPlayerAppearance]:
        result = await self.session.execute(
            select(MatchPlayerAppearance, Player.entity_uid)
            .join(Player, Player.id == MatchPlayerAppearance.player_id)
            .where(
                MatchPlayerAppearance.provider_id == provider.id,
                MatchPlayerAppearance.match_id == match.id,
            )
        )
        return {
            (appearance.side, player_entity_uid): appearance
            for appearance, player_entity_uid in result.all()
        }

    async def _store_raw_payload(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        provider_match_id: str,
        payload: dict,
    ) -> int:
        checksum = hashlib.sha256(
            json.dumps(payload, sort_keys=True, ensure_ascii=True).encode("utf-8")
        ).hexdigest()
        existing = await self.session.execute(
            select(RawProviderPayload).where(
                RawProviderPayload.provider_id == provider.id,
                RawProviderPayload.entity_type == EntityType.match,
                RawProviderPayload.provider_entity_id == provider_match_id,
                RawProviderPayload.checksum == checksum,
            )
        )
        if existing.scalar_one_or_none() is not None:
            return 0

        raw_payload = RawProviderPayload(
            provider_id=provider.id,
            sync_run_id=sync_run.id if sync_run is not None else None,
            entity_type=EntityType.match,
            provider_entity_id=provider_match_id,
            checksum=checksum,
            payload=payload,
            fetched_at=datetime.now(UTC),
        )
        self.session.add(raw_payload)
        await self.session.flush()
        return 1

    @classmethod
    def _promote_starters_when_match_has_no_participation_data(
        cls,
        *,
        match: Match,
        lineup: ProviderMatchLineupSeed,
    ) -> None:
        if not cls._match_should_have_played_data(match):
            return

        entries = [*lineup.home_players, *lineup.away_players]
        if not entries:
            return

        has_any_played_flag = any(bool(entry.played) for entry in entries)
        has_any_minutes = any((entry.minutes_played or 0) > 0 for entry in entries)
        has_any_statistics = any(bool(entry.statistics) for entry in entries)
        if has_any_played_flag or has_any_minutes or has_any_statistics:
            return

        for entry in entries:
            if entry.is_starter:
                entry.played = True

    @staticmethod
    def _match_should_have_played_data(match: Match) -> bool:
        status = getattr(match, "status", None)
        status_value = getattr(status, "value", status)
        return status_value in {"live", "finished"}

    @classmethod
    def _normalize_statistics_payload(cls, value: object) -> object:
        if isinstance(value, dict):
            normalized: dict[str, object] = {}
            for key, nested_value in value.items():
                normalized_key = cls._normalize_stat_key(key)
                normalized[normalized_key] = cls._normalize_statistics_payload(nested_value)
            return normalized

        if isinstance(value, list):
            return [cls._normalize_statistics_payload(item) for item in value]

        if isinstance(value, tuple):
            return [cls._normalize_statistics_payload(item) for item in value]

        if isinstance(value, str):
            return cls._normalize_stat_scalar(value)

        return value

    @staticmethod
    def _normalize_stat_key(key: object) -> str:
        text = str(key).strip()
        if not text:
            return "unknown"
        text = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", text)
        text = re.sub(r"[^0-9A-Za-z]+", "_", text)
        text = text.strip("_").lower()
        return text or "unknown"

    @staticmethod
    def _normalize_stat_scalar(value: str) -> object:
        text = value.strip()
        if not text:
            return None

        lowered = text.casefold()
        if lowered == "true":
            return True
        if lowered == "false":
            return False
        if lowered in {"null", "none", "n/a"}:
            return None

        if re.fullmatch(r"-?\d+", text):
            try:
                return int(text)
            except ValueError:
                return text

        if re.fullmatch(r"-?\d+\.\d+", text):
            try:
                return float(text)
            except ValueError:
                return text

        return text
