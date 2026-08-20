from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.models.domain import (
    Match,
    MatchLiveStatFrame,
    MatchPlayerAppearance,
    MatchStatus,
    PlayerRatingDaily,
    TeamMembership,
    TeamRatingDaily,
)
from app.services.feature_math import (
    ewma_weight,
    mean,
    renormalized_weighted_sum,
    role_group,
    safe_float,
    standard_deviation,
    weighted_mean,
    zscore,
)

ELO_BASE = 1500.0
ELO_K = 20.0
HOME_ADVANTAGE = 55.0


@dataclass(slots=True)
class FeatureRatingStats:
    team_ratings_upserted: int = 0
    player_ratings_upserted: int = 0

    def to_dict(self) -> dict[str, int]:
        return {
            "team_ratings_upserted": self.team_ratings_upserted,
            "player_ratings_upserted": self.player_ratings_upserted,
        }


class FeatureRatingService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.settings = get_settings()
        self.feature_version = self.settings.feature_snapshot_version
        self.stats = FeatureRatingStats()

    async def rebuild_for_date(self, *, target_date: date) -> dict[str, int]:
        end_of_day = datetime.combine(target_date + timedelta(days=1), datetime.min.time(), tzinfo=UTC)
        finished_matches = await self._load_finished_matches(before=end_of_day)
        xg_by_match_id = await self._load_match_xg_totals(match_ids=[match.id for match in finished_matches])
        await self._upsert_team_ratings(
            target_date=target_date,
            matches=finished_matches,
            xg_by_match_id=xg_by_match_id,
        )
        await self._upsert_player_ratings(
            target_date=target_date,
            end_of_day=end_of_day,
        )
        return self.stats.to_dict()

    async def _upsert_team_ratings(
        self,
        *,
        target_date: date,
        matches: list[Match],
        xg_by_match_id: dict[object, tuple[float | None, float | None]],
    ) -> None:
        elo_ratings = defaultdict(lambda: ELO_BASE)
        team_matches: dict[object, list[Match]] = defaultdict(list)
        latest_competition_season_id: dict[object, object | None] = {}

        for match in sorted(matches, key=lambda item: item.kickoff_at):
            home_team_id = match.home_team_id
            away_team_id = match.away_team_id
            team_matches[home_team_id].append(match)
            team_matches[away_team_id].append(match)
            latest_competition_season_id[home_team_id] = match.competition_season_id
            latest_competition_season_id[away_team_id] = match.competition_season_id

            home_score = match.score_home or 0
            away_score = match.score_away or 0
            result_home = 0.5 if home_score == away_score else (1.0 if home_score > away_score else 0.0)
            expected_home = 1.0 / (
                1.0 + 10.0 ** ((elo_ratings[away_team_id] - (elo_ratings[home_team_id] + HOME_ADVANTAGE)) / 400.0)
            )
            delta = ELO_K * (result_home - expected_home)
            elo_ratings[home_team_id] += delta
            elo_ratings[away_team_id] -= delta

        grouped_rows: dict[object | None, list[dict[str, object]]] = defaultdict(list)
        team_rows: dict[object, dict[str, object]] = {}
        for team_id, items in team_matches.items():
            recent_matches = items[-5:]
            last_match = items[-1] if items else None
            points = [self._match_points(match, team_id=team_id) for match in recent_matches]
            xg_values = [xg_by_match_id.get(match.id, (None, None)) for match in recent_matches]
            xg_for = [pair[0] if match.home_team_id == team_id else pair[1] for match, pair in zip(recent_matches, xg_values, strict=True)]
            xg_against = [pair[1] if match.home_team_id == team_id else pair[0] for match, pair in zip(recent_matches, xg_values, strict=True)]
            last_kickoff = last_match.kickoff_at.date() if last_match is not None else None
            rest_days = (target_date - last_kickoff).days if last_kickoff is not None else None
            row = {
                "team_id": team_id,
                "competition_season_id": latest_competition_season_id.get(team_id),
                "elo_rating": elo_ratings[team_id],
                "form_points_avg": mean(points),
                "xg_form_avg": mean(xg_for) if self._count_known(xg_for) >= 3 else None,
                "xga_form_avg": mean(xg_against) if self._count_known(xg_against) >= 3 else None,
                "rest_days": float(rest_days) if rest_days is not None else None,
                "matches_sampled": len(recent_matches),
            }
            team_rows[team_id] = row
            grouped_rows[row["competition_season_id"]].append(row)

        fatigue_by_team = await self._load_team_fatigue_minutes(
            target_date=target_date,
            since=target_date - timedelta(days=14),
        )

        for competition_season_id, rows in grouped_rows.items():
            elo_std = standard_deviation([safe_float(row["elo_rating"]) for row in rows])
            xg_std = standard_deviation([safe_float(row["xg_form_avg"]) for row in rows])
            form_std = standard_deviation([safe_float(row["form_points_avg"]) for row in rows])
            elo_mean = mean([safe_float(row["elo_rating"]) for row in rows])
            xg_mean = mean([safe_float(row["xg_form_avg"]) for row in rows])
            form_mean = mean([safe_float(row["form_points_avg"]) for row in rows])

            for row in rows:
                team_strength = renormalized_weighted_sum(
                    [
                        (zscore(safe_float(row["elo_rating"]), mean=elo_mean, stddev=elo_std), 0.5),
                        (zscore(safe_float(row["xg_form_avg"]), mean=xg_mean, stddev=xg_std), 0.3),
                        (zscore(safe_float(row["form_points_avg"]), mean=form_mean, stddev=form_std), 0.2),
                    ]
                )
                fatigue_minutes = fatigue_by_team.get(row["team_id"])
                await self._upsert_team_rating_row(
                    team_id=row["team_id"],
                    competition_season_id=competition_season_id,
                    target_date=target_date,
                    elo_rating=safe_float(row["elo_rating"]),
                    team_strength=team_strength,
                    form_points_avg=safe_float(row["form_points_avg"]),
                    xg_form_avg=safe_float(row["xg_form_avg"]),
                    xga_form_avg=safe_float(row["xga_form_avg"]),
                    rest_days=safe_float(row["rest_days"]),
                    fatigue_minutes_14d=fatigue_minutes,
                    matches_sampled=int(row["matches_sampled"]),
                    availability_json={
                        "xg_form_available": row["xg_form_avg"] is not None,
                        "competition_season_id": str(competition_season_id) if competition_season_id else None,
                    },
                    quality_json={},
                    source_json={"method": "elo_form_v1"},
                )

    async def _upsert_player_ratings(
        self,
        *,
        target_date: date,
        end_of_day: datetime,
    ) -> None:
        lookback_start = end_of_day - timedelta(days=365)
        result = await self.session.execute(
            select(MatchPlayerAppearance, Match.status, Match.kickoff_at)
            .join(Match, Match.id == MatchPlayerAppearance.match_id)
            .where(Match.kickoff_at >= lookback_start, Match.kickoff_at < end_of_day)
            .order_by(Match.kickoff_at.desc())
        )
        appearances_by_player: dict[object, list[tuple[MatchPlayerAppearance, MatchStatus, datetime]]] = defaultdict(list)
        for appearance, match_status, kickoff_at in result.all():
            appearances_by_player[appearance.player_id].append((appearance, match_status, kickoff_at))

        current_team_result = await self.session.execute(
            select(TeamMembership.player_id, TeamMembership.team_id, TeamMembership.role)
            .where(TeamMembership.is_current.is_(True))
        )
        current_team_map = {
            player_id: (team_id, role) for player_id, team_id, role in current_team_result.all()
        }

        for player_id, records in appearances_by_player.items():
            top_records = records[:10]
            weighted_scores: list[tuple[float | None, float]] = []
            total_minutes = 0
            last_role = None
            for appearance, match_status, kickoff_at in top_records:
                normalized_stats = {}
                metadata = appearance.metadata_json if isinstance(appearance.metadata_json, dict) else {}
                if isinstance(metadata.get("normalized_statistics"), dict):
                    normalized_stats = metadata["normalized_statistics"]
                role = appearance.position or current_team_map.get(player_id, (None, None))[1]
                last_role = role or last_role
                score = self._appearance_power_score(
                    role=role,
                    normalized_stats=normalized_stats,
                )
                minutes = appearance.minutes_played
                minutes_imputed = False
                if minutes is None and appearance.played:
                    minutes = 90 if appearance.is_starter and getattr(match_status, "value", match_status) in {"live", "finished"} else 20
                    minutes_imputed = True
                minute_weight = max(minutes or 0, 1)
                total_minutes += minutes or 0
                days_ago = max((target_date - kickoff_at.date()).days, 0)
                recency_weight = ewma_weight(days_ago, half_life_days=30.0)
                weighted_scores.append((score, minute_weight * recency_weight))
                if minutes_imputed:
                    metadata["minutes_imputed"] = True

            player_power = weighted_mean(weighted_scores)
            team_id, role_from_membership = current_team_map.get(player_id, (None, None))
            await self._upsert_player_rating_row(
                player_id=player_id,
                team_id=team_id,
                target_date=target_date,
                player_power=player_power,
                appearance_rating=player_power,
                recent_minutes=total_minutes if total_minutes > 0 else None,
                appearances_sampled=len(top_records),
                role_code=last_role or role_from_membership,
                availability_json={"recent_appearances": len(top_records)},
                quality_json={"method": "rating" if weighted_scores else "empty"},
                source_json={"method": "player_power_v1"},
            )

    async def _upsert_team_rating_row(
        self,
        *,
        team_id,
        competition_season_id,
        target_date: date,
        elo_rating: float | None,
        team_strength: float | None,
        form_points_avg: float | None,
        xg_form_avg: float | None,
        xga_form_avg: float | None,
        rest_days: float | None,
        fatigue_minutes_14d: int | None,
        matches_sampled: int,
        availability_json: dict,
        quality_json: dict,
        source_json: dict,
    ) -> None:
        result = await self.session.execute(
            select(TeamRatingDaily).where(
                TeamRatingDaily.team_id == team_id,
                TeamRatingDaily.rating_date == target_date,
                TeamRatingDaily.feature_version == self.feature_version,
            )
        )
        row = result.scalar_one_or_none()
        if row is None:
            row = TeamRatingDaily(
                team_id=team_id,
                competition_season_id=competition_season_id,
                rating_date=target_date,
                feature_version=self.feature_version,
                availability_json={},
                quality_json={},
                source_json={},
                metadata_json={},
            )
            self.session.add(row)
            self.stats.team_ratings_upserted += 1
        row.competition_season_id = competition_season_id
        row.elo_rating = elo_rating
        row.team_strength = team_strength
        row.form_points_avg = form_points_avg
        row.xg_form_avg = xg_form_avg
        row.xga_form_avg = xga_form_avg
        row.rest_days = rest_days
        row.fatigue_minutes_14d = fatigue_minutes_14d
        row.matches_sampled = matches_sampled
        row.availability_json = availability_json
        row.quality_json = quality_json
        row.source_json = source_json
        await self.session.flush()

    async def _upsert_player_rating_row(
        self,
        *,
        player_id,
        team_id,
        target_date: date,
        player_power: float | None,
        appearance_rating: float | None,
        recent_minutes: int | None,
        appearances_sampled: int,
        role_code: str | None,
        availability_json: dict,
        quality_json: dict,
        source_json: dict,
    ) -> None:
        result = await self.session.execute(
            select(PlayerRatingDaily).where(
                PlayerRatingDaily.player_id == player_id,
                PlayerRatingDaily.rating_date == target_date,
                PlayerRatingDaily.feature_version == self.feature_version,
            )
        )
        row = result.scalar_one_or_none()
        if row is None:
            row = PlayerRatingDaily(
                player_id=player_id,
                team_id=team_id,
                rating_date=target_date,
                feature_version=self.feature_version,
                availability_json={},
                quality_json={},
                source_json={},
                metadata_json={},
            )
            self.session.add(row)
            self.stats.player_ratings_upserted += 1
        row.team_id = team_id
        row.player_power = player_power
        row.appearance_rating = appearance_rating
        row.recent_minutes = recent_minutes
        row.appearances_sampled = appearances_sampled
        row.role_code = role_code
        row.availability_json = availability_json
        row.quality_json = quality_json
        row.source_json = source_json
        await self.session.flush()

    async def _load_finished_matches(self, *, before: datetime) -> list[Match]:
        result = await self.session.execute(
            select(Match)
            .where(
                Match.status == MatchStatus.finished,
                Match.kickoff_at < before,
            )
            .order_by(Match.kickoff_at.asc())
        )
        return list(result.scalars().all())

    async def _load_match_xg_totals(self, *, match_ids: list[object]) -> dict[object, tuple[float | None, float | None]]:
        if not match_ids:
            return {}
        result = await self.session.execute(
            select(MatchLiveStatFrame)
            .where(MatchLiveStatFrame.match_id.in_(match_ids))
            .order_by(MatchLiveStatFrame.match_id.asc(), MatchLiveStatFrame.tick_time.asc())
        )
        totals: dict[object, tuple[float | None, float | None]] = {}
        for frame in result.scalars().all():
            totals[frame.match_id] = (frame.home_xg, frame.away_xg)
        return totals

    async def _load_team_fatigue_minutes(
        self,
        *,
        target_date: date,
        since: date,
    ) -> dict[object, int]:
        start_dt = datetime.combine(since, datetime.min.time(), tzinfo=UTC)
        end_dt = datetime.combine(target_date + timedelta(days=1), datetime.min.time(), tzinfo=UTC)
        result = await self.session.execute(
            select(MatchPlayerAppearance, Match.status, Match.kickoff_at)
            .join(Match, Match.id == MatchPlayerAppearance.match_id)
            .where(
                Match.kickoff_at >= start_dt,
                Match.kickoff_at < end_dt,
                MatchPlayerAppearance.played.is_(True),
            )
        )
        fatigue: dict[object, int] = defaultdict(int)
        for appearance, match_status, _kickoff_at in result.all():
            minutes = appearance.minutes_played
            if minutes is None:
                status_value = getattr(match_status, "value", match_status)
                if status_value in {"live", "finished"}:
                    minutes = 90 if appearance.is_starter else 20
            fatigue[appearance.team_id] += minutes or 0
        return dict(fatigue)

    @staticmethod
    def _match_points(match: Match, *, team_id) -> float:
        home_score = match.score_home or 0
        away_score = match.score_away or 0
        if home_score == away_score:
            return 1.0
        if match.home_team_id == team_id:
            return 3.0 if home_score > away_score else 0.0
        return 3.0 if away_score > home_score else 0.0

    @staticmethod
    def _count_known(values: list[float | None]) -> int:
        return sum(1 for value in values if value is not None)

    @staticmethod
    def _appearance_power_score(*, role: str | None, normalized_stats: dict) -> float | None:
        rating = safe_float(normalized_stats.get("rating"))
        if rating is None and isinstance(normalized_stats.get("rating_versions"), dict):
            rating = safe_float(normalized_stats["rating_versions"].get("original"))
        if rating is not None:
            return max(0.0, min(100.0, rating * 10.0))

        group = role_group(role)
        goals = safe_float(normalized_stats.get("goals")) or 0.0
        assists = safe_float(
            normalized_stats.get("goal_assist") or normalized_stats.get("assists")
        ) or 0.0
        shots_on_target = safe_float(
            normalized_stats.get("shots_on_target") or normalized_stats.get("shots_ontarget")
        ) or 0.0
        accurate_pass = safe_float(normalized_stats.get("accurate_pass")) or 0.0
        key_passes = safe_float(normalized_stats.get("key_passes")) or 0.0
        tackles = safe_float(normalized_stats.get("tackles")) or 0.0
        interceptions = safe_float(normalized_stats.get("interceptions")) or 0.0
        clearances = safe_float(normalized_stats.get("clearances")) or 0.0
        saves = safe_float(normalized_stats.get("saves")) or 0.0
        goals_prevented = safe_float(normalized_stats.get("goals_prevented")) or 0.0
        clean_sheet = 1.0 if normalized_stats.get("clean_sheet") is True else 0.0

        if group == "GK":
            score = 45.0 + saves * 3.0 + goals_prevented * 10.0 + clean_sheet * 8.0
        elif group == "DEF":
            score = 45.0 + tackles * 2.0 + interceptions * 2.5 + clearances * 1.5 + goals * 6.0
        elif group == "MID":
            score = 45.0 + assists * 7.0 + key_passes * 2.5 + accurate_pass * 0.15 + goals * 6.0
        else:
            score = 45.0 + goals * 12.0 + assists * 7.0 + shots_on_target * 2.0
        return max(0.0, min(100.0, score))
