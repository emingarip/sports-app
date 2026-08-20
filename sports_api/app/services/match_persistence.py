from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.text import slugify_text
from app.db.models.domain import (
    Country,
    EntityRelation,
    EntityType,
    Match,
    MatchStatus,
    Provider,
    ProviderEntityMapping,
    RawProviderPayload,
    Sport,
    SyncRun,
    Team,
)
from app.knowledge_base.relation_builder import build_match_relation_drafts
from app.providers.base import (
    ProviderBatch,
    ProviderCountrySeed,
    ProviderMatchSeed,
    ProviderTeamSeed,
)
from app.services.bootstrap_persistence import BootstrapPersistenceService


@dataclass(slots=True)
class MatchPersistStats:
    teams_upserted: int = 0
    matches_upserted: int = 0
    mappings_upserted: int = 0
    raw_payloads_written: int = 0
    relations_upserted: int = 0

    def to_dict(self) -> dict[str, int]:
        return {
            "teams_upserted": self.teams_upserted,
            "matches_upserted": self.matches_upserted,
            "mappings_upserted": self.mappings_upserted,
            "raw_payloads_written": self.raw_payloads_written,
            "relations_upserted": self.relations_upserted,
        }


class MatchPersistenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.catalog = BootstrapPersistenceService(session)
        self.stats = MatchPersistStats()

    async def persist_batch(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun,
        batch: ProviderBatch,
    ) -> dict[str, int]:
        for seed in batch.matches:
            await self._persist_match_seed(provider=provider, sync_run=sync_run, seed=seed)

        merged = self.catalog.stats.to_dict()
        for key, value in self.stats.to_dict().items():
            merged[key] = merged.get(key, 0) + value
        return merged

    async def persist_live_match_seed(
        self,
        *,
        provider: Provider,
        seed: ProviderMatchSeed,
    ) -> Match:
        return await self._persist_match_seed(provider=provider, sync_run=None, seed=seed)

    async def _persist_match_seed(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderMatchSeed,
    ) -> Match:
        competition = None
        competition_season = None
        season = None

        if seed.competition is not None:
            if seed.competition.category is not None:
                await self.catalog.upsert_category_seed(
                    provider=provider,
                    sync_run=sync_run,
                    seed=seed.competition.category,
                )

            competition = await self.catalog.upsert_competition_seed(
                provider=provider,
                sync_run=sync_run,
                seed=seed.competition,
            )

        if seed.season is not None:
            season = await self.catalog.upsert_season_seed(
                provider=provider,
                sync_run=sync_run,
                seed=seed.season,
                kickoff_at=seed.kickoff_at,
            )
            competition_season = await self.catalog.upsert_competition_season_seed(
                provider=provider,
                competition=competition,
                season=season,
                seed=seed.season,
            )

        home_country = await self._upsert_country_from_team_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.home_team,
        )
        away_country = await self._upsert_country_from_team_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.away_team,
        )
        home_sport = await self._upsert_sport_from_team_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.home_team,
        )
        away_sport = await self._upsert_sport_from_team_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.away_team,
        )

        home_team = await self._upsert_team(
            provider=provider,
            sync_run=sync_run,
            seed=seed.home_team,
            country=home_country,
            sport=home_sport,
        )
        away_team = await self._upsert_team(
            provider=provider,
            sync_run=sync_run,
            seed=seed.away_team,
            country=away_country,
            sport=away_sport,
        )

        match = await self._upsert_match(
            provider=provider,
            sync_run=sync_run,
            seed=seed,
            competition=competition,
            season=season,
            competition_season=competition_season,
            home_team=home_team,
            away_team=away_team,
        )

        match.home_team = home_team
        match.away_team = away_team
        match.competition_season = competition_season

        for draft in build_match_relation_drafts(match):
            self.stats.relations_upserted += await self._upsert_relation(
                source_entity_uid=draft.source_entity_uid,
                target_entity_uid=draft.target_entity_uid,
                relation_type=draft.relation_type,
                weight=draft.weight,
                metadata=draft.metadata,
            )

        return match

    async def _upsert_country_from_team_seed(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderTeamSeed,
    ) -> Country | None:
        if seed.country is None:
            return None

        return await self.catalog.upsert_country_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.country,
        )

    async def _upsert_sport_from_team_seed(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderTeamSeed,
    ) -> Sport | None:
        if seed.sport is None:
            return None

        return await self.catalog.upsert_sport_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.sport,
        )

    async def _upsert_team(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderTeamSeed,
        country: Country | None,
        sport: Sport | None,
    ) -> Team:
        mapping = await self._get_mapping(
            provider=provider,
            entity_type=EntityType.team,
            provider_entity_id=seed.provider_team_id,
        )
        team = None
        if mapping is not None:
            result = await self.session.execute(
                select(Team).where(Team.entity_uid == mapping.canonical_entity_uid)
            )
            team = result.scalar_one_or_none()

        team_slug = slugify_text(seed.slug or seed.name, fallback=f"team-{seed.provider_team_id}")
        sport_prefix = sport.slug if sport is not None else "global"
        country_prefix = country.slug if country is not None else "global"
        entity_uid = f"team:{sport_prefix}:{country_prefix}:{team_slug}"

        if team is None:
            result = await self.session.execute(select(Team).where(Team.entity_uid == entity_uid))
            team = result.scalar_one_or_none()

        created = team is None
        if team is None:
            team = Team(
                entity_uid=entity_uid,
                name=seed.name,
                short_name=seed.short_name,
                slug=f"{sport_prefix}-{country_prefix}-{team_slug}",
                sport_id=sport.id if sport is not None else None,
                country_id=country.id if country is not None else None,
                gender=seed.gender,
                is_national=seed.national,
                team_type=seed.team_type,
                metadata_json={},
            )
            self.session.add(team)
        else:
            team.name = seed.name
            team.short_name = seed.short_name or team.short_name
            team.sport_id = sport.id if sport is not None else team.sport_id
            team.country_id = country.id if country is not None else team.country_id
            team.gender = seed.gender or team.gender
            team.is_national = seed.national if seed.national is not None else team.is_national
            team.team_type = seed.team_type if seed.team_type is not None else team.team_type

        team.metadata_json = {
            **team.metadata_json,
            "provider_team_id": seed.provider_team_id,
            **self._team_metadata_fragment(seed),
            "raw": seed.raw,
        }
        await self.session.flush()

        if created:
            self.stats.teams_upserted += 1

        self.stats.mappings_upserted += await self._upsert_mapping(
            provider=provider,
            entity_type=EntityType.team,
            provider_entity_id=seed.provider_team_id,
            canonical_entity_uid=team.entity_uid,
        )
        self.stats.raw_payloads_written += await self._store_raw_payload(
            provider=provider,
            sync_run=sync_run,
            entity_type=EntityType.team,
            provider_entity_id=seed.provider_team_id,
            payload=seed.raw,
        )
        return team

    async def _upsert_match(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderMatchSeed,
        competition,
        season,
        competition_season,
        home_team: Team,
        away_team: Team,
    ) -> Match:
        mapping = await self._get_mapping(
            provider=provider,
            entity_type=EntityType.match,
            provider_entity_id=seed.provider_match_id,
        )
        match = None
        if mapping is not None:
            result = await self.session.execute(
                select(Match).where(Match.entity_uid == mapping.canonical_entity_uid)
            )
            match = result.scalar_one_or_none()

        entity_uid = self._match_entity_uid(
            seed=seed,
            competition=competition,
            home_team=home_team,
            away_team=away_team,
        )
        if match is None:
            result = await self.session.execute(select(Match).where(Match.entity_uid == entity_uid))
            match = result.scalar_one_or_none()

        created = match is None

        if match is None:
            match = Match(
                entity_uid=entity_uid,
                competition_id=competition.id if competition is not None else None,
                season_id=season.id if season is not None else None,
                competition_season_id=(
                    competition_season.id if competition_season is not None else None
                ),
                home_team_id=home_team.id,
                away_team_id=away_team.id,
                kickoff_at=seed.kickoff_at,
                status=self._map_match_status(seed.status, seed.provider_status),
                provider_status=seed.provider_status,
                venue_name=seed.venue_name,
                score_home=seed.score_home,
                score_away=seed.score_away,
                score_home_ht=seed.score_home_ht,
                score_away_ht=seed.score_away_ht,
                provider_last_synced_at=datetime.now(UTC),
                metadata_json={},
            )
            self.session.add(match)
        else:
            match.competition_id = (
                competition.id if competition is not None else match.competition_id
            )
            match.season_id = season.id if season is not None else match.season_id
            match.competition_season_id = (
                competition_season.id
                if competition_season is not None
                else match.competition_season_id
            )
            match.home_team_id = home_team.id
            match.away_team_id = away_team.id
            match.kickoff_at = seed.kickoff_at
            match.status = self._map_match_status(seed.status, seed.provider_status)
            match.provider_status = seed.provider_status
            match.venue_name = seed.venue_name
            match.score_home = seed.score_home
            match.score_away = seed.score_away
            if seed.score_home_ht is not None:
                match.score_home_ht = seed.score_home_ht
            if seed.score_away_ht is not None:
                match.score_away_ht = seed.score_away_ht
            match.provider_last_synced_at = datetime.now(UTC)

        match.metadata_json = {
            **match.metadata_json,
            "provider_match_id": seed.provider_match_id,
            **self._match_metadata_fragment(seed),
            "raw": seed.raw,
        }
        await self.session.flush()

        if created:
            self.stats.matches_upserted += 1

        self.stats.mappings_upserted += await self._upsert_mapping(
            provider=provider,
            entity_type=EntityType.match,
            provider_entity_id=seed.provider_match_id,
            canonical_entity_uid=match.entity_uid,
        )
        self.stats.raw_payloads_written += await self._store_raw_payload(
            provider=provider,
            sync_run=sync_run,
            entity_type=EntityType.match,
            provider_entity_id=seed.provider_match_id,
            payload=seed.raw,
        )
        return match

    async def _upsert_mapping(
        self,
        *,
        provider: Provider,
        entity_type: EntityType,
        provider_entity_id: str,
        canonical_entity_uid: str,
    ) -> int:
        mapping = await self._get_mapping(
            provider=provider,
            entity_type=entity_type,
            provider_entity_id=provider_entity_id,
        )
        if mapping is None:
            mapping = ProviderEntityMapping(
                provider_id=provider.id,
                entity_type=entity_type,
                provider_entity_id=provider_entity_id,
                canonical_entity_uid=canonical_entity_uid,
                metadata_json={},
            )
            self.session.add(mapping)
            await self.session.flush()
            return 1

        mapping.canonical_entity_uid = canonical_entity_uid
        return 0

    async def _store_raw_payload(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        entity_type: EntityType,
        provider_entity_id: str,
        payload: dict,
    ) -> int:
        checksum = hashlib.sha256(
            json.dumps(payload, sort_keys=True, ensure_ascii=True).encode("utf-8")
        ).hexdigest()
        existing = await self.session.execute(
            select(RawProviderPayload).where(
                RawProviderPayload.provider_id == provider.id,
                RawProviderPayload.entity_type == entity_type,
                RawProviderPayload.provider_entity_id == provider_entity_id,
                RawProviderPayload.checksum == checksum,
            )
        )
        if existing.scalar_one_or_none() is not None:
            return 0

        raw_payload = RawProviderPayload(
            provider_id=provider.id,
            sync_run_id=sync_run.id if sync_run is not None else None,
            entity_type=entity_type,
            provider_entity_id=provider_entity_id,
            checksum=checksum,
            payload=payload,
            fetched_at=datetime.now(UTC),
        )
        self.session.add(raw_payload)
        await self.session.flush()
        return 1

    async def _upsert_relation(
        self,
        *,
        source_entity_uid: str,
        target_entity_uid: str,
        relation_type,
        weight: float,
        metadata: dict,
    ) -> int:
        result = await self.session.execute(
            select(EntityRelation).where(
                EntityRelation.source_entity_uid == source_entity_uid,
                EntityRelation.target_entity_uid == target_entity_uid,
                EntityRelation.relation_type == relation_type,
            )
        )
        relation = result.scalar_one_or_none()
        if relation is None:
            relation = EntityRelation(
                source_entity_uid=source_entity_uid,
                target_entity_uid=target_entity_uid,
                relation_type=relation_type,
                weight=weight,
                metadata_json=metadata,
            )
            self.session.add(relation)
            await self.session.flush()
            return 1

        relation.weight = weight
        relation.metadata_json = {
            **relation.metadata_json,
            **metadata,
        }
        return 0

    async def _get_mapping(
        self,
        *,
        provider: Provider,
        entity_type: EntityType,
        provider_entity_id: str,
    ) -> ProviderEntityMapping | None:
        result = await self.session.execute(
            select(ProviderEntityMapping).where(
                ProviderEntityMapping.provider_id == provider.id,
                ProviderEntityMapping.entity_type == entity_type,
                ProviderEntityMapping.provider_entity_id == provider_entity_id,
            )
        )
        return result.scalar_one_or_none()

    @staticmethod
    def _country_seed_from_category(payload: dict) -> ProviderCountrySeed | None:
        category = payload.get("category") if isinstance(payload, dict) else None
        country = category.get("country") if isinstance(category, dict) else None
        if not isinstance(country, dict):
            return None

        name = country.get("name") or category.get("name")
        if not name:
            return None

        return ProviderCountrySeed(
            provider_country_id=str(country["id"]) if country.get("id") is not None else None,
            name=str(name),
            slug=country.get("slug") or category.get("slug"),
            iso_code2=country.get("alpha2") or category.get("alpha2") or category.get("code"),
            iso_code3=country.get("alpha3") or country.get("iso3"),
            raw=country,
        )

    @staticmethod
    def _map_match_status(status: str, provider_status: str | None) -> MatchStatus:
        normalized = f"{status} {provider_status or ''}".strip().lower()
        if "notstarted" in normalized or "not started" in normalized or "scheduled" in normalized:
            return MatchStatus.scheduled
        if "postponed" in normalized:
            return MatchStatus.postponed
        if "cancelled" in normalized or "canceled" in normalized or "abandoned" in normalized:
            return MatchStatus.cancelled
        if any(
            token in normalized
            for token in ("finished", "ended", "full time", "after penalties")
        ):
            return MatchStatus.finished
        if any(
            token in normalized
            for token in (
                "1st half",
                "2nd half",
                "halftime",
                "live",
                "inprogress",
                "in progress",
            )
        ):
            return MatchStatus.live
        if re.search(r"\bstarted\b", normalized):
            return MatchStatus.live
        return MatchStatus.unknown

    @staticmethod
    def _match_entity_uid(
        *,
        seed: ProviderMatchSeed,
        competition,
        home_team: Team,
        away_team: Team,
    ) -> str:
        canonical_key = {
            "competition": competition.entity_uid if competition is not None else None,
            "kickoff_at": seed.kickoff_at.astimezone(UTC).isoformat(),
            "home_team": home_team.entity_uid,
            "away_team": away_team.entity_uid,
        }
        digest = hashlib.sha256(
            json.dumps(canonical_key, sort_keys=True, ensure_ascii=True).encode("utf-8")
        ).hexdigest()[:24]
        return f"match:{digest}"

    @classmethod
    def _team_metadata_fragment(cls, seed: ProviderTeamSeed) -> dict[str, object]:
        raw = seed.raw if isinstance(seed.raw, dict) else {}
        fragment = {
            "provider_name_code": cls._string_or_none(raw.get("nameCode")),
            "provider_team_colors": raw.get("teamColors")
            if isinstance(raw.get("teamColors"), dict)
            else None,
        }
        return {key: value for key, value in fragment.items() if value is not None}

    @classmethod
    def _match_metadata_fragment(cls, seed: ProviderMatchSeed) -> dict[str, object]:
        raw = seed.raw if isinstance(seed.raw, dict) else {}
        status_payload = raw.get("status") if isinstance(raw.get("status"), dict) else {}
        fragment = {
            "provider_start_timestamp": raw.get("startTimestamp") or raw.get("kickoffTimestamp"),
            "provider_winner_code": raw.get("winnerCode"),
            "provider_status_type": cls._string_or_none(status_payload.get("type")),
            "provider_status_description": cls._string_or_none(
                status_payload.get("description") or status_payload.get("name")
            ),
            "provider_round_info": raw.get("roundInfo")
            if isinstance(raw.get("roundInfo"), dict)
            else None,
            "provider_venue": raw.get("venue") if isinstance(raw.get("venue"), dict) else None,
        }
        return {key: value for key, value in fragment.items() if value is not None}

    @staticmethod
    def _string_or_none(value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None
