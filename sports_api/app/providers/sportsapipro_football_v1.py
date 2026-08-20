from __future__ import annotations

import asyncio
import logging
from datetime import UTC, date, datetime, timedelta

import httpx

from app.core.text import slugify_text
from app.providers.base import (
    BootstrapCategorySeed,
    BootstrapSeasonSeed,
    BootstrapTournamentSeed,
    ProviderBatch,
    ProviderClient,
    ProviderCountrySeed,
    ProviderMatchIncidentSeed,
    ProviderMatchLiveStatFrameSeed,
    ProviderMatchMarketTickSeed,
    ProviderMatchSeed,
    ProviderShotEventSeed,
    ProviderSportSeed,
    ProviderTeamSeed,
)

logger = logging.getLogger(__name__)


class SportsAPIProFootballV1Client(ProviderClient):
    slug = "sportsapipro-football-v1"
    display_name = "SportsAPI Pro Football V1"

    def __init__(self, *, settings=None) -> None:
        super().__init__(settings=settings)
        self._game_cache: dict[str, dict] = {}
        self._matchup_id_cache: dict[str, str] = {}
        self._lines_cache: dict[str, dict] = {}

    @property
    def base_url(self) -> str:
        return self.settings.sportsapipro_v1_base_url.rstrip("/")

    @property
    def headers(self) -> dict[str, str]:
        if not self.settings.sportsapipro_api_key:
            raise ValueError(
                "SPORTS_API_SPORTSAPIPRO_API_KEY is required for SportsAPI Pro requests."
            )
        return {"x-api-key": self.settings.sportsapipro_api_key}

    async def fetch(self, *, scope: str, target_date: date | None) -> ProviderBatch:
        if scope not in {"matches", "market-backfill", "context-backfill", "snapshot-live"}:
            return ProviderBatch(scope=scope, target_date=target_date)

        effective_date = target_date or date.today()
        matches = await self.get_schedule_matches(
            effective_date,
            show_odds=scope == "market-backfill",
        )
        return ProviderBatch(scope=scope, target_date=effective_date, matches=matches)

    async def get_schedule_matches(
        self,
        target_date: date,
        *,
        show_odds: bool = False,
        client: httpx.AsyncClient | None = None,
    ) -> list[ProviderMatchSeed]:
        payload = await self._get_json(
            "/games/allscores",
            params={
                "startDate": target_date.strftime("%d/%m/%Y"),
                "endDate": target_date.strftime("%d/%m/%Y"),
                "sports": 1,
                "showOdds": str(show_odds).lower(),
            },
            client=client,
        )
        countries = self._index_by_id(payload.get("countries"))
        competitions = self._index_by_id(payload.get("competitions"))
        sports = self._index_by_id(payload.get("sports"))

        matches: list[ProviderMatchSeed] = []
        for item in self._extract_games(payload):
            seed = self._build_match_seed(
                item,
                countries=countries,
                competitions=competitions,
                sports=sports,
            )
            if seed is None:
                continue
            matches.append(seed)
            self._remember_matchup_id(item)
        return matches

    async def get_prematch_markets(
        self,
        match_id: str,
    ) -> list[ProviderMatchMarketTickSeed]:
        payload = await self._get_lines_payload(match_id)
        ticks = self._extract_market_ticks(payload, match_id=match_id, phase="pre")
        if ticks:
            return ticks

        game_payload = await self._get_game_payload_for_market_fallback(match_id)
        if game_payload is None:
            return []
        game = game_payload.get("game") if isinstance(game_payload.get("game"), dict) else {}
        return self._extract_market_ticks(
            {"lines": self._game_market_lines(game)},
            match_id=match_id,
            phase="pre",
            tick_time=self._pre_market_tick_time(game),
            minute=0,
        )

    async def get_live_markets(
        self,
        match_id: str,
    ) -> list[ProviderMatchMarketTickSeed]:
        payload = await self._get_lines_payload(match_id)
        ticks = self._extract_market_ticks(payload, match_id=match_id, phase="live")
        if ticks:
            return ticks

        game_payload = await self._get_game_payload_for_market_fallback(match_id)
        if game_payload is None:
            return []
        game = game_payload.get("game") if isinstance(game_payload.get("game"), dict) else {}
        game_time = self._int_or_none(game.get("gameTime"))
        return self._extract_market_ticks(
            {"lines": self._game_market_lines(game)},
            match_id=match_id,
            phase="live",
            tick_time=self._live_market_tick_time(game),
            minute=game_time if game_time is not None and game_time >= 0 else None,
        )

    async def get_match_incidents(
        self,
        match_id: str,
    ) -> list[ProviderMatchIncidentSeed]:
        payload = await self._get_game_payload(match_id)
        game = payload.get("game") if isinstance(payload.get("game"), dict) else {}
        home_id = self._int_or_none(game.get("homeCompetitor", {}).get("id"))
        away_id = self._int_or_none(game.get("awayCompetitor", {}).get("id"))
        events = game.get("events")
        if not isinstance(events, list):
            return []

        incidents: list[ProviderMatchIncidentSeed] = []
        for item in events:
            if not isinstance(item, dict):
                continue
            event_type = item.get("eventType") if isinstance(item.get("eventType"), dict) else {}
            related_player_provider_id = None
            extra_players = item.get("extraPlayers")
            if isinstance(extra_players, list) and extra_players:
                related_player_provider_id = self._string_or_none(extra_players[0])
            incidents.append(
                ProviderMatchIncidentSeed(
                    provider_match_id=match_id,
                    provider_event_id=str(item.get("key") or f"{match_id}:{len(incidents) + 1}"),
                    incident_type=str(event_type.get("name") or item.get("type") or "unknown"),
                    incident_subtype=self._string_or_none(
                        event_type.get("subTypeName") or item.get("subType")
                    ),
                    team_side=self._resolve_team_side(
                        competitor_id=self._int_or_none(item.get("competitorId")),
                        home_id=home_id,
                        away_id=away_id,
                    ),
                    minute=self._int_or_none(item.get("gameTime")),
                    stoppage_minute=self._int_or_none(item.get("addedTime")),
                    sort_order=self._int_or_none(item.get("order")) or len(incidents) + 1,
                    player_provider_id=self._string_or_none(item.get("playerId")),
                    related_player_provider_id=related_player_provider_id,
                    player_name=self._string_or_none(item.get("playerName")),
                    related_player_name=None,
                    score_home=self._int_or_none(item.get("homeScore")),
                    score_away=self._int_or_none(item.get("awayScore")),
                    occurred_at=None,
                    raw=item,
                )
            )
        return incidents

    async def get_match_shotmap(
        self,
        match_id: str,
    ) -> list[ProviderShotEventSeed]:
        payload = await self._get_game_payload(match_id)
        game = payload.get("game") if isinstance(payload.get("game"), dict) else {}
        home_id = self._int_or_none(game.get("homeCompetitor", {}).get("id"))
        away_id = self._int_or_none(game.get("awayCompetitor", {}).get("id"))
        chart_events = self._extract_chart_events(game.get("chartEvents"))

        shots: list[ProviderShotEventSeed] = []
        for item in chart_events:
            if not isinstance(item, dict):
                continue
            outcome = item.get("outcome") if isinstance(item.get("outcome"), dict) else {}
            outcome_id = self._int_or_none(outcome.get("id"))
            shots.append(
                ProviderShotEventSeed(
                    provider_match_id=match_id,
                    provider_shot_id=str(item.get("key") or f"{match_id}:shot:{len(shots) + 1}"),
                    team_side=self._resolve_team_side(
                        competitor_id=self._int_or_none(
                            item.get("competitorId") or item.get("competitorNum")
                        ),
                        home_id=home_id,
                        away_id=away_id,
                    ),
                    minute=self._parse_chart_minute(item.get("time")),
                    second=None,
                    xg=self._float_or_none(item.get("xg")),
                    xgot=self._float_or_none(item.get("xgot")),
                    on_target=outcome_id in {0, 2},
                    resulted_in_goal=outcome_id == 0,
                    raw=item,
                )
            )
        return shots

    async def get_match_live_stats(
        self,
        match_id: str,
    ) -> list[ProviderMatchLiveStatFrameSeed]:
        payload = await self._get_game_payload(match_id)
        game = payload.get("game") if isinstance(payload.get("game"), dict) else {}
        start_time = self._parse_datetime(game.get("startTime"))
        game_time = self._int_or_none(game.get("gameTime")) or 0
        shots = await self.get_match_shotmap(match_id)

        totals_by_side = {
            "home": {"xg": 0.0, "shots": 0, "sot": 0},
            "away": {"xg": 0.0, "shots": 0, "sot": 0},
        }
        frames: list[ProviderMatchLiveStatFrameSeed] = []
        for shot in sorted(shots, key=lambda item: (item.minute or 999, item.provider_shot_id)):
            side = shot.team_side if shot.team_side in {"home", "away"} else "home"
            totals_by_side[side]["xg"] += shot.xg or 0.0
            totals_by_side[side]["shots"] += 1
            totals_by_side[side]["sot"] += 1 if shot.on_target else 0
            minute = shot.minute if shot.minute is not None else game_time
            frames.append(
                ProviderMatchLiveStatFrameSeed(
                    provider_match_id=match_id,
                    frame_time=self._frame_time(start_time, minute),
                    minute=minute,
                    home_xg=totals_by_side["home"]["xg"],
                    away_xg=totals_by_side["away"]["xg"],
                    home_shots=totals_by_side["home"]["shots"],
                    away_shots=totals_by_side["away"]["shots"],
                    home_shots_on_target=totals_by_side["home"]["sot"],
                    away_shots_on_target=totals_by_side["away"]["sot"],
                    home_pressure_index=self._pressure_index(
                        shots_total=totals_by_side["home"]["shots"],
                    ),
                    away_pressure_index=self._pressure_index(
                        shots_total=totals_by_side["away"]["shots"],
                    ),
                    raw={"shot": shot.raw},
                )
            )

        if not frames and game_time > 0:
            frames.append(
                ProviderMatchLiveStatFrameSeed(
                    provider_match_id=match_id,
                    frame_time=self._frame_time(start_time, game_time),
                    minute=game_time,
                    raw={"game": game},
                )
            )
        return frames

    async def _get_lines_payload(self, match_id: str) -> dict:
        cached = self._lines_cache.get(match_id)
        if cached is not None:
            return cached
        payload = await self._get_json("/bets/lines", params={"games": match_id})
        if isinstance(payload, dict):
            self._lines_cache[match_id] = payload
            return payload
        result = {"lines": payload if isinstance(payload, list) else []}
        self._lines_cache[match_id] = result
        return result

    async def _get_game_payload_for_market_fallback(self, match_id: str) -> dict | None:
        try:
            return await self._get_game_payload(match_id)
        except ValueError as exc:
            if "Missing matchupId cache" not in str(exc):
                raise
            logger.info(
                "sportsapipro market fallback skipped for game %s because matchup cache is missing",
                match_id,
            )
            return None

    async def _get_game_payload(self, match_id: str) -> dict:
        cached = self._game_cache.get(match_id)
        if cached is not None:
            return cached
        matchup_id = self._matchup_id_cache.get(match_id)
        if matchup_id is None:
            raise ValueError(
                f"Missing matchupId cache for game {match_id}. Run a schedule fetch first."
            )
        payload = await self._get_json("/game", params={"gameId": match_id, "matchupId": matchup_id})
        if not isinstance(payload, dict):
            raise ValueError(f"Unexpected game payload for {match_id}.")
        self._game_cache[match_id] = payload
        return payload

    def _remember_matchup_id(self, game_payload: dict) -> None:
        game_id = self._string_or_none(game_payload.get("id"))
        home_id = self._string_or_none(game_payload.get("homeCompetitor", {}).get("id"))
        away_id = self._string_or_none(game_payload.get("awayCompetitor", {}).get("id"))
        competition_id = self._string_or_none(game_payload.get("competitionId"))
        if not game_id or not home_id or not away_id or not competition_id:
            return
        self._matchup_id_cache[game_id] = f"{home_id}-{away_id}-{competition_id}"

    def _build_http_client(self) -> httpx.AsyncClient:
        timeout = httpx.Timeout(self.settings.sportsapipro_timeout_seconds)
        return httpx.AsyncClient(base_url=self.base_url, headers=self.headers, timeout=timeout)

    async def _get_json(
        self,
        path: str,
        *,
        params: dict[str, object] | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> dict | list:
        if client is not None:
            return await self._request_json(client=client, path=path, params=params)
        async with self._build_http_client() as transient_client:
            return await self._request_json(client=transient_client, path=path, params=params)

    async def _request_json(
        self,
        *,
        client: httpx.AsyncClient,
        path: str,
        params: dict[str, object] | None,
    ) -> dict | list:
        attempt = 0
        max_attempts = max(self.settings.sportsapipro_max_retries, 0) + 1
        while attempt < max_attempts:
            attempt += 1
            try:
                response = await client.get(path, params=params)
                response.raise_for_status()
                return response.json()
            except httpx.HTTPStatusError as exc:
                should_retry = exc.response.status_code in {429, 500, 502, 503, 504}
                if not should_retry or attempt >= max_attempts:
                    raise
                await asyncio.sleep(self._retry_delay_seconds(exc.response, attempt))
            except httpx.RequestError:
                if attempt >= max_attempts:
                    raise
                await asyncio.sleep(self._retry_delay_seconds(None, attempt))
            finally:
                if self.settings.sportsapipro_request_delay_seconds > 0:
                    await asyncio.sleep(self.settings.sportsapipro_request_delay_seconds)
        raise RuntimeError(f"Exhausted request attempts for {path}.")

    def _retry_delay_seconds(self, response: httpx.Response | None, attempt: int) -> float:
        if response is not None:
            retry_after = response.headers.get("Retry-After")
            if retry_after:
                try:
                    return max(float(retry_after), self.settings.sportsapipro_request_delay_seconds)
                except ValueError:
                    pass
        return max(
            self.settings.sportsapipro_retry_backoff_seconds * attempt,
            self.settings.sportsapipro_request_delay_seconds,
        )

    def _build_match_seed(
        self,
        payload: dict,
        *,
        countries: dict[int, dict],
        competitions: dict[int, dict],
        sports: dict[int, dict],
    ) -> ProviderMatchSeed | None:
        game_id = self._string_or_none(payload.get("id"))
        start_time = self._parse_datetime(payload.get("startTime"))
        if game_id is None or start_time is None:
            return None

        home_payload = (
            payload.get("homeCompetitor") if isinstance(payload.get("homeCompetitor"), dict) else None
        )
        away_payload = (
            payload.get("awayCompetitor") if isinstance(payload.get("awayCompetitor"), dict) else None
        )
        if home_payload is None or away_payload is None:
            return None

        sport_payload = sports.get(self._int_or_none(payload.get("sportId")) or -1)
        competition_payload = competitions.get(self._int_or_none(payload.get("competitionId")) or -1)
        home_team = self._build_team_seed(home_payload, countries=countries, sport_payload=sport_payload)
        away_team = self._build_team_seed(away_payload, countries=countries, sport_payload=sport_payload)
        if home_team is None or away_team is None:
            return None

        competition_seed = self._build_competition_seed(
            payload,
            competition_payload=competition_payload,
            country_payload=countries.get(self._int_or_none(payload.get("countryId")) or -1),
            sport_payload=sport_payload,
        )
        season_seed = self._build_season_seed(payload, kickoff_at=start_time)

        return ProviderMatchSeed(
            provider_match_id=game_id,
            kickoff_at=start_time,
            status=self._string_or_none(payload.get("statusText")) or "unknown",
            provider_status=self._string_or_none(payload.get("shortStatusText"))
            or self._string_or_none(payload.get("statusText")),
            home_team=home_team,
            away_team=away_team,
            competition=competition_seed,
            season=season_seed,
            venue_name=self._string_or_none(payload.get("venue", {}).get("name")),
            score_home=self._int_or_none(home_payload.get("score")),
            score_away=self._int_or_none(away_payload.get("score")),
            raw=payload,
        )

    def _build_competition_seed(
        self,
        payload: dict,
        *,
        competition_payload: dict | None,
        country_payload: dict | None,
        sport_payload: dict | None,
    ) -> BootstrapTournamentSeed | None:
        competition_id = self._string_or_none(
            payload.get("competitionId") or (competition_payload or {}).get("id")
        )
        if competition_id is None:
            return None

        competition_name = self._string_or_none((competition_payload or {}).get("name"))
        if competition_name is None:
            competition_name = self._string_or_none(payload.get("competitionDisplayName"))
        if competition_name is None:
            competition_name = f"Competition {competition_id}"

        category_seed = None
        category_id = self._string_or_none((country_payload or {}).get("id"))
        if category_id is not None:
            category_seed = BootstrapCategorySeed(
                provider_category_id=category_id,
                name=self._string_or_none((country_payload or {}).get("name")) or category_id,
                slug=self._string_or_none((country_payload or {}).get("nameForURL")),
                sport=self._build_sport_seed(sport_payload),
                country=self._build_country_seed(country_payload),
                raw=country_payload or {},
            )

        return BootstrapTournamentSeed(
            provider_tournament_id=competition_id,
            name=competition_name,
            slug=self._string_or_none((competition_payload or {}).get("nameForURL")),
            category_provider_id=category_id,
            category=category_seed,
            raw=competition_payload or payload,
        )

    def _build_season_seed(
        self,
        payload: dict,
        *,
        kickoff_at: datetime,
    ) -> BootstrapSeasonSeed | None:
        competition_id = self._string_or_none(payload.get("competitionId"))
        season_num = self._string_or_none(payload.get("seasonNum"))
        if competition_id is None or season_num is None:
            return None

        provider_season_id = f"{competition_id}:{season_num}"
        label = str(kickoff_at.year)
        return BootstrapSeasonSeed(
            provider_season_id=provider_season_id,
            tournament_provider_id=competition_id,
            name=label,
            year=label,
            raw={
                "competitionId": competition_id,
                "seasonNum": season_num,
                "startTime": payload.get("startTime"),
            },
        )

    def _build_team_seed(
        self,
        payload: dict,
        *,
        countries: dict[int, dict],
        sport_payload: dict | None,
    ) -> ProviderTeamSeed | None:
        team_id = self._string_or_none(payload.get("id"))
        name = self._string_or_none(payload.get("name"))
        if team_id is None or name is None:
            return None

        country_payload = countries.get(self._int_or_none(payload.get("countryId")) or -1)
        return ProviderTeamSeed(
            provider_team_id=team_id,
            name=name,
            slug=self._string_or_none(payload.get("nameForURL"))
            or slugify_text(name, fallback=f"team-{team_id}"),
            short_name=self._string_or_none(payload.get("symbolicName")),
            sport=self._build_sport_seed(sport_payload),
            country=self._build_country_seed(country_payload),
            national=self._int_or_none(payload.get("type")) == 2,
            team_type=self._int_or_none(payload.get("type")),
            raw=payload,
        )

    def _build_sport_seed(self, payload: dict | None) -> ProviderSportSeed | None:
        if not isinstance(payload, dict):
            return None
        name = self._string_or_none(payload.get("name"))
        if name is None:
            return None
        return ProviderSportSeed(
            provider_sport_id=self._string_or_none(payload.get("id")),
            name=name,
            slug=self._string_or_none(payload.get("nameForURL")),
            raw=payload,
        )

    def _build_country_seed(self, payload: dict | None) -> ProviderCountrySeed | None:
        if not isinstance(payload, dict):
            return None
        name = self._string_or_none(payload.get("name"))
        if name is None:
            return None
        return ProviderCountrySeed(
            provider_country_id=self._string_or_none(payload.get("id")),
            name=name,
            slug=self._string_or_none(payload.get("nameForURL")),
            raw=payload,
        )

    @classmethod
    def _extract_market_ticks(
        cls,
        payload: dict,
        *,
        match_id: str,
        phase: str,
        tick_time: datetime | None = None,
        minute: int | None = None,
    ) -> list[ProviderMatchMarketTickSeed]:
        lines = payload.get("lines")
        if not isinstance(lines, list):
            return []

        ticks: list[ProviderMatchMarketTickSeed] = []
        for line in lines:
            if not isinstance(line, dict):
                continue
            line_type = line.get("lineType") if isinstance(line.get("lineType"), dict) else {}
            market_name = cls._string_or_none(
                line_type.get("shortName") or line_type.get("title") or line_type.get("name")
            )
            if market_name is None:
                continue
            normalized_market = cls._normalize_market_name(market_name)
            options = line.get("options")
            if not isinstance(options, list):
                continue

            for option in options:
                if not isinstance(option, dict):
                    continue
                rate_payload = None
                if phase == "pre":
                    rate_payload = (
                        option.get("prematchRate")
                        if isinstance(option.get("prematchRate"), dict)
                        else None
                    )
                    if rate_payload is None:
                        rate_payload = (
                            option.get("originalRate")
                            if isinstance(option.get("originalRate"), dict)
                            else None
                        )
                if rate_payload is None:
                    rate_payload = (
                        option.get("rate") if isinstance(option.get("rate"), dict) else None
                    )
                decimal = cls._float_or_none((rate_payload or {}).get("decimal"))
                if decimal is None or decimal <= 0:
                    continue
                ticks.append(
                    ProviderMatchMarketTickSeed(
                        provider_match_id=match_id,
                        phase=phase,
                        market_type=normalized_market,
                        selection_key=cls._selection_key(
                            option.get("name"),
                            option.get("num"),
                            market_type=normalized_market,
                        ),
                        tick_time=tick_time or datetime.now(UTC),
                        minute=minute,
                        line_value=cls._line_value(line, option, normalized_market),
                        odds_decimal=decimal,
                        implied_prob=1.0 / decimal,
                        normalized_prob=None,
                        bookmaker_key=cls._string_or_none(
                            line.get("bookmakerId")
                            or option.get("bookmakerId")
                            or line.get("bookmaker", {}).get("nameForURL")
                        ),
                        suspended=bool(option.get("isSuspended") or False),
                        raw={"line": line, "option": option},
                    )
                )
        return ticks

    @staticmethod
    def _extract_games(payload: dict | list) -> list[dict]:
        if isinstance(payload, dict):
            games = payload.get("games")
            if isinstance(games, list):
                return [item for item in games if isinstance(item, dict)]
        if isinstance(payload, list):
            return [item for item in payload if isinstance(item, dict)]
        return []

    @staticmethod
    def _extract_chart_events(chart_payload: object) -> list[dict]:
        if isinstance(chart_payload, list):
            return [item for item in chart_payload if isinstance(item, dict)]
        if not isinstance(chart_payload, dict):
            return []

        for key in ("events", "items", "chartEvents", "shots"):
            value = chart_payload.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]

        events: list[dict] = []
        for value in chart_payload.values():
            if isinstance(value, list):
                events.extend(item for item in value if isinstance(item, dict) and "xg" in item)
        return events

    @staticmethod
    def _index_by_id(items: object) -> dict[int, dict]:
        if not isinstance(items, list):
            return {}
        indexed: dict[int, dict] = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            item_id = SportsAPIProFootballV1Client._int_or_none(item.get("id"))
            if item_id is not None:
                indexed[item_id] = item
        return indexed

    @staticmethod
    def _normalize_market_name(value: str) -> str:
        text = value.strip().casefold()
        if text in {"1x2", "full time result", "full-time result"}:
            return "1x2"
        if "next goal" in text or "first to score" in text or "next to score" in text:
            return "next_goal"
        if text in {"o/u", "ou"} or "over" in text or "under" in text or "total" in text:
            return "totals"
        return text.replace(" ", "_")

    @staticmethod
    def _selection_key(name: object, num: object, *, market_type: str) -> str:
        text = str(name or "").strip().casefold()
        if market_type == "totals":
            if "under" in text:
                return "under"
            if "over" in text:
                return "over"
        if market_type == "next_goal":
            if text in {"home", "1"}:
                return "home"
            if text in {"away", "2"}:
                return "away"
            if "no goal" in text or text == "none":
                return "no_goal"
        if market_type == "1x2":
            if text in {"1", "home"}:
                return "home"
            if text in {"x", "draw"}:
                return "draw"
            if text in {"2", "away"}:
                return "away"
        if "under" in text:
            return "under"
        if "over" in text:
            return "over"
        if "home" in text:
            return "home"
        if "draw" in text:
            return "draw"
        if "away" in text:
            return "away"
        if "no goal" in text:
            return "no_goal"
        if num == 1:
            return "home"
        if num == 2 and market_type == "1x2":
            return "draw"
        if num == 3:
            return "away"
        if "away" in text:
            return "away"
        return text or str(num or "unknown")

    @staticmethod
    def _game_market_lines(game_payload: dict) -> list[dict]:
        lines: list[dict] = []
        seen_line_ids: set[str] = set()

        def add_line(item: object) -> None:
            if not isinstance(item, dict):
                return
            line_id = SportsAPIProFootballV1Client._string_or_none(item.get("lineId") or item.get("id"))
            if line_id and line_id in seen_line_ids:
                return
            if line_id:
                seen_line_ids.add(line_id)
            lines.append(item)

        best_odds = game_payload.get("bestOdds")
        if isinstance(best_odds, list):
            for item in best_odds:
                add_line(item)

        predictions = (
            game_payload.get("promotedPredictions", {}).get("predictions")
            if isinstance(game_payload.get("promotedPredictions"), dict)
            else None
        )
        if isinstance(predictions, list):
            for prediction in predictions:
                if not isinstance(prediction, dict):
                    continue
                add_line(prediction.get("odds"))

        return lines

    @classmethod
    def _pre_market_tick_time(cls, game_payload: dict) -> datetime:
        start_time = cls._parse_datetime(game_payload.get("startTime"))
        if start_time is None:
            return datetime.now(UTC)
        return start_time - timedelta(minutes=1)

    @classmethod
    def _live_market_tick_time(cls, game_payload: dict) -> datetime:
        start_time = cls._parse_datetime(game_payload.get("startTime"))
        game_time = cls._int_or_none(game_payload.get("gameTime"))
        if start_time is None or game_time is None or game_time < 0:
            return datetime.now(UTC)
        return start_time + timedelta(minutes=game_time)

    @classmethod
    def _line_value(cls, line: dict, option: dict, market_type: str) -> float | None:
        if market_type != "totals":
            internal_options = line.get("internalOptions")
            if isinstance(internal_options, list) and internal_options:
                return cls._float_or_none(internal_options[0])
            return None

        for source in (
            option.get("internalOptionValue"),
            option.get("internalOption"),
            line.get("internalOptionValue"),
            line.get("internalOption"),
        ):
            value = cls._float_or_none(source)
            if value is not None:
                return value
        return None

    @staticmethod
    def _resolve_team_side(
        *,
        competitor_id: int | None,
        home_id: int | None,
        away_id: int | None,
    ) -> str | None:
        if competitor_id is None:
            return None
        if home_id is not None and competitor_id == home_id:
            return "home"
        if away_id is not None and competitor_id == away_id:
            return "away"
        if competitor_id == 1 and home_id is None:
            return "home"
        if competitor_id == 2 and away_id is None:
            return "away"
        return None

    @staticmethod
    def _parse_datetime(value: object) -> datetime | None:
        if isinstance(value, datetime):
            return value if value.tzinfo is not None else value.replace(tzinfo=UTC)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
                return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=UTC)
            except ValueError:
                return None
        return None

    @staticmethod
    def _parse_chart_minute(value: object) -> int | None:
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            if "+" in text:
                left, _, right = text.partition("+")
                try:
                    return int(left) + int(right)
                except ValueError:
                    return None
            digits = "".join(ch for ch in text if ch.isdigit())
            if digits:
                return int(digits)
        return None

    @staticmethod
    def _frame_time(start_time: datetime | None, minute: int | None) -> datetime:
        if start_time is None:
            return datetime.now(UTC)
        return start_time + timedelta(minutes=max(minute or 0, 0))

    @staticmethod
    def _pressure_index(
        *,
        dangerous_attacks: int | None = None,
        box_entries: int | None = None,
        shots_total: int | None = None,
    ) -> float | None:
        components: list[tuple[float, float]] = []
        if dangerous_attacks is not None:
            components.append((0.5, float(dangerous_attacks)))
        if box_entries is not None:
            components.append((0.3, float(box_entries)))
        if shots_total is not None:
            components.append((0.2, float(shots_total)))
        if not components:
            return None
        weight_sum = sum(weight for weight, _ in components)
        return sum(weight * value for weight, value in components) / weight_sum

    @staticmethod
    def _string_or_none(value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _int_or_none(value: object) -> int | None:
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                return int(float(text))
            except ValueError:
                return None
        return None

    @staticmethod
    def _float_or_none(value: object) -> float | None:
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            text = value.strip()
            if not text:
                return None
            try:
                return float(text)
            except ValueError:
                return None
        return None
