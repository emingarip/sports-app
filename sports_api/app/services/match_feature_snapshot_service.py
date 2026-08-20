from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.timezones import utc_day_bounds
from app.db.models.domain import (
    Match,
    MatchEventTimeline,
    MatchFeatureSnapshot,
    MatchLiveStatFrame,
    MatchMarketTick,
    MatchPlayerAppearance,
    MatchStatus,
    PlayerRatingDaily,
    Provider,
    SnapshotPhase,
    TeamMembership,
    TeamRatingDaily,
)
from app.providers.hybrid import expand_lineup_provider_slugs
from app.services.feature_math import (
    implied_probability,
    jaccard_similarity,
    lineup_strength,
    market_state_class,
    mean,
    normalize_probabilities,
    parse_formation,
    renormalized_weighted_sum,
    role_group,
    score_state_class,
    sigmoid,
    stable_bucket,
    standard_deviation,
)

SHOTMARKET_SELECTIONS = ("home", "draw", "away")


@dataclass(slots=True)
class MatchFeatureSnapshotStats:
    snapshots_upserted: int = 0

    def to_dict(self) -> dict[str, int]:
        return {"snapshots_upserted": self.snapshots_upserted}


class MatchFeatureSnapshotService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.settings = get_settings()
        self.feature_version = self.settings.feature_snapshot_version
        self.stats = MatchFeatureSnapshotStats()

    async def list_snapshots(
        self,
        *,
        match_id,
        phase: str | None = None,
        limit: int = 500,
    ) -> list[MatchFeatureSnapshot]:
        stmt = (
            select(MatchFeatureSnapshot)
            .where(MatchFeatureSnapshot.match_id == match_id)
            .order_by(MatchFeatureSnapshot.snapshot_ts.asc())
            .limit(limit)
        )
        if phase:
            stmt = stmt.where(MatchFeatureSnapshot.snapshot_phase == SnapshotPhase(phase))
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def latest_snapshot(self, *, match_id) -> MatchFeatureSnapshot | None:
        result = await self.session.execute(
            select(MatchFeatureSnapshot)
            .where(MatchFeatureSnapshot.match_id == match_id)
            .order_by(MatchFeatureSnapshot.snapshot_ts.desc(), MatchFeatureSnapshot.snapshot_phase.desc())
            .limit(1)
        )
        return result.scalars().first()

    async def materialize_for_date(
        self,
        *,
        target_date: date,
        timezone_name: str | None,
    ) -> dict[str, int]:
        start_of_day, end_of_day = utc_day_bounds(target_date, timezone_name)
        matches = await self._load_matches_for_day(start_of_day=start_of_day, end_of_day=end_of_day)
        model = await self._fit_state_model(before=start_of_day)
        cluster_model = await self._fit_cluster_model(before=start_of_day)
        for match in matches:
            await self._materialize_match(
                match=match,
                target_date=target_date,
                model=model,
                cluster_model=cluster_model,
            )
        return self.stats.to_dict()

    async def _load_matches_for_day(
        self,
        *,
        start_of_day: datetime,
        end_of_day: datetime,
    ) -> list[Match]:
        result = await self.session.execute(
            select(Match)
            .where(Match.kickoff_at >= start_of_day, Match.kickoff_at < end_of_day)
            .order_by(Match.kickoff_at.asc())
        )
        return list(result.scalars().all())

    async def _materialize_match(
        self,
        *,
        match: Match,
        target_date: date,
        model,
        cluster_model,
    ) -> None:
        await self.session.execute(
            delete(MatchFeatureSnapshot).where(
                MatchFeatureSnapshot.match_id == match.id,
                MatchFeatureSnapshot.feature_version == self.feature_version,
            )
        )

        event_rows = await self._load_match_events(match_id=match.id)
        live_frames = await self._load_live_frames(match_id=match.id)
        market_ticks = await self._load_market_ticks(match_id=match.id)
        real_lineups = await self._load_real_lineups(match=match)
        predicted_lineups = await self._predict_lineups(match=match, target_date=target_date)
        team_ratings = await self._load_team_ratings(
            team_ids=[match.home_team_id, match.away_team_id],
            target_date=target_date,
        )
        player_ratings = await self._load_player_ratings(
            player_ids={
                *[appearance.player_id for appearance in real_lineups["home"]],
                *[appearance.player_id for appearance in real_lineups["away"]],
                *predicted_lineups["home_players"],
                *predicted_lineups["away_players"],
            },
            target_date=target_date,
        )

        static_context = self._build_static_context(
            match=match,
            team_ratings=team_ratings,
            player_ratings=player_ratings,
            real_lineups=real_lineups,
            predicted_lineups=predicted_lineups,
            market_ticks=market_ticks,
        )
        max_minute = self._resolve_max_minute(match=match, event_rows=event_rows, live_frames=live_frames)
        previous_live_vectors: list[tuple[datetime, dict[str, float | None]]] = []

        for minute in range(0, max_minute + 1):
            phase = SnapshotPhase.pre if minute == 0 else SnapshotPhase.live
            dynamic_context = self._build_dynamic_context(
                match=match,
                minute=minute,
                event_rows=event_rows,
                live_frames=live_frames,
                market_ticks=market_ticks,
                previous_live_vectors=previous_live_vectors,
            )
            snapshot_payload = self._compose_snapshot_payload(
                match=match,
                phase=phase,
                minute=minute,
                static_context=static_context,
                dynamic_context=dynamic_context,
                model=model,
                cluster_model=cluster_model,
                max_minute=max_minute,
                event_rows=event_rows,
            )
            self.session.add(MatchFeatureSnapshot(**snapshot_payload))
            self.stats.snapshots_upserted += 1
            previous_live_vectors.append(
                (
                    snapshot_payload["snapshot_ts"],
                    {
                        "live_home_prob": snapshot_payload.get("live_home_prob"),
                    },
                )
            )

        finalized_payload = self._compose_snapshot_payload(
            match=match,
            phase=SnapshotPhase.finalized,
            minute=max_minute,
            static_context=static_context,
            dynamic_context=self._build_dynamic_context(
                match=match,
                minute=max_minute,
                event_rows=event_rows,
                live_frames=live_frames,
                market_ticks=market_ticks,
                previous_live_vectors=previous_live_vectors,
            ),
            model=model,
            cluster_model=cluster_model,
            max_minute=max_minute,
            event_rows=event_rows,
        )
        finalized_payload["is_finalized"] = True
        self.session.add(MatchFeatureSnapshot(**finalized_payload))
        self.stats.snapshots_upserted += 1
        await self.session.flush()

    async def _load_match_events(self, *, match_id) -> list[MatchEventTimeline]:
        result = await self.session.execute(
            select(MatchEventTimeline)
            .where(MatchEventTimeline.match_id == match_id)
            .order_by(MatchEventTimeline.minute.asc(), MatchEventTimeline.sort_order.asc())
        )
        return list(result.scalars().all())

    async def _load_live_frames(self, *, match_id) -> list[MatchLiveStatFrame]:
        result = await self.session.execute(
            select(MatchLiveStatFrame)
            .where(MatchLiveStatFrame.match_id == match_id)
            .order_by(MatchLiveStatFrame.tick_time.asc())
        )
        return list(result.scalars().all())

    async def _load_market_ticks(self, *, match_id) -> list[MatchMarketTick]:
        result = await self.session.execute(
            select(MatchMarketTick)
            .where(MatchMarketTick.match_id == match_id)
            .order_by(MatchMarketTick.tick_time.asc())
        )
        return list(result.scalars().all())

    async def _load_real_lineups(self, *, match: Match) -> dict[str, list[MatchPlayerAppearance]]:
        metadata = match.metadata_json if isinstance(match.metadata_json, dict) else {}
        lineup_metadata = metadata.get("lineup") if isinstance(metadata.get("lineup"), dict) else {}
        provider_slug = lineup_metadata.get("provider_slug")
        allowed_slugs = set(expand_lineup_provider_slugs(provider_slug)) if provider_slug else set()

        result = await self.session.execute(
            select(MatchPlayerAppearance, Provider.slug)
            .join(Provider, Provider.id == MatchPlayerAppearance.provider_id)
            .where(MatchPlayerAppearance.match_id == match.id)
            .order_by(MatchPlayerAppearance.updated_at.desc())
        )
        grouped: dict[str, dict[str, list[MatchPlayerAppearance]]] = defaultdict(lambda: {"home": [], "away": []})
        for appearance, slug in result.all():
            if allowed_slugs and slug not in allowed_slugs:
                continue
            grouped[str(slug)][appearance.side].append(appearance)

        if not grouped:
            return {"home": [], "away": []}

        preferred_slug = provider_slug if provider_slug in grouped else None
        if preferred_slug is None:
            preferred_slug = max(
                grouped.items(),
                key=lambda item: len(item[1]["home"]) + len(item[1]["away"]),
            )[0]
        selected = grouped[preferred_slug]
        return {
            "home": [item for item in selected["home"] if item.is_starter],
            "away": [item for item in selected["away"] if item.is_starter],
        }

    async def _predict_lineups(self, *, match: Match, target_date: date) -> dict[str, object]:
        home = await self._predict_team_lineup(
            team_id=match.home_team_id,
            kickoff_at=match.kickoff_at,
            side="home",
            target_date=target_date,
        )
        away = await self._predict_team_lineup(
            team_id=match.away_team_id,
            kickoff_at=match.kickoff_at,
            side="away",
            target_date=target_date,
        )
        return {
            "home_players": set(home["player_ids"]),
            "away_players": set(away["player_ids"]),
            "home_roles": home["roles"],
            "away_roles": away["roles"],
            "home_formation": home["formation"],
            "away_formation": away["formation"],
            "home_low_history": home["low_history"],
            "away_low_history": away["low_history"],
        }

    async def _predict_team_lineup(
        self,
        *,
        team_id,
        kickoff_at: datetime,
        side: str,
        target_date: date,
    ) -> dict[str, object]:
        recent_match_result = await self.session.execute(
            select(Match)
            .where(
                or_(Match.home_team_id == team_id, Match.away_team_id == team_id),
                Match.kickoff_at < kickoff_at,
            )
            .order_by(Match.kickoff_at.desc())
            .limit(5)
        )
        recent_matches = list(recent_match_result.scalars().all())
        match_ids = [match.id for match in recent_matches]
        appearances: list[MatchPlayerAppearance] = []
        if match_ids:
            appearance_result = await self.session.execute(
                select(MatchPlayerAppearance).where(
                    MatchPlayerAppearance.match_id.in_(match_ids),
                    MatchPlayerAppearance.team_id == team_id,
                )
            )
            appearances = list(appearance_result.scalars().all())

        formation_candidates: list[str] = []
        for recent_match in recent_matches:
            lineup_metadata = (recent_match.metadata_json or {}).get("lineup")
            if not isinstance(lineup_metadata, dict):
                continue
            formation_key = "home_formation" if recent_match.home_team_id == team_id else "away_formation"
            formation = lineup_metadata.get(formation_key)
            if formation:
                formation_candidates.append(str(formation))
        modal_formation = self._modal_value(formation_candidates) or "4-3-3"
        desired_shape = parse_formation(modal_formation) or {"GK": 1, "DEF": 4, "MID": 3, "ATT": 3}

        start_probabilities: dict[object, float] = defaultdict(float)
        role_map: dict[object, str | None] = {}
        weighted_matches = list(reversed(recent_matches))
        for index, recent_match in enumerate(weighted_matches, start=1):
            weight = float(index)
            for appearance in appearances:
                if appearance.match_id != recent_match.id:
                    continue
                role_map[appearance.player_id] = appearance.position or role_map.get(appearance.player_id)
                if appearance.is_starter:
                    start_probabilities[appearance.player_id] += weight

        max_weight = sum(float(index) for index in range(1, len(weighted_matches) + 1)) or 1.0
        for player_id in list(start_probabilities):
            start_probabilities[player_id] /= max_weight

        membership_result = await self.session.execute(
            select(TeamMembership.player_id, TeamMembership.role)
            .where(TeamMembership.team_id == team_id, TeamMembership.is_current.is_(True))
        )
        candidate_players = [(player_id, role) for player_id, role in membership_result.all()]
        if not candidate_players:
            candidate_players = [(player_id, role_map.get(player_id)) for player_id in start_probabilities]

        player_ratings = await self._load_player_ratings(
            player_ids={player_id for player_id, _role in candidate_players},
            target_date=target_date,
        )
        scored_candidates: list[tuple[float, object, str | None]] = []
        for player_id, membership_role in candidate_players:
            player_rating = player_ratings.get(player_id)
            power = player_rating.player_power if player_rating is not None else None
            start_probability = start_probabilities.get(player_id, 0.0)
            selection_score = start_probability + 0.25 * ((power or 0.0) / 100.0)
            role_code = membership_role or role_map.get(player_id) or (
                player_rating.role_code if player_rating is not None else None
            )
            scored_candidates.append((selection_score, player_id, role_code))

        scored_candidates.sort(key=lambda item: item[0], reverse=True)
        selected_ids: list[object] = []
        selected_roles: dict[object, str | None] = {}
        remaining = list(scored_candidates)
        for bucket, quota in desired_shape.items():
            bucket_roles = []
            for item in remaining:
                _, player_id, role_code = item
                if role_group(role_code) == bucket:
                    bucket_roles.append(item)
            for item in bucket_roles[:quota]:
                _, player_id, role_code = item
                selected_ids.append(player_id)
                selected_roles[player_id] = role_code
                remaining.remove(item)

        for _score, player_id, role_code in remaining:
            if len(selected_ids) >= 11:
                break
            selected_ids.append(player_id)
            selected_roles[player_id] = role_code

        return {
            "player_ids": selected_ids[:11],
            "roles": selected_roles,
            "formation": modal_formation,
            "low_history": len(recent_matches) < 3,
        }

    async def _load_team_ratings(
        self,
        *,
        team_ids: list[object],
        target_date: date,
    ) -> dict[object, TeamRatingDaily]:
        if not team_ids:
            return {}
        result = await self.session.execute(
            select(TeamRatingDaily)
            .where(
                TeamRatingDaily.team_id.in_(team_ids),
                TeamRatingDaily.rating_date <= target_date,
                TeamRatingDaily.feature_version == self.feature_version,
            )
            .order_by(TeamRatingDaily.team_id.asc(), TeamRatingDaily.rating_date.desc())
        )
        rows: dict[object, TeamRatingDaily] = {}
        for item in result.scalars().all():
            rows.setdefault(item.team_id, item)
        return rows

    async def _load_player_ratings(
        self,
        *,
        player_ids: set[object],
        target_date: date,
    ) -> dict[object, PlayerRatingDaily]:
        if not player_ids:
            return {}
        result = await self.session.execute(
            select(PlayerRatingDaily)
            .where(
                PlayerRatingDaily.player_id.in_(player_ids),
                PlayerRatingDaily.rating_date <= target_date,
                PlayerRatingDaily.feature_version == self.feature_version,
            )
            .order_by(PlayerRatingDaily.player_id.asc(), PlayerRatingDaily.rating_date.desc())
        )
        rows: dict[object, PlayerRatingDaily] = {}
        for item in result.scalars().all():
            rows.setdefault(item.player_id, item)
        return rows

    def _build_static_context(
        self,
        *,
        match: Match,
        team_ratings: dict[object, TeamRatingDaily],
        player_ratings: dict[object, PlayerRatingDaily],
        real_lineups: dict[str, list[MatchPlayerAppearance]],
        predicted_lineups: dict[str, object],
        market_ticks: list[MatchMarketTick],
    ) -> dict[str, object]:
        home_team_rating = team_ratings.get(match.home_team_id)
        away_team_rating = team_ratings.get(match.away_team_id)
        pre_market = self._build_pre_market_context(market_ticks=market_ticks)
        real_home = self._lineup_metrics(
            player_ids={appearance.player_id for appearance in real_lineups["home"]},
            roles={appearance.player_id: appearance.position for appearance in real_lineups["home"]},
            player_ratings=player_ratings,
        )
        real_away = self._lineup_metrics(
            player_ids={appearance.player_id for appearance in real_lineups["away"]},
            roles={appearance.player_id: appearance.position for appearance in real_lineups["away"]},
            player_ratings=player_ratings,
        )
        pred_home = self._lineup_metrics(
            player_ids=set(predicted_lineups["home_players"]),
            roles=predicted_lineups["home_roles"],
            player_ratings=player_ratings,
        )
        pred_away = self._lineup_metrics(
            player_ids=set(predicted_lineups["away_players"]),
            roles=predicted_lineups["away_roles"],
            player_ratings=player_ratings,
        )
        pred_home["strength_diff"] = self._diff(pred_home["strength"], pred_away["strength"])
        pred_away["strength_diff"] = self._diff(pred_away["strength"], pred_home["strength"])
        real_home["strength_diff"] = self._diff(real_home["strength"], real_away["strength"])
        real_away["strength_diff"] = self._diff(real_away["strength"], real_home["strength"])
        home_jaccard = jaccard_similarity(
            set(predicted_lineups["home_players"]),
            {appearance.player_id for appearance in real_lineups["home"]},
        )
        away_jaccard = jaccard_similarity(
            set(predicted_lineups["away_players"]),
            {appearance.player_id for appearance in real_lineups["away"]},
        )

        home_missing_ids = set(predicted_lineups["home_players"]) - {
            appearance.player_id for appearance in real_lineups["home"]
        }
        away_missing_ids = set(predicted_lineups["away_players"]) - {
            appearance.player_id for appearance in real_lineups["away"]
        }
        home_missing_strength = sum(
            (player_ratings.get(player_id).player_power or 0.0)
            for player_id in home_missing_ids
            if player_ratings.get(player_id) is not None
        )
        away_missing_strength = sum(
            (player_ratings.get(player_id).player_power or 0.0)
            for player_id in away_missing_ids
            if player_ratings.get(player_id) is not None
        )

        lineup_surprise_home = self._lineup_surprise(
            jaccard=home_jaccard,
            predicted_strength=pred_home["strength"],
            real_strength=real_home["strength"],
        )
        lineup_surprise_away = self._lineup_surprise(
            jaccard=away_jaccard,
            predicted_strength=pred_away["strength"],
            real_strength=real_away["strength"],
        )

        return {
            "pre_market": pre_market,
            "team_strength_diff": self._diff(
                home_team_rating.team_strength if home_team_rating is not None else None,
                away_team_rating.team_strength if away_team_rating is not None else None,
            ),
            "elo_diff": self._diff(
                home_team_rating.elo_rating if home_team_rating is not None else None,
                away_team_rating.elo_rating if away_team_rating is not None else None,
            ),
            "form_points_diff": self._diff(
                home_team_rating.form_points_avg if home_team_rating is not None else None,
                away_team_rating.form_points_avg if away_team_rating is not None else None,
            ),
            "xg_form_diff": self._diff(
                home_team_rating.xg_form_avg if home_team_rating is not None else None,
                away_team_rating.xg_form_avg if away_team_rating is not None else None,
            ),
            "xga_form_diff": self._diff(
                home_team_rating.xga_form_avg if home_team_rating is not None else None,
                away_team_rating.xga_form_avg if away_team_rating is not None else None,
            ),
            "rest_days_diff": self._diff(
                home_team_rating.rest_days if home_team_rating is not None else None,
                away_team_rating.rest_days if away_team_rating is not None else None,
            ),
            "fatigue_diff": self._diff(
                home_team_rating.fatigue_minutes_14d if home_team_rating is not None else None,
                away_team_rating.fatigue_minutes_14d if away_team_rating is not None else None,
            ),
            "pred_home": pred_home,
            "pred_away": pred_away,
            "real_home": real_home,
            "real_away": real_away,
            "lineup_surprise_score": mean([lineup_surprise_home, lineup_surprise_away]),
            "rotation_diff": float(len(home_missing_ids) - len(away_missing_ids)),
            "missing_strength_diff": home_missing_strength - away_missing_strength,
            "predicted_lineup_low_history": bool(
                predicted_lineups["home_low_history"] or predicted_lineups["away_low_history"]
            ),
        }

    def _build_dynamic_context(
        self,
        *,
        match: Match,
        minute: int,
        event_rows: list[MatchEventTimeline],
        live_frames: list[MatchLiveStatFrame],
        market_ticks: list[MatchMarketTick],
        previous_live_vectors: list[tuple[datetime, dict[str, float | None]]],
    ) -> dict[str, object]:
        current_events = [
            item for item in event_rows if self._event_minute(item) is not None and self._event_minute(item) <= minute
        ]
        current_frame = self._latest_frame_before(live_frames, minute=minute)
        frame_last5 = self._latest_frame_before(live_frames, minute=max(minute - 5, 0))
        frame_last10 = self._latest_frame_before(live_frames, minute=max(minute - 10, 0))
        market_context = self._build_live_market_context(
            market_ticks=market_ticks,
            snapshot_ts=match.kickoff_at + timedelta(minutes=minute),
            previous_live_vectors=previous_live_vectors,
        )

        home_score = sum(1 for item in current_events if self._is_goal_event(item) and item.team_side == "home")
        away_score = sum(1 for item in current_events if self._is_goal_event(item) and item.team_side == "away")
        last_goal_minute = self._latest_event_minute(current_events, predicate=self._is_goal_event)
        last_red_minute = self._latest_event_minute(current_events, predicate=self._is_red_card_event)

        return {
            "home_score": home_score,
            "away_score": away_score,
            "home_red_cards": sum(
                1 for item in current_events if self._is_red_card_event(item) and item.team_side == "home"
            ),
            "away_red_cards": sum(
                1 for item in current_events if self._is_red_card_event(item) and item.team_side == "away"
            ),
            "yellow_card_diff": self._yellow_card_diff(current_events),
            "subs_diff": self._subs_diff(current_events),
            "time_since_last_goal": (minute - last_goal_minute) if last_goal_minute is not None else None,
            "time_since_last_red_card": (minute - last_red_minute) if last_red_minute is not None else None,
            "frame": current_frame,
            "frame_last5": frame_last5,
            "frame_last10": frame_last10,
            "market": market_context,
        }

    def _compose_snapshot_payload(
        self,
        *,
        match: Match,
        phase: SnapshotPhase,
        minute: int,
        static_context: dict[str, object],
        dynamic_context: dict[str, object],
        model,
        cluster_model,
        max_minute: int,
        event_rows: list[MatchEventTimeline],
    ) -> dict[str, object]:
        frame = dynamic_context["frame"]
        frame_last5 = dynamic_context["frame_last5"]
        frame_last10 = dynamic_context["frame_last10"]
        market = dynamic_context["market"]
        pre_market = static_context["pre_market"]
        pred_home = static_context["pred_home"]
        pred_away = static_context["pred_away"]
        real_home = static_context["real_home"]
        real_away = static_context["real_away"]
        score_state = self._reconcile_score_state(
            match=match,
            phase=phase,
            minute=minute,
            max_minute=max_minute,
            event_rows=event_rows,
            current_home_score=dynamic_context["home_score"],
            current_away_score=dynamic_context["away_score"],
        )
        home_score = score_state["home_score"]
        away_score = score_state["away_score"]
        score_diff = home_score - away_score

        live_home_prob = market.get("live_home_prob")
        pre_home_prob = pre_market.get("pre_home_prob")
        xg_diff_total = self._frame_diff(frame, "home_xg", "away_xg")
        shots_diff_total = self._frame_diff(frame, "home_shots", "away_shots")
        sot_diff_total = self._frame_diff(frame, "home_shots_on_target", "away_shots_on_target")
        corners_diff_total = self._frame_diff(frame, "home_corners", "away_corners")
        possession_diff = self._frame_diff(frame, "home_possession", "away_possession")
        xg_diff_last5 = self._frame_window_diff(frame, frame_last5, "home_xg", "away_xg")
        xg_diff_last10 = self._frame_window_diff(frame, frame_last10, "home_xg", "away_xg")
        shots_diff_last5 = self._frame_window_diff(frame, frame_last5, "home_shots", "away_shots")
        shots_diff_last10 = self._frame_window_diff(frame, frame_last10, "home_shots", "away_shots")
        sot_diff_last10 = self._frame_window_diff(
            frame,
            frame_last10,
            "home_shots_on_target",
            "away_shots_on_target",
        )
        dangerous_attacks_diff_last10 = self._frame_window_diff(
            frame,
            frame_last10,
            "home_dangerous_attacks",
            "away_dangerous_attacks",
        )
        box_entries_diff_last10 = self._frame_window_diff(
            frame,
            frame_last10,
            "home_box_entries",
            "away_box_entries",
        )
        pressure_diff_last10 = self._frame_window_diff(
            frame,
            frame_last10,
            "home_pressure_index",
            "away_pressure_index",
        )
        momentum_diff = self._momentum_diff(frame=frame, frame_last10=frame_last10)
        lineup_context_available = (
            pred_home["strength_diff"] is not None or real_home["strength_diff"] is not None
        )
        team_context_available = (
            static_context.get("team_strength_diff") is not None
            or static_context.get("elo_diff") is not None
        )
        market_available = any(
            value is not None
            for value in (
                pre_market.get("pre_home_prob"),
                pre_market.get("pre_draw_prob"),
                pre_market.get("pre_away_prob"),
                market.get("live_home_prob"),
                market.get("live_draw_prob"),
                market.get("live_away_prob"),
                market.get("live_over25_prob"),
                market.get("live_under25_prob"),
                market.get("live_next_goal_home_prob"),
            )
        )
        flow_available = any(
            value is not None
            for value in (
                xg_diff_total,
                shots_diff_total,
                sot_diff_total,
                pressure_diff_last10,
                momentum_diff,
            )
        )
        state_model_home_prob = self._estimate_state_model_home_prob(
            model=model,
            phase=phase,
            minute=minute,
            team_strength_diff=static_context.get("team_strength_diff"),
            pred_lineup_strength_diff=pred_home["strength_diff"],
            real_lineup_strength_diff=real_home["strength_diff"],
            score_diff=score_diff,
            xg_diff_total=xg_diff_total,
            shots_diff_total=shots_diff_total,
            momentum_diff=momentum_diff,
            red_card_diff=int(dynamic_context["away_red_cards"] - dynamic_context["home_red_cards"]),
            pre_home_prob=pre_home_prob,
        )
        market_overreaction_score = None
        market_underreaction_score = None
        if (
            live_home_prob is not None
            and pre_home_prob is not None
            and state_model_home_prob is not None
        ):
            market_overreaction_score = max(
                0.0,
                abs(live_home_prob - pre_home_prob) - abs(state_model_home_prob - pre_home_prob),
            )
            market_underreaction_score = max(
                0.0,
                abs(state_model_home_prob - pre_home_prob) - abs(live_home_prob - pre_home_prob),
            )

        label_bundle = self._build_labels(
            match=match,
            minute=minute,
            max_minute=max_minute,
            event_rows=event_rows,
            current_home_score=home_score,
            current_away_score=away_score,
            score_conflict_with_final=score_state["score_conflict_with_final"],
        )
        feature_ready, trainable_reasons = self._feature_ready_status(
            phase=phase,
            pre_home_prob=pre_home_prob,
            team_context_available=team_context_available,
            has_score=home_score is not None and away_score is not None,
            has_live_signal=bool(live_home_prob is not None or flow_available),
        )
        label_final_ready = label_bundle["label_final_result_1x2"] is not None
        path_labels_ready = label_bundle["label_goal_next10min"] is not None
        trainable_snapshot = feature_ready and label_final_ready and not score_state["score_conflict_with_final"]
        coverage_tier = self._coverage_tier(
            market_available=market_available,
            lineup_context_available=lineup_context_available,
            flow_available=flow_available,
            team_context_available=team_context_available,
        )
        state_cluster_id = self._estimate_cluster_id(
            cluster_model=cluster_model,
            minute=minute,
            score_diff=score_diff,
            xg_diff_total=xg_diff_total,
            shots_diff_total=shots_diff_total,
            momentum_diff=momentum_diff,
            live_home_prob=live_home_prob,
        )

        return {
            "match_id": match.id,
            "snapshot_phase": phase,
            "snapshot_minute": minute,
            "snapshot_ts": match.kickoff_at + timedelta(minutes=minute),
            "feature_version": self.feature_version,
            "is_finalized": phase == SnapshotPhase.finalized,
            "availability_json": {
                "market_available": market_available,
                "xg_available": frame is not None and (frame.home_xg is not None or frame.away_xg is not None),
                "corners_available": frame is not None and (frame.home_corners is not None or frame.away_corners is not None),
                "possession_available": frame is not None and (frame.home_possession is not None or frame.away_possession is not None),
                "pressure_available": frame is not None and (frame.home_pressure_index is not None or frame.away_pressure_index is not None),
                "real_lineup_available": bool(real_home["players"]) and bool(real_away["players"]),
                "lineup_context_available": lineup_context_available,
                "team_context_available": team_context_available,
                "feature_ready": feature_ready,
                "label_final_ready": label_final_ready,
                "path_labels_ready": path_labels_ready,
            },
            "quality_json": {
                "state_model_method": "sklearn" if model is not None else "heuristic",
                "cluster_method": "sklearn" if cluster_model is not None else "hash",
                "score_integrity": score_state["score_integrity"],
                "score_conflict_with_final": score_state["score_conflict_with_final"],
                "market_time_precision": market.get("market_time_precision"),
                "coverage_tier": coverage_tier,
                "feature_ready": feature_ready,
                "label_final_ready": label_final_ready,
                "path_labels_ready": path_labels_ready,
                "trainable_snapshot": trainable_snapshot,
            },
            "source_json": {
                "feature_version": self.feature_version,
                "event_rows": len(event_rows),
                "live_frame_loaded": frame is not None,
                "market_context_available": market_available,
            },
            "metadata_json": {
                "trainable_reasons": trainable_reasons,
                "score_state": {
                    "event_home_score": score_state["event_home_score"],
                    "event_away_score": score_state["event_away_score"],
                    "final_home_score": score_state["final_home_score"],
                    "final_away_score": score_state["final_away_score"],
                },
            },
            "expected_goal_line_proxy": pre_market.get("expected_goal_line_proxy"),
            "predicted_lineup_low_history": static_context.get("predicted_lineup_low_history"),
            "betfair_unavailable": True,
            "state_model_home_prob": state_model_home_prob,
            "pre_home_prob": pre_market.get("pre_home_prob"),
            "pre_draw_prob": pre_market.get("pre_draw_prob"),
            "pre_away_prob": pre_market.get("pre_away_prob"),
            "pre_favorite_gap": pre_market.get("pre_favorite_gap"),
            "pre_expected_goal_line": pre_market.get("pre_expected_goal_line"),
            "team_strength_diff": static_context.get("team_strength_diff"),
            "elo_diff": static_context.get("elo_diff"),
            "form_points_diff": static_context.get("form_points_diff"),
            "xg_form_diff": static_context.get("xg_form_diff"),
            "xga_form_diff": static_context.get("xga_form_diff"),
            "rest_days_diff": static_context.get("rest_days_diff"),
            "fatigue_diff": static_context.get("fatigue_diff"),
            "pred_home_lineup_strength": pred_home["strength"],
            "pred_away_lineup_strength": pred_away["strength"],
            "pred_lineup_strength_diff": pred_home["strength_diff"],
            "real_home_lineup_strength": real_home["strength"],
            "real_away_lineup_strength": real_away["strength"],
            "real_lineup_strength_diff": real_home["strength_diff"],
            "home_defense_strength": real_home["defense_strength"],
            "away_defense_strength": real_away["defense_strength"],
            "midfield_strength_diff": self._diff(real_home["mid_strength"], real_away["mid_strength"]),
            "attack_strength_diff": self._diff(real_home["att_strength"], real_away["att_strength"]),
            "lineup_surprise_score": static_context.get("lineup_surprise_score"),
            "rotation_diff": static_context.get("rotation_diff"),
            "missing_strength_diff": static_context.get("missing_strength_diff"),
            "minute_norm": minute / 90.0,
            "time_remaining_norm": max(0, 90 - minute) / 90.0,
            "home_score": home_score,
            "away_score": away_score,
            "score_diff": score_diff,
            "goal_total": home_score + away_score,
            "home_red_cards": dynamic_context["home_red_cards"],
            "away_red_cards": dynamic_context["away_red_cards"],
            "red_card_diff": dynamic_context["away_red_cards"] - dynamic_context["home_red_cards"],
            "yellow_card_diff": dynamic_context["yellow_card_diff"],
            "subs_diff": dynamic_context["subs_diff"],
            "time_since_last_goal": dynamic_context["time_since_last_goal"],
            "time_since_last_red_card": dynamic_context["time_since_last_red_card"],
            "xg_diff_total": xg_diff_total,
            "shots_diff_total": shots_diff_total,
            "sot_diff_total": sot_diff_total,
            "corners_diff_total": corners_diff_total,
            "possession_diff": possession_diff,
            "xg_diff_last5": xg_diff_last5,
            "xg_diff_last10": xg_diff_last10,
            "shots_diff_last5": shots_diff_last5,
            "shots_diff_last10": shots_diff_last10,
            "sot_diff_last10": sot_diff_last10,
            "dangerous_attacks_diff_last10": dangerous_attacks_diff_last10,
            "box_entries_diff_last10": box_entries_diff_last10,
            "pressure_diff_last10": pressure_diff_last10,
            "momentum_diff": momentum_diff,
            "live_home_prob": live_home_prob,
            "live_draw_prob": market.get("live_draw_prob"),
            "live_away_prob": market.get("live_away_prob"),
            "live_over25_prob": market.get("live_over25_prob"),
            "live_under25_prob": market.get("live_under25_prob"),
            "live_next_goal_home_prob": market.get("live_next_goal_home_prob"),
            "home_prob_shift_from_pre": self._diff(live_home_prob, pre_home_prob),
            "draw_prob_shift_from_pre": self._diff(market.get("live_draw_prob"), pre_market.get("pre_draw_prob")),
            "away_prob_shift_from_pre": self._diff(market.get("live_away_prob"), pre_market.get("pre_away_prob")),
            "home_prob_change_last1": market.get("home_prob_change_last1"),
            "home_prob_change_last5": market.get("home_prob_change_last5"),
            "market_volatility_last5": market.get("market_volatility_last5"),
            "betfair_total_matched": None,
            "betfair_liquidity_score": None,
            "betfair_home_spread": None,
            "market_overreaction_score": market_overreaction_score,
            "market_underreaction_score": market_underreaction_score,
            "favorite_fragility_score": self._favorite_fragility_score(
                pre_market=pre_market,
                momentum_diff=momentum_diff,
                lineup_surprise_score=static_context.get("lineup_surprise_score"),
                market_overreaction_score=market_overreaction_score,
                missing_strength_diff=static_context.get("missing_strength_diff"),
            ),
            "underdog_resistance_score": self._underdog_resistance_score(
                pre_market=pre_market,
                score_diff=score_diff,
                xg_diff_total=xg_diff_total,
                momentum_diff=momentum_diff,
                market_underreaction_score=market_underreaction_score,
            ),
            "comeback_potential_score": self._comeback_potential_score(
                score_diff=score_diff,
                time_remaining_norm=max(0, 90 - minute) / 90.0,
                momentum_diff=momentum_diff,
                favorite_fragility_score=self._favorite_fragility_score(
                    pre_market=pre_market,
                    momentum_diff=momentum_diff,
                    lineup_surprise_score=static_context.get("lineup_surprise_score"),
                    market_overreaction_score=market_overreaction_score,
                    missing_strength_diff=static_context.get("missing_strength_diff"),
                ),
            ),
            "late_goal_risk_score": self._late_goal_risk_score(
                minute=minute,
                xg_last10_total=self._frame_window_total(frame, frame_last10, "home_xg", "away_xg"),
                shots_last10_total=self._frame_window_total(frame, frame_last10, "home_shots", "away_shots"),
                pressure_last10_total=self._frame_window_total(
                    frame,
                    frame_last10,
                    "home_pressure_index",
                    "away_pressure_index",
                ),
                live_over25_prob=market.get("live_over25_prob"),
            ),
            "state_cluster_id": state_cluster_id,
            "score_state_class": score_state_class(score_diff),
            "market_state_class": market_state_class(
                market_volatility_last5=market.get("market_volatility_last5"),
                live_home_prob=live_home_prob,
                live_draw_prob=market.get("live_draw_prob"),
                live_away_prob=market.get("live_away_prob"),
            ),
            "label_final_result_1x2": label_bundle["label_final_result_1x2"],
            "label_home_win": label_bundle["label_home_win"],
            "label_goal_next10min": label_bundle["label_goal_next10min"],
            "label_next_goal_team": label_bundle["label_next_goal_team"],
            "label_result_from_snapshot_to_end": label_bundle["label_result_from_snapshot_to_end"],
            "label_over25_from_snapshot": label_bundle["label_over25_from_snapshot"],
        }

    def _build_pre_market_context(self, *, market_ticks: list[MatchMarketTick]) -> dict[str, object]:
        prematch_1x2 = self._latest_selection_probs(
            market_ticks=market_ticks,
            phase=SnapshotPhase.pre,
            market_type="1x2",
        )
        total_lines = self._prematch_total_lines(market_ticks=market_ticks)
        expected_goal_line = None
        expected_goal_line_proxy = False
        if total_lines:
            expected_goal_line = min(
                total_lines,
                key=lambda item: abs((item["over_prob"] or 0.5) - 0.5),
            )["line_value"]
        else:
            expected_goal_line_proxy = True
            expected_goal_line = 2.5

        probs = [prematch_1x2.get(selection) for selection in SHOTMARKET_SELECTIONS]
        sorted_probs = sorted((value for value in probs if value is not None), reverse=True)
        favorite_gap = None
        if len(sorted_probs) >= 2:
            favorite_gap = sorted_probs[0] - sorted_probs[1]

        return {
            "pre_home_prob": prematch_1x2.get("home"),
            "pre_draw_prob": prematch_1x2.get("draw"),
            "pre_away_prob": prematch_1x2.get("away"),
            "pre_favorite_gap": favorite_gap,
            "pre_expected_goal_line": expected_goal_line,
            "expected_goal_line_proxy": expected_goal_line_proxy,
        }

    def _build_live_market_context(
        self,
        *,
        market_ticks: list[MatchMarketTick],
        snapshot_ts: datetime,
        previous_live_vectors: list[tuple[datetime, dict[str, float | None]]],
    ) -> dict[str, object]:
        eligible_ticks = self._eligible_market_ticks(market_ticks=market_ticks, snapshot_ts=snapshot_ts)
        live_1x2 = self._latest_selection_probs(
            market_ticks=eligible_ticks,
            phase=SnapshotPhase.live,
            market_type="1x2",
        )
        total_25 = self._latest_total_line_probs(
            market_ticks=eligible_ticks,
            phase=SnapshotPhase.live,
            line_value=2.5,
        )
        next_goal = self._latest_selection_probs(
            market_ticks=eligible_ticks,
            phase=SnapshotPhase.live,
            market_type="next_goal",
        )
        prior_1 = self._latest_live_vector_before(previous_live_vectors, snapshot_ts=snapshot_ts, minutes=1)
        prior_5 = self._latest_live_vector_before(previous_live_vectors, snapshot_ts=snapshot_ts, minutes=5)
        trailing_values = [
            values.get("live_home_prob")
            for ts, values in previous_live_vectors
            if ts >= snapshot_ts - timedelta(minutes=5)
        ]
        live_market_ticks = [
            tick
            for tick in eligible_ticks
            if tick.snapshot_phase == SnapshotPhase.live
            and tick.market_type in {"1x2", "totals", "next_goal"}
        ]
        market_time_precision = "missing"
        if live_market_ticks:
            market_time_precision = (
                "minute"
                if any(tick.minute is not None for tick in live_market_ticks)
                else "timestamp_only"
            )
        return {
            "live_home_prob": live_1x2.get("home"),
            "live_draw_prob": live_1x2.get("draw"),
            "live_away_prob": live_1x2.get("away"),
            "live_over25_prob": total_25.get("over"),
            "live_under25_prob": total_25.get("under"),
            "live_next_goal_home_prob": next_goal.get("home"),
            "market_time_precision": market_time_precision,
            "home_prob_change_last1": self._diff(
                live_1x2.get("home"),
                prior_1.get("live_home_prob") if prior_1 else None,
            ),
            "home_prob_change_last5": self._diff(
                live_1x2.get("home"),
                prior_5.get("live_home_prob") if prior_5 else None,
            ),
            "market_volatility_last5": standard_deviation(trailing_values),
        }

    def _lineup_metrics(
        self,
        *,
        player_ids: set[object],
        roles: dict[object, str | None],
        player_ratings: dict[object, PlayerRatingDaily],
    ) -> dict[str, object]:
        grouped: dict[str, list[float | None]] = defaultdict(list)
        for player_id in player_ids:
            rating = player_ratings.get(player_id)
            power = rating.player_power if rating is not None else None
            grouped[role_group(roles.get(player_id)) or "UNK"].append(power)
        strength = lineup_strength(
            gk=mean(grouped.get("GK", [])),
            defenders=grouped.get("DEF", []),
            midfielders=grouped.get("MID", []),
            attackers=grouped.get("ATT", []),
        )
        return {
            "players": player_ids,
            "strength": strength,
            "strength_diff": None,
            "defense_strength": mean(grouped.get("DEF", [])),
            "mid_strength": mean(grouped.get("MID", [])),
            "att_strength": mean(grouped.get("ATT", [])),
        }

    def _lineup_surprise(
        self,
        *,
        jaccard: float | None,
        predicted_strength: float | None,
        real_strength: float | None,
    ) -> float | None:
        return min(
            1.0,
            max(
                0.0,
                0.7 * (1.0 - (jaccard if jaccard is not None else 0.0))
                + 0.3 * abs((predicted_strength or 0.0) - (real_strength or 0.0)) / 100.0,
            ),
        )

    def _resolve_max_minute(
        self,
        *,
        match: Match,
        event_rows: list[MatchEventTimeline],
        live_frames: list[MatchLiveStatFrame],
    ) -> int:
        candidates = [90 if match.status == MatchStatus.finished else 0]
        candidates.extend(self._event_minute(item) or 0 for item in event_rows)
        candidates.extend(item.minute or 0 for item in live_frames)
        return min(130, max(candidates) if candidates else 0)

    @staticmethod
    def _latest_frame_before(frames: list[MatchLiveStatFrame], *, minute: int) -> MatchLiveStatFrame | None:
        selected = None
        for frame in frames:
            frame_minute = frame.minute or 0
            if frame_minute <= minute:
                selected = frame
            else:
                break
        return selected

    @staticmethod
    def _frame_diff(frame, home_attr: str, away_attr: str) -> float | None:
        if frame is None:
            return None
        home_value = getattr(frame, home_attr, None)
        away_value = getattr(frame, away_attr, None)
        if home_value is None or away_value is None:
            return None
        return float(home_value) - float(away_value)

    @classmethod
    def _frame_window_diff(cls, frame, prior_frame, home_attr: str, away_attr: str) -> float | None:
        current = cls._frame_diff(frame, home_attr, away_attr)
        prior = cls._frame_diff(prior_frame, home_attr, away_attr)
        return cls._diff(current, prior)

    @staticmethod
    def _frame_window_total(frame, prior_frame, home_attr: str, away_attr: str) -> float | None:
        if frame is None:
            return None
        current_total = (getattr(frame, home_attr, None) or 0.0) + (getattr(frame, away_attr, None) or 0.0)
        prior_total = 0.0
        if prior_frame is not None:
            prior_total = (getattr(prior_frame, home_attr, None) or 0.0) + (
                getattr(prior_frame, away_attr, None) or 0.0
            )
        return float(current_total - prior_total)

    @staticmethod
    def _event_minute(item: MatchEventTimeline) -> int | None:
        if item.minute is None:
            return None
        return item.minute + (item.stoppage_minute or 0)

    @classmethod
    def _latest_event_minute(cls, events: list[MatchEventTimeline], *, predicate) -> int | None:
        filtered = [cls._event_minute(item) for item in events if predicate(item)]
        filtered = [item for item in filtered if item is not None]
        return max(filtered) if filtered else None

    @staticmethod
    def _is_goal_event(item: MatchEventTimeline) -> bool:
        return "goal" in str(item.event_type or "").casefold()

    @staticmethod
    def _is_red_card_event(item: MatchEventTimeline) -> bool:
        text = f"{item.event_type or ''} {item.event_subtype or ''}".casefold()
        return "red" in text

    @staticmethod
    def _is_yellow_card_event(item: MatchEventTimeline) -> bool:
        text = f"{item.event_type or ''} {item.event_subtype or ''}".casefold()
        return "yellow" in text

    @staticmethod
    def _is_sub_event(item: MatchEventTimeline) -> bool:
        text = f"{item.event_type or ''} {item.event_subtype or ''}".casefold()
        return "sub" in text

    @classmethod
    def _yellow_card_diff(cls, events: list[MatchEventTimeline]) -> int | None:
        home = sum(1 for item in events if cls._is_yellow_card_event(item) and item.team_side == "home")
        away = sum(1 for item in events if cls._is_yellow_card_event(item) and item.team_side == "away")
        return home - away

    @classmethod
    def _subs_diff(cls, events: list[MatchEventTimeline]) -> int | None:
        home = sum(1 for item in events if cls._is_sub_event(item) and item.team_side == "home")
        away = sum(1 for item in events if cls._is_sub_event(item) and item.team_side == "away")
        return home - away

    @classmethod
    def _event_goal_counts(cls, events: list[MatchEventTimeline]) -> tuple[int, int]:
        home = sum(1 for item in events if cls._is_goal_event(item) and item.team_side == "home")
        away = sum(1 for item in events if cls._is_goal_event(item) and item.team_side == "away")
        return home, away

    @staticmethod
    def _match_is_finished(match: Match) -> bool:
        status = getattr(match, "status", None)
        status_value = getattr(status, "value", status)
        return status_value == MatchStatus.finished.value or status == MatchStatus.finished

    def _reconcile_score_state(
        self,
        *,
        match: Match,
        phase: SnapshotPhase,
        minute: int,
        max_minute: int,
        event_rows: list[MatchEventTimeline],
        current_home_score: int,
        current_away_score: int,
    ) -> dict[str, object]:
        final_home = match.score_home
        final_away = match.score_away
        total_event_home, total_event_away = self._event_goal_counts(event_rows)
        final_score_known = (
            self._match_is_finished(match)
            and final_home is not None
            and final_away is not None
        )
        score_conflict_with_final = bool(
            final_score_known
            and (total_event_home != final_home or total_event_away != final_away)
        )
        home_score = int(current_home_score)
        away_score = int(current_away_score)
        score_integrity = "event"

        if phase == SnapshotPhase.pre:
            home_score = 0
            away_score = 0
            score_integrity = "pre"
        elif final_score_known:
            if home_score > final_home or away_score > final_away:
                home_score = min(home_score, int(final_home))
                away_score = min(away_score, int(final_away))
                score_integrity = "reconciled"
            if phase == SnapshotPhase.finalized or minute >= max_minute:
                home_score = int(final_home)
                away_score = int(final_away)
                score_integrity = (
                    "final_score"
                    if not score_conflict_with_final
                    else "reconciled_final_score"
                )

        return {
            "home_score": home_score,
            "away_score": away_score,
            "event_home_score": int(current_home_score),
            "event_away_score": int(current_away_score),
            "final_home_score": final_home,
            "final_away_score": final_away,
            "score_conflict_with_final": score_conflict_with_final,
            "score_integrity": score_integrity,
        }

    @staticmethod
    def _feature_ready_status(
        *,
        phase: SnapshotPhase,
        pre_home_prob: float | None,
        team_context_available: bool,
        has_score: bool,
        has_live_signal: bool,
    ) -> tuple[bool, list[str]]:
        reasons: list[str] = []
        if pre_home_prob is None:
            reasons.append("missing_pre_market")
        if not team_context_available:
            reasons.append("missing_team_context")
        if phase != SnapshotPhase.pre and not has_score:
            reasons.append("missing_score")
        if phase != SnapshotPhase.pre and not has_live_signal:
            reasons.append("missing_live_signal")
        return len(reasons) == 0, reasons

    @staticmethod
    def _coverage_tier(
        *,
        market_available: bool,
        lineup_context_available: bool,
        flow_available: bool,
        team_context_available: bool,
    ) -> str:
        signals = sum(
            1
            for value in (
                market_available,
                lineup_context_available,
                flow_available,
                team_context_available,
            )
            if value
        )
        if signals >= 4:
            return "full"
        if signals == 3:
            return "strong"
        if signals == 2:
            return "partial"
        if signals == 1:
            return "thin"
        return "minimal"

    def _momentum_diff(self, *, frame, frame_last10) -> float | None:
        return renormalized_weighted_sum(
            [
                (self._frame_window_diff(frame, frame_last10, "home_xg", "away_xg"), 0.4),
                (
                    self._frame_window_diff(
                        frame,
                        frame_last10,
                        "home_shots_on_target",
                        "away_shots_on_target",
                    ),
                    0.25,
                ),
                (
                    self._frame_window_diff(frame, frame_last10, "home_box_entries", "away_box_entries"),
                    0.20,
                ),
                (
                    self._frame_window_diff(
                        frame,
                        frame_last10,
                        "home_pressure_index",
                        "away_pressure_index",
                    ),
                    0.15,
                ),
            ]
        )

    async def _fit_state_model(self, *, before: datetime):
        try:
            from sklearn.ensemble import HistGradientBoostingClassifier
        except Exception:
            return None

        features, labels = await self._historical_training_rows(before=before)
        if len(features) < 50:
            return None
        model = HistGradientBoostingClassifier(random_state=42)
        model.fit(features, labels)
        return model

    async def _fit_cluster_model(self, *, before: datetime):
        try:
            from sklearn.cluster import MiniBatchKMeans
        except Exception:
            return None

        features, _labels = await self._historical_training_rows(before=before)
        if len(features) < 64:
            return None
        model = MiniBatchKMeans(n_clusters=64, random_state=42)
        model.fit(features)
        return model

    async def _historical_training_rows(self, *, before: datetime) -> tuple[list[list[float]], list[int]]:
        result = await self.session.execute(
            select(MatchFeatureSnapshot)
            .where(
                MatchFeatureSnapshot.snapshot_ts < before,
                MatchFeatureSnapshot.feature_version == self.feature_version,
                MatchFeatureSnapshot.label_home_win.is_not(None),
                MatchFeatureSnapshot.snapshot_phase.in_([SnapshotPhase.live, SnapshotPhase.finalized]),
            )
        )
        features: list[list[float]] = []
        labels: list[int] = []
        for row in result.scalars().all():
            quality = row.quality_json if isinstance(row.quality_json, dict) else {}
            if not bool(quality.get("trainable_snapshot")):
                continue
            vector = self._feature_vector(
                minute=row.snapshot_minute,
                team_strength_diff=row.team_strength_diff,
                pred_lineup_strength_diff=row.pred_lineup_strength_diff,
                real_lineup_strength_diff=row.real_lineup_strength_diff,
                score_diff=row.score_diff,
                xg_diff_total=row.xg_diff_total,
                shots_diff_total=row.shots_diff_total,
                momentum_diff=row.momentum_diff,
                red_card_diff=row.red_card_diff,
                pre_home_prob=row.pre_home_prob,
            )
            if vector is None:
                continue
            features.append(vector)
            labels.append(1 if row.label_home_win else 0)
        return features, labels

    def _estimate_state_model_home_prob(
        self,
        *,
        model,
        phase: SnapshotPhase,
        minute: int,
        team_strength_diff: float | None,
        pred_lineup_strength_diff: float | None,
        real_lineup_strength_diff: float | None,
        score_diff: int | None,
        xg_diff_total: float | None,
        shots_diff_total: float | None,
        momentum_diff: float | None,
        red_card_diff: int | None,
        pre_home_prob: float | None,
    ) -> float | None:
        vector = self._feature_vector(
            minute=minute,
            team_strength_diff=team_strength_diff,
            pred_lineup_strength_diff=pred_lineup_strength_diff,
            real_lineup_strength_diff=real_lineup_strength_diff,
            score_diff=score_diff,
            xg_diff_total=xg_diff_total,
            shots_diff_total=shots_diff_total,
            momentum_diff=momentum_diff,
            red_card_diff=red_card_diff,
            pre_home_prob=pre_home_prob,
        )
        if model is not None and vector is not None:
            try:
                return float(model.predict_proba([vector])[0][1])
            except Exception:
                pass
        heuristic = sigmoid(
            (team_strength_diff or 0.0) * 0.55
            + ((pred_lineup_strength_diff or 0.0) / 100.0) * 0.20
            + ((real_lineup_strength_diff or 0.0) / 100.0) * 0.10
            + (score_diff or 0) * 0.80
            + (xg_diff_total or 0.0) * 0.45
            + (shots_diff_total or 0.0) * 0.03
            + (momentum_diff or 0.0) * 0.25
            + (red_card_diff or 0) * -0.35
            + ((pre_home_prob or 0.5) - 0.5) * 1.2
            - (minute / 90.0) * 0.15
        )
        return heuristic if phase != SnapshotPhase.pre else pre_home_prob

    def _estimate_cluster_id(
        self,
        *,
        cluster_model,
        minute: int,
        score_diff: int | None,
        xg_diff_total: float | None,
        shots_diff_total: float | None,
        momentum_diff: float | None,
        live_home_prob: float | None,
    ) -> int | None:
        vector = [
            float(minute),
            float(score_diff or 0),
            float(xg_diff_total or 0.0),
            float(shots_diff_total or 0.0),
            float(momentum_diff or 0.0),
            float(live_home_prob or 0.0),
        ]
        if cluster_model is not None:
            try:
                return int(cluster_model.predict([vector])[0])
            except Exception:
                pass
        return stable_bucket(vector, buckets=64)

    @staticmethod
    def _feature_vector(
        *,
        minute: int,
        team_strength_diff: float | None,
        pred_lineup_strength_diff: float | None,
        real_lineup_strength_diff: float | None,
        score_diff: int | None,
        xg_diff_total: float | None,
        shots_diff_total: float | None,
        momentum_diff: float | None,
        red_card_diff: int | None,
        pre_home_prob: float | None,
    ) -> list[float] | None:
        return [
            float(minute),
            float(team_strength_diff or 0.0),
            float(pred_lineup_strength_diff or 0.0),
            float(real_lineup_strength_diff or 0.0),
            float(score_diff or 0),
            float(xg_diff_total or 0.0),
            float(shots_diff_total or 0.0),
            float(momentum_diff or 0.0),
            float(red_card_diff or 0),
            float(pre_home_prob or 0.0),
        ]

    def _build_labels(
        self,
        *,
        match: Match,
        minute: int,
        max_minute: int,
        event_rows: list[MatchEventTimeline],
        current_home_score: int,
        current_away_score: int,
        score_conflict_with_final: bool,
    ) -> dict[str, object]:
        final_result_known = (
            self._match_is_finished(match)
            and match.score_home is not None
            and match.score_away is not None
        )
        if not final_result_known:
            return {
                "label_final_result_1x2": None,
                "label_home_win": None,
                "label_goal_next10min": None,
                "label_next_goal_team": None,
                "label_result_from_snapshot_to_end": None,
                "label_over25_from_snapshot": None,
            }

        final_home = int(match.score_home)
        final_away = int(match.score_away)
        final_result = "1" if final_home > final_away else ("X" if final_home == final_away else "2")
        if score_conflict_with_final:
            return {
                "label_final_result_1x2": final_result,
                "label_home_win": final_home > final_away,
                "label_goal_next10min": None,
                "label_next_goal_team": None,
                "label_result_from_snapshot_to_end": None,
                "label_over25_from_snapshot": (final_home + final_away) > 2,
            }

        future_events = [
            item
            for item in event_rows
            if self._is_goal_event(item) and (self._event_minute(item) or 999) > minute
        ]
        next_goal = future_events[0] if future_events else None
        goals_next_10 = any((self._event_minute(item) or 999) <= minute + 10 for item in future_events)
        future_home_goals = sum(1 for item in future_events if item.team_side == "home")
        future_away_goals = sum(1 for item in future_events if item.team_side == "away")
        delta_result = "home" if future_home_goals > future_away_goals else (
            "draw" if future_home_goals == future_away_goals else "away"
        )
        return {
            "label_final_result_1x2": final_result,
            "label_home_win": final_home > final_away,
            "label_goal_next10min": goals_next_10,
            "label_next_goal_team": next_goal.team_side if next_goal is not None else "none",
            "label_result_from_snapshot_to_end": delta_result,
            "label_over25_from_snapshot": (final_home + final_away) > 2,
        }

    @staticmethod
    def _latest_live_vector_before(
        items: list[tuple[datetime, dict[str, float | None]]],
        *,
        snapshot_ts: datetime,
        minutes: int,
    ) -> dict[str, float | None] | None:
        cutoff = snapshot_ts - timedelta(minutes=minutes)
        selected = None
        for ts, payload in items:
            if ts <= cutoff:
                selected = payload
        return selected

    def _latest_selection_probs(
        self,
        *,
        market_ticks: list[MatchMarketTick],
        phase: SnapshotPhase,
        market_type: str,
    ) -> dict[str, float | None]:
        selections = {
            tick.selection_key: tick
            for tick in market_ticks
            if tick.snapshot_phase == phase and tick.market_type == market_type
        }
        if market_type == "1x2":
            values = [
                implied_probability(selections.get("home").odds_decimal if selections.get("home") else None),
                implied_probability(selections.get("draw").odds_decimal if selections.get("draw") else None),
                implied_probability(selections.get("away").odds_decimal if selections.get("away") else None),
            ]
            normalized = normalize_probabilities(values)
            return {
                "home": normalized[0],
                "draw": normalized[1],
                "away": normalized[2],
            }
        if market_type == "next_goal":
            home = implied_probability(selections.get("home").odds_decimal if selections.get("home") else None)
            away = implied_probability(selections.get("away").odds_decimal if selections.get("away") else None)
            normalized = normalize_probabilities([home, away])
            return {"home": normalized[0], "away": normalized[1]}
        return {}

    def _prematch_total_lines(self, *, market_ticks: list[MatchMarketTick]) -> list[dict[str, float | None]]:
        grouped: dict[float, dict[str, MatchMarketTick]] = defaultdict(dict)
        for tick in market_ticks:
            if tick.snapshot_phase != SnapshotPhase.pre or tick.market_type != "totals" or tick.line_value is None:
                continue
            grouped[float(tick.line_value)][tick.selection_key] = tick
        results: list[dict[str, float | None]] = []
        for line_value, selections in grouped.items():
            normalized = normalize_probabilities(
                [
                    implied_probability(selections.get("over").odds_decimal if selections.get("over") else None),
                    implied_probability(selections.get("under").odds_decimal if selections.get("under") else None),
                ]
            )
            results.append({"line_value": line_value, "over_prob": normalized[0], "under_prob": normalized[1]})
        return results

    def _latest_total_line_probs(
        self,
        *,
        market_ticks: list[MatchMarketTick],
        phase: SnapshotPhase,
        line_value: float,
    ) -> dict[str, float | None]:
        grouped = [
            tick
            for tick in market_ticks
            if tick.snapshot_phase == phase and tick.market_type == "totals" and tick.line_value == line_value
        ]
        selections = {tick.selection_key: tick for tick in grouped}
        normalized = normalize_probabilities(
            [
                implied_probability(selections.get("over").odds_decimal if selections.get("over") else None),
                implied_probability(selections.get("under").odds_decimal if selections.get("under") else None),
            ]
        )
        return {"over": normalized[0], "under": normalized[1]}

    @staticmethod
    def _eligible_market_ticks(
        *,
        market_ticks: list[MatchMarketTick],
        snapshot_ts: datetime,
    ) -> list[MatchMarketTick]:
        eligible = [tick for tick in market_ticks if tick.tick_time <= snapshot_ts]
        return eligible or market_ticks

    @staticmethod
    def _favorite_fragility_score(
        *,
        pre_market: dict[str, object],
        momentum_diff: float | None,
        lineup_surprise_score: float | None,
        market_overreaction_score: float | None,
        missing_strength_diff: float | None,
    ) -> float | None:
        fav_edge = max(
            (pre_market.get("pre_home_prob") or 0.0),
            (pre_market.get("pre_away_prob") or 0.0),
        ) - 0.5
        return sigmoid(
            fav_edge * 0.35
            + (-(momentum_diff or 0.0)) * 0.25
            + (lineup_surprise_score or 0.0) * 0.20
            + (market_overreaction_score or 0.0) * 0.20
            + abs((missing_strength_diff or 0.0) / 100.0) * 0.10
        )

    @staticmethod
    def _underdog_resistance_score(
        *,
        pre_market: dict[str, object],
        score_diff: int | None,
        xg_diff_total: float | None,
        momentum_diff: float | None,
        market_underreaction_score: float | None,
    ) -> float | None:
        underdog_gap = 0.5 - max(
            (pre_market.get("pre_home_prob") or 0.0),
            (pre_market.get("pre_away_prob") or 0.0),
        )
        return sigmoid(
            underdog_gap * 0.40
            + (-(score_diff or 0)) * 0.20
            + (-(xg_diff_total or 0.0)) * 0.25
            + (-(momentum_diff or 0.0)) * 0.15
            + (market_underreaction_score or 0.0) * 0.15
        )

    @staticmethod
    def _comeback_potential_score(
        *,
        score_diff: int | None,
        time_remaining_norm: float | None,
        momentum_diff: float | None,
        favorite_fragility_score: float | None,
    ) -> float | None:
        if score_diff is None or score_diff == 0:
            return 0.0
        trailing_momentum = -(momentum_diff or 0.0) if score_diff > 0 else (momentum_diff or 0.0)
        return sigmoid(
            trailing_momentum * 0.35
            + (time_remaining_norm or 0.0) * 0.20
            + (favorite_fragility_score or 0.0) * 0.20
            + abs(score_diff) * -0.25
        )

    @staticmethod
    def _late_goal_risk_score(
        *,
        minute: int,
        xg_last10_total: float | None,
        shots_last10_total: float | None,
        pressure_last10_total: float | None,
        live_over25_prob: float | None,
    ) -> float | None:
        if minute < 70:
            return None
        return sigmoid(
            (xg_last10_total or 0.0) * 0.35
            + (shots_last10_total or 0.0) * 0.10
            + (pressure_last10_total or 0.0) * 0.08
            + (live_over25_prob or 0.0) * 0.20
            + ((90 - minute) / 20.0) * -0.15
        )

    @staticmethod
    def _modal_value(values: list[str]) -> str | None:
        if not values:
            return None
        counts: dict[str, int] = defaultdict(int)
        for value in values:
            counts[value] += 1
        return max(counts.items(), key=lambda item: item[1])[0]

    @staticmethod
    def _diff(left: float | None, right: float | None) -> float | None:
        if left is None or right is None:
            return None
        return float(left) - float(right)
