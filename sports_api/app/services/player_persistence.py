from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.text import slugify_text
from app.db.models.domain import (
    Country,
    EntityType,
    Player,
    Provider,
    ProviderEntityMapping,
    RawProviderPayload,
    SyncRun,
    Team,
    TeamMembership,
)
from app.providers.base import ProviderPlayerSeed
from app.services.bootstrap_persistence import BootstrapPersistenceService


@dataclass(slots=True)
class PlayerPersistStats:
    players_upserted: int = 0
    memberships_upserted: int = 0
    mappings_upserted: int = 0
    raw_payloads_written: int = 0

    def to_dict(self) -> dict[str, int]:
        return {
            "players_upserted": self.players_upserted,
            "memberships_upserted": self.memberships_upserted,
            "mappings_upserted": self.mappings_upserted,
            "raw_payloads_written": self.raw_payloads_written,
        }


class PlayerPersistenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.catalog = BootstrapPersistenceService(session)
        self.stats = PlayerPersistStats()

    async def persist_team_players(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun,
        team: Team,
        team_provider_id: str,
        seeds: list[ProviderPlayerSeed],
    ) -> dict[str, int]:
        for seed in seeds:
            player = await self._upsert_player(
                provider=provider,
                sync_run=sync_run,
                seed=seed,
            )
            await self._upsert_team_membership(
                player=player,
                team=team,
                seed=seed,
            )

        merged = self.catalog.stats.to_dict()
        for key, value in self.stats.to_dict().items():
            merged[key] = merged.get(key, 0) + value
        return merged

    async def _upsert_player(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderPlayerSeed,
    ) -> Player:
        country = await self._upsert_country(provider=provider, sync_run=sync_run, seed=seed)
        mapping = await self._get_mapping(
            provider=provider,
            entity_type=EntityType.player,
            provider_entity_id=seed.provider_player_id,
        )
        player = None
        if mapping is not None:
            result = await self.session.execute(
                select(Player).where(Player.entity_uid == mapping.canonical_entity_uid)
            )
            player = result.scalar_one_or_none()

        entity_uid = self._player_entity_uid(seed=seed, country=country)
        if player is None:
            result = await self.session.execute(select(Player).where(Player.entity_uid == entity_uid))
            player = result.scalar_one_or_none()

        created = player is None
        entity_uid = self._player_entity_uid(seed=seed, country=country)
        slug = (
            await self._resolve_unique_player_slug(
                seed=seed,
                country=country,
                entity_uid=entity_uid,
            )
            if player is None
            else (player.slug or self._player_slug_base(seed))
        )

        if player is None:
            player = Player(
                entity_uid=entity_uid,
                full_name=seed.full_name,
                short_name=seed.short_name,
                slug=slug,
                date_of_birth=seed.date_of_birth,
                country_id=country.id if country is not None else None,
                metadata_json={},
            )
            self.session.add(player)
        else:
            player.full_name = seed.full_name
            player.short_name = seed.short_name or player.short_name
            player.slug = slug
            player.date_of_birth = seed.date_of_birth or player.date_of_birth
            player.country_id = country.id if country is not None else player.country_id

        player.metadata_json = {
            **player.metadata_json,
            "provider_player_id": seed.provider_player_id,
            **self._player_metadata_fragment(seed),
            "raw": seed.raw,
        }
        await self.session.flush()

        if created:
            self.stats.players_upserted += 1

        self.stats.mappings_upserted += await self._upsert_mapping(
            provider=provider,
            entity_type=EntityType.player,
            provider_entity_id=seed.provider_player_id,
            canonical_entity_uid=player.entity_uid,
        )
        self.stats.raw_payloads_written += await self._store_raw_payload(
            provider=provider,
            sync_run=sync_run,
            entity_type=EntityType.player,
            provider_entity_id=seed.provider_player_id,
            payload=seed.raw,
        )
        return player

    async def _upsert_team_membership(
        self,
        *,
        player: Player,
        team: Team,
        seed: ProviderPlayerSeed,
    ) -> TeamMembership:
        result = await self.session.execute(
            select(TeamMembership).where(
                TeamMembership.player_id == player.id,
                TeamMembership.team_id == team.id,
                TeamMembership.season_id.is_(None),
            )
        )
        membership = result.scalar_one_or_none()
        created = membership is None

        if membership is None:
            membership = TeamMembership(
                player_id=player.id,
                team_id=team.id,
                season_id=None,
                squad_number=seed.squad_number,
                role=seed.role,
                is_current=seed.is_current if seed.is_current is not None else True,
                metadata_json={},
            )
            self.session.add(membership)
        else:
            membership.squad_number = (
                seed.squad_number if seed.squad_number is not None else membership.squad_number
            )
            membership.role = seed.role or membership.role
            membership.is_current = (
                seed.is_current if seed.is_current is not None else membership.is_current
            )

        membership.metadata_json = {
            **membership.metadata_json,
            "team_provider_id": seed.team_provider_id,
            **self._membership_metadata_fragment(seed),
            "raw": seed.raw,
        }
        await self.session.flush()

        if created:
            self.stats.memberships_upserted += 1
        return membership

    async def _upsert_country(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun | None,
        seed: ProviderPlayerSeed,
    ) -> Country | None:
        if seed.country is None:
            return None
        return await self.catalog.upsert_country_seed(
            provider=provider,
            sync_run=sync_run,
            seed=seed.country,
        )

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
    def _player_slug_base(seed: ProviderPlayerSeed) -> str:
        slug_core = slugify_text(seed.slug or seed.full_name, fallback=f"player-{seed.provider_player_id}")
        if seed.date_of_birth is not None:
            return f"{slug_core}-{seed.date_of_birth.isoformat()}"
        return slug_core

    @staticmethod
    def _player_entity_uid(*, seed: ProviderPlayerSeed, country: Country | None) -> str:
        country_prefix = country.slug if country is not None else "global"
        slug = PlayerPersistenceService._player_slug_base(seed)
        dob = seed.date_of_birth.isoformat() if seed.date_of_birth is not None else "unknown"
        return f"player:{country_prefix}:{slug}:{dob}"

    async def _resolve_unique_player_slug(
        self,
        *,
        seed: ProviderPlayerSeed,
        country: Country | None,
        entity_uid: str,
    ) -> str:
        base_slug = self._player_slug_base(seed)
        country_prefix = country.slug if country is not None else None
        candidate_slugs: list[str] = [base_slug]

        if country_prefix:
            candidate_slugs.append(f"{country_prefix}-{base_slug}")

        candidate_slugs.append(f"{base_slug}-{seed.provider_player_id}")
        if country_prefix:
            candidate_slugs.append(f"{country_prefix}-{base_slug}-{seed.provider_player_id}")

        seen: set[str] = set()
        for candidate in candidate_slugs:
            if candidate in seen:
                continue
            seen.add(candidate)
            existing = await self._find_player_by_slug(candidate)
            if existing is None or existing.entity_uid == entity_uid:
                return candidate

        return f"{base_slug}-{seed.provider_player_id}"

    async def _find_player_by_slug(self, slug: str) -> Player | None:
        result = await self.session.execute(select(Player).where(Player.slug == slug))
        return result.scalar_one_or_none()

    @classmethod
    def _player_metadata_fragment(cls, seed: ProviderPlayerSeed) -> dict[str, object]:
        raw = seed.raw if isinstance(seed.raw, dict) else {}
        raw_player = raw.get("player") if isinstance(raw.get("player"), dict) else raw
        positions_detailed = raw_player.get("positionsDetailed")
        fragment = {
            "team_provider_id": seed.team_provider_id,
            "provider_position": cls._string_or_none(raw.get("position"))
            or cls._string_or_none(raw_player.get("position"))
            or seed.role,
            "provider_positions_detailed": positions_detailed
            if isinstance(positions_detailed, list) and positions_detailed
            else None,
            "provider_preferred_foot": cls._string_or_none(
                raw_player.get("preferredFoot") or raw_player.get("preferred_foot")
            ),
            "provider_height": raw_player.get("height"),
            "provider_weight": raw_player.get("weight"),
        }
        return {key: value for key, value in fragment.items() if value is not None}

    @staticmethod
    def _membership_metadata_fragment(seed: ProviderPlayerSeed) -> dict[str, object]:
        fragment = {
            "provider_squad_number": seed.squad_number,
            "provider_role": seed.role,
            "provider_is_current": seed.is_current,
        }
        return {key: value for key, value in fragment.items() if value is not None}

    @staticmethod
    def _string_or_none(value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None
