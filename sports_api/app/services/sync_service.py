import inspect
import logging
from datetime import UTC, date, datetime, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.core.timezones import utc_day_bounds
from app.db.models.domain import (
    EntityType,
    Match,
    Provider,
    ProviderEntityMapping,
    SyncRun,
    SyncRunStatus,
    Team,
)
from app.providers.base import ProviderBootstrapCatalog, ProviderClient
from app.providers.hybrid import (
    HYBRID_LINEUP_PROVIDER_NAME,
    HYBRID_LINEUP_PROVIDER_SLUG,
    HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS,
    is_hybrid_lineup_provider,
)
from app.providers.registry import REGISTERED_PROVIDER_CLIENTS
from app.schemas.sync import SyncTriggerResponse
from app.services.bootstrap_persistence import BootstrapPersistenceService
from app.services.feature_rating_service import FeatureRatingService
from app.services.match_context_persistence import MatchContextPersistenceService
from app.services.match_feature_snapshot_service import MatchFeatureSnapshotService
from app.services.match_lineup_persistence import MatchLineupPersistenceService
from app.services.match_persistence import MatchPersistenceService
from app.services.player_persistence import PlayerPersistenceService

logger = logging.getLogger(__name__)


class SyncService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def trigger_provider_sync(
        self,
        *,
        provider_slug: str,
        scope: str,
        target_date: date | None,
        timezone_name: str | None = None,
        category_id: str | None = None,
        tournament_id: str | None = None,
        client_override=None,
        progress_callback=None,
    ) -> SyncTriggerResponse:
        logger.info(
            "sync started provider=%s scope=%s target_date=%s timezone=%s",
            provider_slug,
            scope,
            target_date.isoformat() if target_date is not None else None,
            timezone_name,
        )
        settings = get_settings()
        hybrid_lineup_provider = is_hybrid_lineup_provider(provider_slug)
        client = None

        if hybrid_lineup_provider:
            if scope not in {"matches", "match-lineups"}:
                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    message=(
                        "Hybrid lineup provider supports only matches and match-lineups."
                    ),
                )
            if scope == "matches":
                client = client_override or self._build_provider_client(
                    HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS[0],
                    settings=settings,
                    progress_callback=progress_callback,
                )
                if client_override is not None and progress_callback is not None:
                    client.progress_reporter = progress_callback
            provider = await self._get_or_create_provider(
                provider_slug=provider_slug,
                client=client,
                provider_name=HYBRID_LINEUP_PROVIDER_NAME,
                base_url=getattr(client, "base_url", None),
            )
        else:
            client_cls = REGISTERED_PROVIDER_CLIENTS.get(provider_slug)
            if client_cls is None and client_override is None:
                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    message="Provider client scaffold is missing. Implement it under app/providers/.",
                )

            client = client_override or client_cls(settings=settings)
            if progress_callback is not None:
                client.progress_reporter = progress_callback
            provider = await self._get_or_create_provider(provider_slug=provider_slug, client=client)
        await self._emit_progress(
            progress_callback,
            message=(
                f"Sync started: provider={provider_slug} scope={scope} "
                f"date={target_date.isoformat() if target_date is not None else '-'}."
            ),
        )

        sync_run = SyncRun(
            provider_id=provider.id,
            scope=scope,
            target_date=target_date,
            status=SyncRunStatus.pending,
            started_at=datetime.now(UTC),
        )
        self.session.add(sync_run)
        await self.session.flush()
        sync_run_id = sync_run.id
        sync_started_at = sync_run.started_at
        await self._emit_progress(
            progress_callback,
            message=f"Sync run created: {sync_run_id}",
            sync_run_id=sync_run_id,
        )

        if hybrid_lineup_provider and scope == "match-lineups":
            return await self._trigger_hybrid_match_lineup_sync(
                provider=provider,
                sync_run=sync_run,
                target_date=target_date,
                timezone_name=timezone_name,
                progress_callback=progress_callback,
                sync_run_id=sync_run_id,
                sync_started_at=sync_started_at,
                settings=settings,
            )

        if scope == "bootstrap":
            sync_run.status = SyncRunStatus.failed
            sync_run.completed_at = datetime.now(UTC)
            sync_run.error_message = (
                "Full bootstrap is disabled to protect provider request quotas."
            )
            await self.session.commit()
            await self.session.refresh(sync_run)

            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=sync_run.status,
                queued_at=sync_run.started_at,
                message=(
                    "Full bootstrap is disabled. Use bootstrap-countries, "
                    "bootstrap-tournaments, or bootstrap-seasons with tournament_id."
                ),
            )

        if scope in {"bootstrap-countries", "bootstrap-tournaments", "bootstrap-seasons"}:
            try:
                catalog = await self._build_stage_catalog(
                    client=client,
                    scope=scope,
                    category_id=category_id,
                    tournament_id=tournament_id,
                )
                persist_stats = await BootstrapPersistenceService(self.session).persist_catalog(
                    provider=provider,
                    sync_run=sync_run,
                    catalog=catalog,
                )
                sync_run.status = SyncRunStatus.succeeded
                sync_run.completed_at = datetime.now(UTC)
                sync_run.stats = {
                    **catalog.to_stats(),
                    **persist_stats.to_dict(),
                }
                await self.session.commit()
                await self.session.refresh(sync_run)
                logger.info(
                    "sync bootstrap stage succeeded provider=%s scope=%s target_date=%s stats=%s",
                    provider_slug,
                    scope,
                    target_date.isoformat() if target_date is not None else None,
                    sync_run.stats,
                )
                await self._emit_progress(
                    progress_callback,
                    message=f"Bootstrap stage completed. stats={sync_run.stats}",
                    stats=sync_run.stats,
                    sync_run_id=sync_run.id,
                )

                message = "Bootstrap stage completed."
                if catalog.errors:
                    message = f"{message} Completed with {len(catalog.errors)} non-fatal errors."

                return SyncTriggerResponse(
                    accepted=True,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=sync_run.id,
                    status=sync_run.status,
                    queued_at=sync_run.started_at,
                    stats=sync_run.stats,
                    message=message,
                )
            except Exception as exc:
                logger.exception(
                    "sync bootstrap stage failed provider=%s scope=%s target_date=%s error=%s",
                    provider_slug,
                    scope,
                    target_date.isoformat() if target_date is not None else None,
                    exc,
                )
                await self.session.rollback()
                recovered_provider = await self._get_or_create_provider(
                    provider_slug=provider_slug,
                    client=client,
                )

                failed_sync_run = SyncRun(
                    provider_id=recovered_provider.id,
                    scope=scope,
                    target_date=target_date,
                    status=SyncRunStatus.failed,
                    started_at=sync_started_at,
                    completed_at=datetime.now(UTC),
                    error_message=str(exc),
                )
                self.session.add(failed_sync_run)
                await self.session.commit()
                await self.session.refresh(failed_sync_run)
                await self._emit_progress(
                    progress_callback,
                    message=f"Bootstrap stage failed: {exc}",
                    error=str(exc),
                    status_code=self._extract_error_code(exc),
                    sync_run_id=failed_sync_run.id,
                )

                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=failed_sync_run.id,
                    status=failed_sync_run.status,
                    queued_at=failed_sync_run.started_at,
                    error_code=self._extract_error_code(exc),
                    message=f"Bootstrap stage failed: {exc}",
                )

        if scope in {"market-backfill", "context-backfill"}:
            return await self._trigger_match_context_sync(
                provider=provider,
                client=client,
                scope=scope,
                sync_run=sync_run,
                target_date=target_date,
                timezone_name=timezone_name,
                progress_callback=progress_callback,
                sync_started_at=sync_started_at,
            )

        if scope == "rating-rebuild":
            return await self._trigger_rating_rebuild(
                provider=provider,
                sync_run=sync_run,
                target_date=target_date,
                progress_callback=progress_callback,
                sync_started_at=sync_started_at,
            )

        if scope in {"snapshot-backfill", "snapshot-live"}:
            return await self._trigger_snapshot_materialization(
                provider=provider,
                sync_run=sync_run,
                target_date=target_date,
                timezone_name=timezone_name,
                progress_callback=progress_callback,
                sync_started_at=sync_started_at,
                scope=scope,
            )

        if scope == "matches":
            try:
                if hybrid_lineup_provider:
                    await self._emit_progress(
                        progress_callback,
                        message=(
                            "Hybrid provider uses "
                            f"{HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS[0]} for schedule discovery."
                        ),
                        sync_run_id=sync_run.id,
                    )
                batch = await client.fetch(scope=scope, target_date=target_date)
                persist_stats = await MatchPersistenceService(self.session).persist_batch(
                    provider=provider,
                    sync_run=sync_run,
                    batch=batch,
                )
                sync_run.status = SyncRunStatus.succeeded
                sync_run.completed_at = datetime.now(UTC)
                sync_run.stats = {
                    "matches_count": len(batch.matches),
                    **persist_stats,
                }
                await self.session.commit()
                await self.session.refresh(sync_run)
                logger.info(
                    "sync matches succeeded provider=%s target_date=%s matches_count=%s stats=%s",
                    provider_slug,
                    batch.target_date.isoformat() if batch.target_date is not None else None,
                    len(batch.matches),
                    sync_run.stats,
                )
                await self._emit_progress(
                    progress_callback,
                    message=f"Match sync completed. stats={sync_run.stats}",
                    stats=sync_run.stats,
                    sync_run_id=sync_run.id,
                )

                return SyncTriggerResponse(
                    accepted=True,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=batch.target_date,
                    sync_run_id=sync_run.id,
                    status=sync_run.status,
                    queued_at=sync_run.started_at,
                    stats=sync_run.stats,
                    message="Match sync completed.",
                )
            except Exception as exc:
                logger.exception(
                    "sync matches failed provider=%s target_date=%s error_code=%s error=%s",
                    provider_slug,
                    target_date.isoformat() if target_date is not None else None,
                    self._extract_error_code(exc),
                    exc,
                )
                await self.session.rollback()
                recovered_provider = await self._get_or_create_provider(
                    provider_slug=provider_slug,
                    client=client,
                )

                failed_sync_run = SyncRun(
                    provider_id=recovered_provider.id,
                    scope=scope,
                    target_date=target_date,
                    status=SyncRunStatus.failed,
                    started_at=sync_started_at,
                    completed_at=datetime.now(UTC),
                    error_message=str(exc),
                )
                self.session.add(failed_sync_run)
                await self.session.commit()
                await self.session.refresh(failed_sync_run)
                await self._emit_progress(
                    progress_callback,
                    message=f"Match sync failed: {exc}",
                    error=str(exc),
                    status_code=self._extract_error_code(exc),
                    sync_run_id=failed_sync_run.id,
                )

                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=failed_sync_run.id,
                    status=failed_sync_run.status,
                    queued_at=failed_sync_run.started_at,
                    error_code=self._extract_error_code(exc),
                    message=f"Match sync failed: {exc}",
                )

        if scope == "players":
            try:
                team_mappings = await self._get_provider_team_mappings(provider=provider)
                if not team_mappings:
                    logger.warning(
                        "sync players aborted provider=%s reason=no_mapped_teams",
                        provider_slug,
                    )
                    sync_run.status = SyncRunStatus.failed
                    sync_run.completed_at = datetime.now(UTC)
                    sync_run.error_message = (
                        "No mapped teams found for this provider. Run match sync first."
                    )
                    await self.session.commit()
                    await self.session.refresh(sync_run)
                    await self._emit_progress(
                        progress_callback,
                        message="Player sync failed: no provider-mapped teams found. Run match sync first.",
                        sync_run_id=sync_run.id,
                    )
                    return SyncTriggerResponse(
                        accepted=False,
                        provider_slug=provider_slug,
                        scope=scope,
                        target_date=target_date,
                        sync_run_id=sync_run.id,
                        status=sync_run.status,
                        queued_at=sync_run.started_at,
                        message="Player sync failed: no provider-mapped teams found. Run match sync first.",
                    )

                persist_service = PlayerPersistenceService(self.session)
                total_players_fetched = 0
                teams_total_mapped = len(team_mappings)
                teams_scanned = 0
                teams_synced = 0
                teams_missing_roster = 0
                teams_failed = 0
                last_team_error: str | None = None

                sync_run.status = SyncRunStatus.running
                sync_run.stats = self._player_sync_stats(
                    teams_total_mapped=teams_total_mapped,
                    teams_scanned=teams_scanned,
                    teams_synced=teams_synced,
                    teams_missing_roster=teams_missing_roster,
                    teams_failed=teams_failed,
                    total_players_fetched=total_players_fetched,
                    persist_service=persist_service,
                )
                await self.session.commit()
                sync_run = await self.session.get(SyncRun, sync_run_id)
                await self._emit_progress(
                    progress_callback,
                    message=f"Player sync scanning started. teams_total_mapped={teams_total_mapped}",
                    stats=sync_run.stats,
                    sync_run_id=sync_run.id,
                )

                for team, provider_team_id in team_mappings:
                    teams_scanned += 1
                    try:
                        seeds = await client.get_team_players(provider_team_id)
                        total_players_fetched += len(seeds)
                        team_record = await self.session.get(Team, team.id)
                        if team_record is None:
                            raise RuntimeError(
                                f"Mapped team disappeared before player sync: {team.id}"
                            )

                        await persist_service.persist_team_players(
                            provider=provider,
                            sync_run=sync_run,
                            team=team_record,
                            team_provider_id=provider_team_id,
                            seeds=seeds,
                        )
                        teams_synced += 1
                        logger.info(
                            "sync players team succeeded provider=%s team=%s provider_team_id=%s players=%s",
                            provider_slug,
                            team.name,
                            provider_team_id,
                            len(seeds),
                        )
                    except Exception as exc:
                        logger.warning(
                            "sync players team failed provider=%s team=%s provider_team_id=%s error_code=%s error=%s",
                            provider_slug,
                            team.name,
                            provider_team_id,
                            self._extract_error_code(exc),
                            exc,
                        )
                        await self.session.rollback()
                        provider = await self._get_or_create_provider(
                            provider_slug=provider_slug,
                            client=client,
                        )
                        sync_run = await self.session.get(SyncRun, sync_run_id)
                        if sync_run is None:
                            raise RuntimeError("Sync run disappeared during player sync.") from exc

                        if self._extract_error_code(exc) == 404:
                            teams_missing_roster += 1
                        else:
                            teams_failed += 1
                            last_team_error = (
                                f"Team {team.name} ({provider_team_id}) failed: {exc}"
                            )

                    sync_run.status = SyncRunStatus.running
                    sync_run.stats = self._player_sync_stats(
                        teams_total_mapped=teams_total_mapped,
                        teams_scanned=teams_scanned,
                        teams_synced=teams_synced,
                        teams_missing_roster=teams_missing_roster,
                        teams_failed=teams_failed,
                        total_players_fetched=total_players_fetched,
                        persist_service=persist_service,
                    )
                    sync_run.error_message = last_team_error
                    await self.session.commit()
                    sync_run = await self.session.get(SyncRun, sync_run_id)

                if sync_run is None:
                    sync_run = await self.session.get(SyncRun, sync_run_id)
                sync_run.status = SyncRunStatus.succeeded
                sync_run.completed_at = datetime.now(UTC)
                sync_run.stats = self._player_sync_stats(
                    teams_total_mapped=teams_total_mapped,
                    teams_scanned=teams_scanned,
                    teams_synced=teams_synced,
                    teams_missing_roster=teams_missing_roster,
                    teams_failed=teams_failed,
                    total_players_fetched=total_players_fetched,
                    persist_service=persist_service,
                )
                sync_run.error_message = last_team_error
                await self.session.commit()
                await self.session.refresh(sync_run)
                logger.info(
                    "sync players succeeded provider=%s stats=%s last_error=%s",
                    provider_slug,
                    sync_run.stats,
                    last_team_error,
                )
                await self._emit_progress(
                    progress_callback,
                    message=f"Player sync completed. stats={sync_run.stats}",
                    stats=sync_run.stats,
                    sync_run_id=sync_run.id,
                )

                summary_bits: list[str] = []
                if teams_missing_roster:
                    summary_bits.append(f"skipped {teams_missing_roster} missing rosters")
                if teams_failed:
                    summary_bits.append(f"{teams_failed} teams failed")

                return SyncTriggerResponse(
                    accepted=True,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=sync_run.id,
                    status=sync_run.status,
                    queued_at=sync_run.started_at,
                    stats=sync_run.stats,
                    message=(
                        "Player sync completed."
                        if not summary_bits
                        else f"Player sync completed: {', '.join(summary_bits)}."
                    ),
                )
            except Exception as exc:
                logger.exception(
                    "sync players failed provider=%s target_date=%s error_code=%s error=%s",
                    provider_slug,
                    target_date.isoformat() if target_date is not None else None,
                    self._extract_error_code(exc),
                    exc,
                )
                await self.session.rollback()
                recovered_provider = await self._get_or_create_provider(
                    provider_slug=provider_slug,
                    client=client,
                )

                failed_sync_run = SyncRun(
                    provider_id=recovered_provider.id,
                    scope=scope,
                    target_date=target_date,
                    status=SyncRunStatus.failed,
                    started_at=sync_started_at,
                    completed_at=datetime.now(UTC),
                    error_message=str(exc),
                )
                self.session.add(failed_sync_run)
                await self.session.commit()
                await self.session.refresh(failed_sync_run)
                await self._emit_progress(
                    progress_callback,
                    message=f"Player sync failed: {exc}",
                    error=str(exc),
                    status_code=self._extract_error_code(exc),
                    sync_run_id=failed_sync_run.id,
                )

                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=failed_sync_run.id,
                    status=failed_sync_run.status,
                    queued_at=failed_sync_run.started_at,
                    error_code=self._extract_error_code(exc),
                    message=f"Player sync failed: {exc}",
                )

        if scope == "match-lineups":
            try:
                if target_date is None:
                    raise ValueError("target_date is required for match-lineups.")

                if client.__class__.get_match_lineup is ProviderClient.get_match_lineup:
                    sync_run.status = SyncRunStatus.failed
                    sync_run.completed_at = datetime.now(UTC)
                    sync_run.error_message = (
                        "This provider does not implement match lineup discovery."
                    )
                    await self.session.commit()
                    await self.session.refresh(sync_run)
                    await self._emit_progress(
                        progress_callback,
                        message="Match lineup sync failed: provider does not implement lineup discovery.",
                        sync_run_id=sync_run.id,
                    )
                    return SyncTriggerResponse(
                        accepted=False,
                        provider_slug=provider_slug,
                        scope=scope,
                        target_date=target_date,
                        sync_run_id=sync_run.id,
                        status=sync_run.status,
                        queued_at=sync_run.started_at,
                        message="Match lineup sync failed: provider does not implement lineup discovery.",
                    )

                match_mappings = await self._get_provider_match_mappings(
                    provider=provider,
                    target_date=target_date,
                    timezone_name=timezone_name,
                )
                if not match_mappings:
                    logger.warning(
                        "sync match-lineups aborted provider=%s target_date=%s timezone=%s reason=no_mapped_matches",
                        provider_slug,
                        target_date.isoformat(),
                        timezone_name,
                    )
                    sync_run.status = SyncRunStatus.failed
                    sync_run.completed_at = datetime.now(UTC)
                    sync_run.error_message = (
                        "No mapped matches found for this provider and date. Run match sync first."
                    )
                    await self.session.commit()
                    await self.session.refresh(sync_run)
                    await self._emit_progress(
                        progress_callback,
                        message=(
                            "Match lineup sync failed: no provider-mapped matches found. "
                            "Run match sync first."
                        ),
                        sync_run_id=sync_run.id,
                    )
                    return SyncTriggerResponse(
                        accepted=False,
                        provider_slug=provider_slug,
                        scope=scope,
                        target_date=target_date,
                        sync_run_id=sync_run.id,
                        status=sync_run.status,
                        queued_at=sync_run.started_at,
                        message=(
                            "Match lineup sync failed: no provider-mapped matches found. "
                            "Run match sync first."
                        ),
                    )

                persist_service = MatchLineupPersistenceService(self.session)
                matches_total = len(match_mappings)
                matches_scanned = 0
                matches_with_lineups = 0
                matches_missing_lineups = 0
                matches_failed = 0
                last_match_error: str | None = None

                sync_run.status = SyncRunStatus.running
                sync_run.stats = self._match_lineup_sync_stats(
                    matches_total=matches_total,
                    matches_scanned=matches_scanned,
                    matches_with_lineups=matches_with_lineups,
                    matches_missing_lineups=matches_missing_lineups,
                    matches_failed=matches_failed,
                    persist_service=persist_service,
                )
                await self.session.commit()
                sync_run = await self.session.get(SyncRun, sync_run_id)
                await self._emit_progress(
                    progress_callback,
                    message=f"Match lineup sync scanning started. matches_total={matches_total}",
                    stats=sync_run.stats,
                    sync_run_id=sync_run.id,
                )

                for mapped_match, provider_match_id in match_mappings:
                    matches_scanned += 1
                    try:
                        lineup = await client.get_match_lineup(provider_match_id)
                        if lineup is None:
                            matches_missing_lineups += 1
                            match_record = await self._get_match_for_lineup_sync(mapped_match.id)
                            if match_record is None:
                                raise RuntimeError(
                                    f"Mapped match disappeared before lineup sync: {mapped_match.id}"
                                )
                            await persist_service.persist_missing_match_lineup(
                                provider=provider,
                                sync_run=sync_run,
                                match=match_record,
                                provider_match_id=provider_match_id,
                            )
                        else:
                            match_record = await self._get_match_for_lineup_sync(mapped_match.id)
                            if match_record is None:
                                raise RuntimeError(
                                    f"Mapped match disappeared before lineup sync: {mapped_match.id}"
                                )

                            await persist_service.persist_match_lineup(
                                provider=provider,
                                sync_run=sync_run,
                                match=match_record,
                                lineup=lineup,
                            )
                            matches_with_lineups += 1
                            logger.info(
                                "sync match-lineups match succeeded provider=%s provider_match_id=%s match_id=%s home_players=%s away_players=%s",
                                provider_slug,
                                provider_match_id,
                                mapped_match.id,
                                len(lineup.home_players),
                                len(lineup.away_players),
                            )
                    except Exception as exc:
                        logger.warning(
                            "sync match-lineups match failed provider=%s provider_match_id=%s error_code=%s error=%s",
                            provider_slug,
                            provider_match_id,
                            self._extract_error_code(exc),
                            exc,
                        )
                        await self.session.rollback()
                        provider = await self._get_or_create_provider(
                            provider_slug=provider_slug,
                            client=client,
                        )
                        sync_run = await self.session.get(SyncRun, sync_run_id)
                        if sync_run is None:
                            raise RuntimeError(
                                "Sync run disappeared during match lineup sync."
                            ) from exc

                        if self._extract_error_code(exc) == 404:
                            matches_missing_lineups += 1
                        else:
                            matches_failed += 1
                            last_match_error = (
                                f"Match {provider_match_id} failed: {exc}"
                            )

                    sync_run.status = SyncRunStatus.running
                    sync_run.stats = self._match_lineup_sync_stats(
                        matches_total=matches_total,
                        matches_scanned=matches_scanned,
                        matches_with_lineups=matches_with_lineups,
                        matches_missing_lineups=matches_missing_lineups,
                        matches_failed=matches_failed,
                        persist_service=persist_service,
                    )
                    sync_run.error_message = last_match_error
                    await self.session.commit()
                    sync_run = await self.session.get(SyncRun, sync_run_id)

                if sync_run is None:
                    sync_run = await self.session.get(SyncRun, sync_run_id)
                sync_run.status = SyncRunStatus.succeeded
                sync_run.completed_at = datetime.now(UTC)
                sync_run.stats = self._match_lineup_sync_stats(
                    matches_total=matches_total,
                    matches_scanned=matches_scanned,
                    matches_with_lineups=matches_with_lineups,
                    matches_missing_lineups=matches_missing_lineups,
                    matches_failed=matches_failed,
                    persist_service=persist_service,
                )
                sync_run.error_message = last_match_error
                await self.session.commit()
                await self.session.refresh(sync_run)
                logger.info(
                    "sync match-lineups succeeded provider=%s target_date=%s stats=%s last_error=%s",
                    provider_slug,
                    target_date.isoformat(),
                    sync_run.stats,
                    last_match_error,
                )
                await self._emit_progress(
                    progress_callback,
                    message=f"Match lineup sync completed. stats={sync_run.stats}",
                    stats=sync_run.stats,
                    sync_run_id=sync_run.id,
                )

                summary_bits: list[str] = []
                if matches_missing_lineups:
                    summary_bits.append(f"skipped {matches_missing_lineups} missing lineups")
                if matches_failed:
                    summary_bits.append(f"{matches_failed} matches failed")

                return SyncTriggerResponse(
                    accepted=True,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=sync_run.id,
                    status=sync_run.status,
                    queued_at=sync_run.started_at,
                    stats=sync_run.stats,
                    message=(
                        "Match lineup sync completed."
                        if not summary_bits
                        else f"Match lineup sync completed: {', '.join(summary_bits)}."
                    ),
                )
            except Exception as exc:
                logger.exception(
                    "sync match-lineups failed provider=%s target_date=%s timezone=%s error_code=%s error=%s",
                    provider_slug,
                    target_date.isoformat() if target_date is not None else None,
                    timezone_name,
                    self._extract_error_code(exc),
                    exc,
                )
                await self.session.rollback()
                recovered_provider = await self._get_or_create_provider(
                    provider_slug=provider_slug,
                    client=client,
                )

                failed_sync_run = SyncRun(
                    provider_id=recovered_provider.id,
                    scope=scope,
                    target_date=target_date,
                    status=SyncRunStatus.failed,
                    started_at=sync_started_at,
                    completed_at=datetime.now(UTC),
                    error_message=str(exc),
                )
                self.session.add(failed_sync_run)
                await self.session.commit()
                await self.session.refresh(failed_sync_run)
                await self._emit_progress(
                    progress_callback,
                    message=f"Match lineup sync failed: {exc}",
                    error=str(exc),
                    status_code=self._extract_error_code(exc),
                    sync_run_id=failed_sync_run.id,
                )

                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=failed_sync_run.id,
                    status=failed_sync_run.status,
                    queued_at=failed_sync_run.started_at,
                    error_code=self._extract_error_code(exc),
                    message=f"Match lineup sync failed: {exc}",
                )

        await self.session.commit()
        await self.session.refresh(sync_run)

        return SyncTriggerResponse(
            accepted=True,
            provider_slug=provider_slug,
            scope=scope,
            target_date=target_date,
            sync_run_id=sync_run.id,
            status=sync_run.status,
            queued_at=sync_run.started_at,
            message=(
                "Sync run queued. Next step is implementing provider fetch, raw payload capture, "
                "canonical normalization, and relation generation."
            ),
        )

    def _build_provider_client(self, provider_slug: str, *, settings, progress_callback=None):
        client_cls = REGISTERED_PROVIDER_CLIENTS.get(provider_slug)
        if client_cls is None:
            raise ValueError(f"Unsupported provider: {provider_slug}")
        client = client_cls(settings=settings)
        if progress_callback is not None:
            client.progress_reporter = progress_callback
        return client

    async def _trigger_hybrid_match_lineup_sync(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun,
        target_date: date | None,
        timezone_name: str | None,
        progress_callback,
        sync_run_id,
        sync_started_at: datetime,
        settings,
    ) -> SyncTriggerResponse:
        source_clients = {}

        try:
            source_clients = {
                slug: self._build_provider_client(
                    slug,
                    settings=settings,
                    progress_callback=progress_callback,
                )
                for slug in HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS
            }
            if target_date is None:
                raise ValueError("target_date is required for match-lineups.")

            await self._emit_progress(
                progress_callback,
                message=(
                    "Hybrid match lineup sync will try "
                    f"{HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS[0]} first and fall back to "
                    f"{HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS[1]}."
                ),
                sync_run_id=sync_run.id,
            )
            match_mappings = await self._get_provider_match_mappings_for_provider_slugs(
                provider_slugs=(
                    HYBRID_LINEUP_PROVIDER_SLUG,
                    *HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS,
                ),
                target_date=target_date,
                timezone_name=timezone_name,
            )
            if not match_mappings:
                logger.warning(
                    "sync hybrid match-lineups aborted provider=%s target_date=%s timezone=%s reason=no_mapped_matches",
                    provider.slug,
                    target_date.isoformat(),
                    timezone_name,
                )
                sync_run.status = SyncRunStatus.failed
                sync_run.completed_at = datetime.now(UTC)
                sync_run.error_message = (
                    "No mapped matches found for SportsAPI Pro or Sofascore on this date. "
                    "Run match sync first."
                )
                await self.session.commit()
                await self.session.refresh(sync_run)
                await self._emit_progress(
                    progress_callback,
                    message=(
                        "Hybrid match lineup sync failed: no SportsAPI Pro or Sofascore "
                        "match mappings were found for this date."
                    ),
                    sync_run_id=sync_run.id,
                )
                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider.slug,
                    scope="match-lineups",
                    target_date=target_date,
                    sync_run_id=sync_run.id,
                    status=sync_run.status,
                    queued_at=sync_run.started_at,
                    message=(
                        "Hybrid match lineup sync failed: no SportsAPI Pro or Sofascore "
                        "match mappings found. Run match sync first."
                    ),
                )

            persist_service = MatchLineupPersistenceService(self.session)
            matches_total = len(match_mappings)
            matches_scanned = 0
            matches_with_lineups = 0
            matches_missing_lineups = 0
            matches_failed = 0
            last_match_error: str | None = None

            sync_run.status = SyncRunStatus.running
            sync_run.stats = self._match_lineup_sync_stats(
                matches_total=matches_total,
                matches_scanned=matches_scanned,
                matches_with_lineups=matches_with_lineups,
                matches_missing_lineups=matches_missing_lineups,
                matches_failed=matches_failed,
                persist_service=persist_service,
            )
            await self.session.commit()
            sync_run = await self.session.get(SyncRun, sync_run_id)
            await self._emit_progress(
                progress_callback,
                message=f"Hybrid match lineup sync scanning started. matches_total={matches_total}",
                stats=sync_run.stats,
                sync_run_id=sync_run.id,
            )

            for match_record, mapped_provider_match_ids in match_mappings:
                matches_scanned += 1
                source_match_ids = self._resolve_hybrid_source_match_ids(
                    mapped_provider_match_ids
                )
                attempted_sources: list[tuple[str, str]] = []
                source_errors: list[tuple[str, str, Exception]] = []
                resolved_lineup = None
                resolved_source_slug: str | None = None
                resolved_source_match_id: str | None = None

                for source_slug in HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS:
                    source_match_id, implicit_source_match_id = (
                        await self._resolve_hybrid_source_match_id_for_attempt(
                            match=match_record,
                            source_slug=source_slug,
                            source_match_ids=source_match_ids,
                            source_client=source_clients[source_slug],
                        )
                    )
                    if source_match_id is None:
                        continue

                    if attempted_sources:
                        previous_slug, previous_match_id = attempted_sources[-1]
                        await self._emit_progress(
                            progress_callback,
                            message=(
                                "Hybrid fallback for "
                                f"{match_record.id}: {previous_slug} "
                                f"did not return a usable lineup for {previous_match_id}; "
                                f"trying {source_slug} {source_match_id}."
                            ),
                            sync_run_id=sync_run.id,
                        )
                    elif implicit_source_match_id:
                        await self._emit_progress(
                            progress_callback,
                            message=(
                                f"No explicit {source_slug} mapping for {match_record.id}. "
                                f"Validated implicit match id {source_match_id} via event endpoint."
                            ),
                            sync_run_id=sync_run.id,
                        )

                    attempted_sources.append((source_slug, source_match_id))
                    try:
                        lineup = await source_clients[source_slug].get_match_lineup(
                            source_match_id
                        )
                    except Exception as exc:
                        error_code = self._extract_error_code(exc)
                        if error_code == 404:
                            await self._emit_progress(
                                progress_callback,
                                message=(
                                    f"{source_slug} returned 404 for lineup {source_match_id}. "
                                    "Trying next source if available."
                                ),
                                status_code=error_code,
                                sync_run_id=sync_run.id,
                            )
                            continue

                        source_errors.append((source_slug, source_match_id, exc))
                        await self._emit_progress(
                            progress_callback,
                            message=(
                                f"{source_slug} failed for lineup {source_match_id}: {exc}. "
                                "Trying next source if available."
                            ),
                            error=str(exc),
                            status_code=error_code,
                            sync_run_id=sync_run.id,
                        )
                        continue

                    if lineup is None:
                        await self._emit_progress(
                            progress_callback,
                            message=(
                                f"{source_slug} reported no lineup for {source_match_id}. "
                                "Trying next source if available."
                            ),
                            sync_run_id=sync_run.id,
                        )
                        continue

                    if self._should_fallback_from_hybrid_lineup(
                        match=match_record,
                        source_slug=source_slug,
                        lineup=lineup,
                    ):
                        listed_players, played_players, minutes_players = (
                            self._lineup_played_summary(lineup)
                        )
                        await self._emit_progress(
                            progress_callback,
                            message=(
                                f"{source_slug} returned a low-quality lineup for "
                                f"{source_match_id} on a completed/in-progress match "
                                f"(listed={listed_players}, played={played_players}, "
                                f"minutes>0={minutes_players}). Trying next source if available."
                            ),
                            sync_run_id=sync_run.id,
                        )
                        continue

                    resolved_lineup = lineup
                    resolved_source_slug = source_slug
                    resolved_source_match_id = source_match_id
                    break

                if resolved_lineup is not None and resolved_source_slug is not None:
                    await persist_service.persist_match_lineup(
                        provider=provider,
                        sync_run=sync_run,
                        match=match_record,
                        lineup=resolved_lineup,
                        source_provider_slug=resolved_source_slug,
                        source_provider_match_id=resolved_source_match_id,
                    )
                    matches_with_lineups += 1
                    logger.info(
                        "sync hybrid match-lineups match succeeded provider=%s source_provider=%s provider_match_id=%s match_id=%s home_players=%s away_players=%s",
                        provider.slug,
                        resolved_source_slug,
                        resolved_source_match_id,
                        match_record.id,
                        len(resolved_lineup.home_players),
                        len(resolved_lineup.away_players),
                    )
                    if resolved_source_slug != HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS[0]:
                        await self._emit_progress(
                            progress_callback,
                            message=(
                                "Hybrid fallback succeeded for "
                                f"{match_record.id}: lineup came from "
                                f"{resolved_source_slug} {resolved_source_match_id}."
                            ),
                            sync_run_id=sync_run.id,
                        )
                elif source_errors:
                    matches_failed += 1
                    failed_source_slug, failed_source_match_id, failed_exc = source_errors[-1]
                    last_match_error = (
                        f"Match {failed_source_match_id} failed after hybrid fallback: "
                        f"{failed_exc}"
                    )
                    logger.warning(
                        "sync hybrid match-lineups match failed provider=%s source_provider=%s provider_match_id=%s match_id=%s error_code=%s error=%s",
                        provider.slug,
                        failed_source_slug,
                        failed_source_match_id,
                        match_record.id,
                        self._extract_error_code(failed_exc),
                        failed_exc,
                    )
                else:
                    matches_missing_lineups += 1
                    missing_source_slug = attempted_sources[-1][0] if attempted_sources else None
                    missing_source_match_id = (
                        attempted_sources[-1][1] if attempted_sources else None
                    )
                    await persist_service.persist_missing_match_lineup(
                        provider=provider,
                        sync_run=sync_run,
                        match=match_record,
                        provider_match_id=missing_source_match_id or "",
                        source_provider_slug=missing_source_slug,
                        source_provider_match_id=missing_source_match_id,
                    )

                sync_run.status = SyncRunStatus.running
                sync_run.stats = self._match_lineup_sync_stats(
                    matches_total=matches_total,
                    matches_scanned=matches_scanned,
                    matches_with_lineups=matches_with_lineups,
                    matches_missing_lineups=matches_missing_lineups,
                    matches_failed=matches_failed,
                    persist_service=persist_service,
                )
                sync_run.error_message = last_match_error
                await self.session.commit()
                sync_run = await self.session.get(SyncRun, sync_run_id)

            if sync_run is None:
                sync_run = await self.session.get(SyncRun, sync_run_id)
            sync_run.status = SyncRunStatus.succeeded
            sync_run.completed_at = datetime.now(UTC)
            sync_run.stats = self._match_lineup_sync_stats(
                matches_total=matches_total,
                matches_scanned=matches_scanned,
                matches_with_lineups=matches_with_lineups,
                matches_missing_lineups=matches_missing_lineups,
                matches_failed=matches_failed,
                persist_service=persist_service,
            )
            sync_run.error_message = last_match_error
            await self.session.commit()
            await self.session.refresh(sync_run)
            await self._emit_progress(
                progress_callback,
                message=f"Hybrid match lineup sync completed. stats={sync_run.stats}",
                stats=sync_run.stats,
                sync_run_id=sync_run.id,
            )
            return SyncTriggerResponse(
                accepted=True,
                provider_slug=provider.slug,
                scope="match-lineups",
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=sync_run.status,
                queued_at=sync_run.started_at,
                stats=sync_run.stats,
                message=self._match_lineup_summary_message(
                    matches_missing_lineups=matches_missing_lineups,
                    matches_failed=matches_failed,
                ),
            )
        except Exception as exc:
            logger.exception(
                "sync hybrid match-lineups failed provider=%s target_date=%s timezone=%s error_code=%s error=%s",
                provider.slug,
                target_date.isoformat() if target_date is not None else None,
                timezone_name,
                self._extract_error_code(exc),
                exc,
            )
            await self.session.rollback()
            recovered_provider = await self._get_or_create_provider(
                provider_slug=provider.slug,
                client=None,
                provider_name=HYBRID_LINEUP_PROVIDER_NAME,
            )

            failed_sync_run = SyncRun(
                provider_id=recovered_provider.id,
                scope="match-lineups",
                target_date=target_date,
                status=SyncRunStatus.failed,
                started_at=sync_started_at,
                completed_at=datetime.now(UTC),
                error_message=str(exc),
            )
            self.session.add(failed_sync_run)
            await self.session.commit()
            await self.session.refresh(failed_sync_run)
            await self._emit_progress(
                progress_callback,
                message=f"Hybrid match lineup sync failed: {exc}",
                error=str(exc),
                status_code=self._extract_error_code(exc),
                sync_run_id=failed_sync_run.id,
            )

            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider.slug,
                scope="match-lineups",
                target_date=target_date,
                sync_run_id=failed_sync_run.id,
                status=failed_sync_run.status,
                queued_at=failed_sync_run.started_at,
                error_code=self._extract_error_code(exc),
                message=f"Hybrid match lineup sync failed: {exc}",
            )
        finally:
            for source_client in source_clients.values():
                try:
                    await source_client.aclose()
                except Exception:
                    logger.warning(
                        "hybrid match-lineups client close failed provider=%s",
                        getattr(source_client, "slug", type(source_client).__name__),
                    )

    async def _get_provider_match_mappings_for_provider_slugs(
        self,
        *,
        provider_slugs: tuple[str, ...],
        target_date: date,
        timezone_name: str | None,
    ) -> list[tuple[Match, dict[str, str]]]:
        start_of_day_local, end_of_day_local = utc_day_bounds(target_date, timezone_name)
        result = await self.session.execute(
            select(Match, Provider.slug, ProviderEntityMapping.provider_entity_id)
            .options(
                selectinload(Match.home_team),
                selectinload(Match.away_team),
                selectinload(Match.season),
            )
            .join(
                ProviderEntityMapping,
                ProviderEntityMapping.canonical_entity_uid == Match.entity_uid,
            )
            .join(Provider, Provider.id == ProviderEntityMapping.provider_id)
            .where(
                Provider.slug.in_(provider_slugs),
                ProviderEntityMapping.entity_type == EntityType.match,
                Match.kickoff_at >= start_of_day_local,
                Match.kickoff_at < end_of_day_local,
            )
            .order_by(Match.kickoff_at.asc())
        )

        grouped: dict[object, dict[str, object]] = {}
        for match, mapped_provider_slug, provider_match_id in result.unique().all():
            entry = grouped.setdefault(
                match.id,
                {
                    "match": match,
                    "provider_match_ids": {},
                },
            )
            entry["provider_match_ids"][str(mapped_provider_slug)] = str(provider_match_id)

        return [
            (entry["match"], entry["provider_match_ids"])
            for entry in grouped.values()
        ]

    @staticmethod
    def _resolve_hybrid_source_match_ids(provider_match_ids: dict[str, str]) -> dict[str, str]:
        resolved: dict[str, str] = {}
        primary_provider_slug, secondary_provider_slug = HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS

        primary_match_id = provider_match_ids.get(primary_provider_slug) or provider_match_ids.get(
            HYBRID_LINEUP_PROVIDER_SLUG
        )
        if primary_match_id is not None:
            resolved[primary_provider_slug] = primary_match_id

        secondary_match_id = provider_match_ids.get(secondary_provider_slug)
        if secondary_match_id is not None:
            resolved[secondary_provider_slug] = secondary_match_id

        return resolved

    async def _resolve_hybrid_source_match_id_for_attempt(
        self,
        *,
        match: Match,
        source_slug: str,
        source_match_ids: dict[str, str],
        source_client,
    ) -> tuple[str | None, bool]:
        explicit_match_id = source_match_ids.get(source_slug)
        if explicit_match_id is not None:
            return explicit_match_id, False

        primary_provider_slug, secondary_provider_slug = HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS
        if source_slug != secondary_provider_slug:
            return None, False

        primary_match_id = source_match_ids.get(primary_provider_slug)
        if primary_match_id is None:
            return None, False

        match_event_fetcher = getattr(source_client, "get_match_event", None)
        if not callable(match_event_fetcher):
            return None, False

        event_payload = await match_event_fetcher(primary_match_id)
        if not self._sofascore_event_matches_match(match=match, event_payload=event_payload):
            return None, False

        return primary_match_id, True

    @staticmethod
    def _match_lineup_summary_message(
        *,
        matches_missing_lineups: int,
        matches_failed: int,
    ) -> str:
        summary_bits: list[str] = []
        if matches_missing_lineups:
            summary_bits.append(f"skipped {matches_missing_lineups} missing lineups")
        if matches_failed:
            summary_bits.append(f"{matches_failed} matches failed")
        if not summary_bits:
            return "Match lineup sync completed."
        return f"Match lineup sync completed: {', '.join(summary_bits)}."

    @staticmethod
    def _normalize_hybrid_match_text(value: object) -> str:
        return " ".join(str(value or "").strip().casefold().split())

    @classmethod
    def _sofascore_event_matches_match(cls, *, match: Match, event_payload: dict | None) -> bool:
        if not isinstance(event_payload, dict):
            return False

        event = event_payload.get("event") if isinstance(event_payload.get("event"), dict) else event_payload
        if not isinstance(event, dict):
            return False

        home_payload = event.get("homeTeam") if isinstance(event.get("homeTeam"), dict) else {}
        away_payload = event.get("awayTeam") if isinstance(event.get("awayTeam"), dict) else {}

        expected_home_name = cls._normalize_hybrid_match_text(getattr(match.home_team, "name", ""))
        expected_away_name = cls._normalize_hybrid_match_text(getattr(match.away_team, "name", ""))
        actual_home_name = cls._normalize_hybrid_match_text(home_payload.get("name"))
        actual_away_name = cls._normalize_hybrid_match_text(away_payload.get("name"))
        if not expected_home_name or not expected_away_name:
            return False
        if actual_home_name != expected_home_name or actual_away_name != expected_away_name:
            return False

        metadata = getattr(match, "metadata_json", {}) or {}
        raw_payload = metadata.get("raw") if isinstance(metadata, dict) else None
        if isinstance(raw_payload, dict):
            raw_home = raw_payload.get("homeTeam") if isinstance(raw_payload.get("homeTeam"), dict) else {}
            raw_away = raw_payload.get("awayTeam") if isinstance(raw_payload.get("awayTeam"), dict) else {}
            raw_home_id = raw_home.get("id")
            raw_away_id = raw_away.get("id")
            event_home_id = home_payload.get("id")
            event_away_id = away_payload.get("id")
            if raw_home_id is not None and event_home_id is not None and str(raw_home_id) != str(event_home_id):
                return False
            if raw_away_id is not None and event_away_id is not None and str(raw_away_id) != str(event_away_id):
                return False

            raw_start = raw_payload.get("startTimestamp")
            event_start = event.get("startTimestamp")
            if raw_start is not None and event_start is not None and str(raw_start) != str(event_start):
                return False

        return True

    @staticmethod
    def _lineup_played_summary(lineup) -> tuple[int, int, int]:
        entries = [
            *getattr(lineup, "home_players", []),
            *getattr(lineup, "away_players", []),
        ]
        listed_players = len(entries)
        played_players = sum(1 for entry in entries if bool(getattr(entry, "played", False)))
        minutes_players = sum(
            1 for entry in entries if (getattr(entry, "minutes_played", None) or 0) > 0
        )
        return listed_players, played_players, minutes_players

    @staticmethod
    def _should_fallback_from_hybrid_lineup(
        *,
        match: Match,
        source_slug: str,
        lineup,
    ) -> bool:
        if source_slug != HYBRID_LINEUP_SOURCE_PROVIDER_SLUGS[0]:
            return False

        listed_players, played_players, minutes_players = SyncService._lineup_played_summary(
            lineup
        )
        if listed_players == 0:
            return True
        if not SyncService._match_should_have_played_data(match):
            return False
        return played_players == 0 and minutes_players == 0

    @staticmethod
    def _match_should_have_played_data(match: Match) -> bool:
        status = getattr(match, "status", None)
        status_value = getattr(status, "value", status)
        if status_value in {"live", "finished"}:
            return True
        if status_value in {"postponed", "cancelled"}:
            return False

        kickoff_at = getattr(match, "kickoff_at", None)
        if not isinstance(kickoff_at, datetime):
            return False
        if kickoff_at.tzinfo is None:
            kickoff_at = kickoff_at.replace(tzinfo=UTC)

        # Schedule status can stay stale after kickoff; past-due fixtures should not keep
        # a zero-played primary lineup when a fallback source may have the real participation data.
        return kickoff_at <= datetime.now(UTC) - timedelta(hours=2)

    async def _trigger_match_context_sync(
        self,
        *,
        provider: Provider,
        client,
        scope: str,
        sync_run: SyncRun,
        target_date: date | None,
        timezone_name: str | None,
        progress_callback,
        sync_started_at: datetime,
    ) -> SyncTriggerResponse:
        provider_slug = provider.slug
        provider_id = provider.id
        sync_run_id = sync_run.id
        if target_date is None:
            sync_run.status = SyncRunStatus.failed
            sync_run.completed_at = datetime.now(UTC)
            sync_run.error_message = "target_date is required."
            await self.session.commit()
            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=sync_run.status,
                queued_at=sync_run.started_at,
                message=f"{scope} failed: target_date is required.",
            )

        required_methods = (
            ("market-backfill", ("get_prematch_markets", "get_live_markets")),
            ("context-backfill", ("get_match_incidents", "get_match_live_stats", "get_match_shotmap")),
        )[0 if scope == "market-backfill" else 1][1]
        for method_name in required_methods:
            if getattr(client.__class__, method_name) is getattr(ProviderClient, method_name):
                sync_run.status = SyncRunStatus.failed
                sync_run.completed_at = datetime.now(UTC)
                sync_run.error_message = f"This provider does not implement {method_name}."
                await self.session.commit()
                return SyncTriggerResponse(
                    accepted=False,
                    provider_slug=provider_slug,
                    scope=scope,
                    target_date=target_date,
                    sync_run_id=sync_run.id,
                    status=sync_run.status,
                    queued_at=sync_run.started_at,
                    message=f"{scope} failed: provider method {method_name} is missing.",
                )

        try:
            batch = await client.fetch(scope=scope, target_date=target_date)
            match_persist_stats = await MatchPersistenceService(self.session).persist_batch(
                provider=provider,
                sync_run=sync_run,
                batch=batch,
            )
            match_mappings = await self._get_provider_match_mappings(
                provider=provider,
                target_date=target_date,
                timezone_name=timezone_name,
            )
            persist_service = MatchContextPersistenceService(self.session)
            matches_total = len(match_mappings)
            matches_scanned = 0
            matches_synced = 0
            matches_failed = 0

            sync_run.status = SyncRunStatus.running
            sync_run.stats = {
                "matches_total": matches_total,
                "matches_scanned": 0,
                "matches_synced": 0,
                "matches_failed": 0,
            }
            await self.session.commit()
            await self._emit_progress(
                progress_callback,
                message=f"{scope} scanning started. matches_total={matches_total}",
                stats=sync_run.stats,
                sync_run_id=sync_run.id,
            )

            for match, provider_match_id in match_mappings:
                matches_scanned += 1
                match_record = await self._get_match_for_lineup_sync(match.id)
                if match_record is None:
                    matches_failed += 1
                    continue
                try:
                    if scope == "market-backfill":
                        prematch_ticks = await client.get_prematch_markets(provider_match_id)
                        live_ticks = await client.get_live_markets(provider_match_id)
                        await persist_service.persist_markets(
                            provider=provider,
                            sync_run=sync_run,
                            match=match_record,
                            provider_match_id=provider_match_id,
                            prematch_ticks=prematch_ticks,
                            live_ticks=live_ticks,
                        )
                    else:
                        incidents = await client.get_match_incidents(provider_match_id)
                        live_frames = await client.get_match_live_stats(provider_match_id)
                        shots = await client.get_match_shotmap(provider_match_id)
                        await persist_service.persist_context(
                            provider=provider,
                            sync_run=sync_run,
                            match=match_record,
                            provider_match_id=provider_match_id,
                            incidents=incidents,
                            live_frames=live_frames,
                            shots=shots,
                        )
                    matches_synced += 1
                except Exception as exc:
                    await self.session.rollback()
                    logger.warning(
                        "sync %s match failed provider=%s match_id=%s error=%s",
                        scope,
                        provider_slug,
                        provider_match_id,
                        exc,
                    )
                    matches_failed += 1

                sync_run = await self.session.get(SyncRun, sync_run_id)
                if sync_run is None:
                    raise RuntimeError("Sync run disappeared during match context sync.")
                sync_run.status = SyncRunStatus.running
                sync_run.stats = {
                    "matches_total": matches_total,
                    "matches_scanned": matches_scanned,
                    "matches_synced": matches_synced,
                    "matches_failed": matches_failed,
                    **match_persist_stats,
                    **persist_service.stats.to_dict(),
                }
                await self.session.commit()

            sync_run = await self.session.get(SyncRun, sync_run_id)
            if sync_run is None:
                raise RuntimeError("Sync run disappeared before match context sync completion.")
            sync_run.status = SyncRunStatus.succeeded
            sync_run.completed_at = datetime.now(UTC)
            sync_run.stats = {
                "matches_total": matches_total,
                "matches_scanned": matches_scanned,
                "matches_synced": matches_synced,
                "matches_failed": matches_failed,
                **match_persist_stats,
                **persist_service.stats.to_dict(),
            }
            await self.session.commit()
            await self.session.refresh(sync_run)
            await self._emit_progress(
                progress_callback,
                message=f"{scope} completed. stats={sync_run.stats}",
                stats=sync_run.stats,
                sync_run_id=sync_run.id,
            )
            return SyncTriggerResponse(
                accepted=True,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=sync_run.status,
                queued_at=sync_run.started_at,
                stats=sync_run.stats,
                message=f"{scope} completed.",
            )
        except Exception as exc:
            logger.exception("sync %s failed provider=%s error=%s", scope, provider_slug, exc)
            await self.session.rollback()
            failed_sync_run = SyncRun(
                provider_id=provider_id,
                scope=scope,
                target_date=target_date,
                status=SyncRunStatus.failed,
                started_at=sync_started_at,
                completed_at=datetime.now(UTC),
                error_message=str(exc),
            )
            self.session.add(failed_sync_run)
            await self.session.commit()
            await self._emit_progress(
                progress_callback,
                message=f"{scope} failed: {exc}",
                error=str(exc),
                status_code=self._extract_error_code(exc),
                sync_run_id=failed_sync_run.id,
            )
            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=failed_sync_run.id,
                status=failed_sync_run.status,
                queued_at=failed_sync_run.started_at,
                error_code=self._extract_error_code(exc),
                message=f"{scope} failed: {exc}",
            )

    async def _trigger_rating_rebuild(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun,
        target_date: date | None,
        progress_callback,
        sync_started_at: datetime,
    ) -> SyncTriggerResponse:
        provider_slug = provider.slug
        provider_id = provider.id
        if target_date is None:
            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope="rating-rebuild",
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=SyncRunStatus.failed,
                queued_at=sync_run.started_at,
                message="rating-rebuild failed: target_date is required.",
            )
        try:
            stats = await FeatureRatingService(self.session).rebuild_for_date(target_date=target_date)
            sync_run.status = SyncRunStatus.succeeded
            sync_run.completed_at = datetime.now(UTC)
            sync_run.stats = stats
            await self.session.commit()
            await self.session.refresh(sync_run)
            await self._emit_progress(
                progress_callback,
                message=f"rating-rebuild completed. stats={stats}",
                stats=stats,
                sync_run_id=sync_run.id,
            )
            return SyncTriggerResponse(
                accepted=True,
                provider_slug=provider_slug,
                scope="rating-rebuild",
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=sync_run.status,
                queued_at=sync_run.started_at,
                stats=stats,
                message="rating-rebuild completed.",
            )
        except Exception as exc:
            logger.exception("rating-rebuild failed provider=%s error=%s", provider_slug, exc)
            await self.session.rollback()
            failed_sync_run = SyncRun(
                provider_id=provider_id,
                scope="rating-rebuild",
                target_date=target_date,
                status=SyncRunStatus.failed,
                started_at=sync_started_at,
                completed_at=datetime.now(UTC),
                error_message=str(exc),
            )
            self.session.add(failed_sync_run)
            await self.session.commit()
            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope="rating-rebuild",
                target_date=target_date,
                sync_run_id=failed_sync_run.id,
                status=failed_sync_run.status,
                queued_at=failed_sync_run.started_at,
                error_code=self._extract_error_code(exc),
                message=f"rating-rebuild failed: {exc}",
            )

    async def _trigger_snapshot_materialization(
        self,
        *,
        provider: Provider,
        sync_run: SyncRun,
        target_date: date | None,
        timezone_name: str | None,
        progress_callback,
        sync_started_at: datetime,
        scope: str,
    ) -> SyncTriggerResponse:
        provider_slug = provider.slug
        provider_id = provider.id
        if target_date is None:
            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=SyncRunStatus.failed,
                queued_at=sync_run.started_at,
                message=f"{scope} failed: target_date is required.",
            )
        try:
            stats = await MatchFeatureSnapshotService(self.session).materialize_for_date(
                target_date=target_date,
                timezone_name=timezone_name,
            )
            sync_run.status = SyncRunStatus.succeeded
            sync_run.completed_at = datetime.now(UTC)
            sync_run.stats = stats
            await self.session.commit()
            await self.session.refresh(sync_run)
            await self._emit_progress(
                progress_callback,
                message=f"{scope} completed. stats={stats}",
                stats=stats,
                sync_run_id=sync_run.id,
            )
            return SyncTriggerResponse(
                accepted=True,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=sync_run.id,
                status=sync_run.status,
                queued_at=sync_run.started_at,
                stats=stats,
                message=f"{scope} completed.",
            )
        except Exception as exc:
            logger.exception("%s failed provider=%s error=%s", scope, provider_slug, exc)
            await self.session.rollback()
            failed_sync_run = SyncRun(
                provider_id=provider_id,
                scope=scope,
                target_date=target_date,
                status=SyncRunStatus.failed,
                started_at=sync_started_at,
                completed_at=datetime.now(UTC),
                error_message=str(exc),
            )
            self.session.add(failed_sync_run)
            await self.session.commit()
            return SyncTriggerResponse(
                accepted=False,
                provider_slug=provider_slug,
                scope=scope,
                target_date=target_date,
                sync_run_id=failed_sync_run.id,
                status=failed_sync_run.status,
                queued_at=failed_sync_run.started_at,
                error_code=self._extract_error_code(exc),
                message=f"{scope} failed: {exc}",
            )

    async def _build_stage_catalog(
        self,
        *,
        client,
        scope: str,
        category_id: str | None,
        tournament_id: str | None,
    ) -> ProviderBootstrapCatalog:
        catalog = ProviderBootstrapCatalog()

        if scope == "bootstrap-countries":
            catalog.categories.extend(await client.get_extended_categories())
            return catalog

        if scope == "bootstrap-tournaments":
            if category_id:
                catalog.tournaments.extend(await client.get_category_tournaments(category_id))
            else:
                catalog.tournaments.extend(await client.get_all_tournaments())
            return catalog

        if scope == "bootstrap-seasons":
            if not tournament_id:
                raise ValueError("tournament_id is required for bootstrap-seasons.")
            catalog.seasons.extend(await client.get_tournament_seasons(tournament_id))
            return catalog

        raise ValueError(f"Unsupported bootstrap scope: {scope}")

    async def _get_provider(self, provider_slug: str) -> Provider | None:
        result = await self.session.execute(select(Provider).where(Provider.slug == provider_slug))
        return result.scalar_one_or_none()

    async def _get_or_create_provider(
        self,
        *,
        provider_slug: str,
        client,
        provider_name: str | None = None,
        base_url: str | None = None,
    ) -> Provider:
        provider = await self._get_provider(provider_slug)
        if provider is not None:
            return provider

        provider = Provider(
            slug=provider_slug,
            name=provider_name or getattr(client, "display_name", provider_slug),
            base_url=base_url if base_url is not None else getattr(client, "base_url", None),
        )
        self.session.add(provider)
        await self.session.flush()
        return provider

    async def _get_provider_team_mappings(
        self,
        *,
        provider: Provider,
    ) -> list[tuple[Team, str]]:
        result = await self.session.execute(
            select(Team, ProviderEntityMapping.provider_entity_id)
            .join(ProviderEntityMapping, ProviderEntityMapping.canonical_entity_uid == Team.entity_uid)
            .where(
                ProviderEntityMapping.provider_id == provider.id,
                ProviderEntityMapping.entity_type == EntityType.team,
            )
            .order_by(Team.name.asc())
        )
        return list(result.all())

    async def _get_provider_match_mappings(
        self,
        *,
        provider: Provider,
        target_date: date,
        timezone_name: str | None,
    ) -> list[tuple[Match, str]]:
        start_of_day_local, end_of_day_local = utc_day_bounds(target_date, timezone_name)
        result = await self.session.execute(
            select(Match, ProviderEntityMapping.provider_entity_id)
            .join(
                ProviderEntityMapping,
                ProviderEntityMapping.canonical_entity_uid == Match.entity_uid,
            )
            .where(
                ProviderEntityMapping.provider_id == provider.id,
                ProviderEntityMapping.entity_type == EntityType.match,
                Match.kickoff_at >= start_of_day_local,
                Match.kickoff_at < end_of_day_local,
            )
            .order_by(Match.kickoff_at.asc())
        )
        return list(result.all())

    async def _get_match_for_lineup_sync(self, match_id) -> Match | None:
        result = await self.session.execute(
            select(Match)
            .options(
                selectinload(Match.home_team),
                selectinload(Match.away_team),
                selectinload(Match.season),
            )
            .where(Match.id == match_id)
        )
        return result.scalars().unique().one_or_none()

    @staticmethod
    def _player_sync_stats(
        *,
        teams_total_mapped: int,
        teams_scanned: int,
        teams_synced: int,
        teams_missing_roster: int,
        teams_failed: int,
        total_players_fetched: int,
        persist_service: PlayerPersistenceService,
    ) -> dict[str, int]:
        return {
            "teams_total_mapped": teams_total_mapped,
            "teams_scanned": teams_scanned,
            "teams_synced": teams_synced,
            "teams_missing_roster": teams_missing_roster,
            "teams_failed": teams_failed,
            "players_fetched": total_players_fetched,
            **persist_service.catalog.stats.to_dict(),
            **persist_service.stats.to_dict(),
        }

    @staticmethod
    def _match_lineup_sync_stats(
        *,
        matches_total: int,
        matches_scanned: int,
        matches_with_lineups: int,
        matches_missing_lineups: int,
        matches_failed: int,
        persist_service: MatchLineupPersistenceService,
    ) -> dict[str, int]:
        stats = {
            "matches_total": matches_total,
            "matches_scanned": matches_scanned,
            "matches_with_lineups": matches_with_lineups,
            "matches_missing_lineups": matches_missing_lineups,
            "matches_failed": matches_failed,
        }
        for source in (
            persist_service.player_service.catalog.stats.to_dict(),
            persist_service.player_service.stats.to_dict(),
            persist_service.stats.to_dict(),
        ):
            for key, value in source.items():
                stats[key] = stats.get(key, 0) + value
        return stats

    @staticmethod
    def _extract_error_code(exc: Exception) -> int | None:
        if isinstance(exc, httpx.HTTPStatusError):
            return exc.response.status_code
        status_code = getattr(exc, "status_code", None)
        if isinstance(status_code, int):
            return status_code
        return None

    @staticmethod
    async def _emit_progress(progress_callback, **payload) -> None:
        if progress_callback is None:
            return
        result = progress_callback(payload)
        if inspect.isawaitable(result):
            await result
