from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime

import httpx

from app.core.text import slugify_text
from app.providers.base import (
    BootstrapCategorySeed,
    BootstrapSeasonSeed,
    BootstrapTournamentSeed,
    ProviderBatch,
    ProviderBootstrapCatalog,
    ProviderClient,
    ProviderCountrySeed,
    ProviderMatchLineupEntrySeed,
    ProviderMatchLineupSeed,
    ProviderMatchSeed,
    ProviderPlayerSeed,
    ProviderSportSeed,
    ProviderTeamSeed,
)


class SportsAPIProFootballV2Client(ProviderClient):
    slug = "sportsapipro-football-v2"
    display_name = "SportsAPI Pro Football V2"

    @property
    def base_url(self) -> str:
        return self.settings.sportsapipro_base_url.rstrip("/")

    @property
    def headers(self) -> dict[str, str]:
        if not self.settings.sportsapipro_api_key:
            raise ValueError(
                "SPORTS_API_SPORTSAPIPRO_API_KEY is required for SportsAPI Pro requests."
            )
        return {"x-api-key": self.settings.sportsapipro_api_key}

    async def fetch(self, *, scope: str, target_date: date | None) -> ProviderBatch:
        if scope == "matches":
            effective_date = target_date or date.today()
            matches = await self.get_schedule_matches(effective_date)
            return ProviderBatch(scope=scope, target_date=effective_date, matches=matches)
        return ProviderBatch(scope=scope, target_date=target_date)

    async def bootstrap_catalog(self) -> ProviderBootstrapCatalog:
        catalog = ProviderBootstrapCatalog()

        async with self._build_http_client() as client:
            category_seeds = await self.get_extended_categories(client=client)
            catalog.categories.extend(category_seeds)

            tournament_seeds = await self._collect_tournaments(
                category_seeds=category_seeds,
                catalog=catalog,
                client=client,
            )

            seen_tournament_ids: set[str] = set()
            seen_season_ids: set[tuple[str, str]] = set()

            for tournament in tournament_seeds:
                if tournament.provider_tournament_id in seen_tournament_ids:
                    continue

                seen_tournament_ids.add(tournament.provider_tournament_id)
                catalog.tournaments.append(tournament)

                try:
                    seasons = await self.get_tournament_seasons(
                        tournament.provider_tournament_id,
                        client=client,
                    )
                except (httpx.HTTPError, ValueError) as exc:
                    catalog.errors.append(
                        "Season bootstrap failed for tournament "
                        f"{tournament.provider_tournament_id}: {exc}"
                    )
                    continue

                for season in seasons:
                    season_key = (season.tournament_provider_id, season.provider_season_id)
                    if season_key not in seen_season_ids:
                        seen_season_ids.add(season_key)
                        catalog.seasons.append(season)

        return catalog

    async def _collect_tournaments(
        self,
        *,
        category_seeds: list[BootstrapCategorySeed],
        catalog: ProviderBootstrapCatalog,
        client: httpx.AsyncClient,
    ) -> list[BootstrapTournamentSeed]:
        try:
            tournaments = await self.get_all_tournaments(client=client)
            if tournaments:
                return tournaments
        except (httpx.HTTPError, ValueError) as exc:
            catalog.errors.append(
                f"Flat tournament bootstrap failed, falling back to category requests: {exc}"
            )

        tournaments_by_id: dict[str, BootstrapTournamentSeed] = {}
        for category in category_seeds:
            try:
                category_tournaments = await self.get_category_tournaments(
                    category.provider_category_id,
                    client=client,
                )
            except (httpx.HTTPError, ValueError) as exc:
                catalog.errors.append(
                    "Tournament bootstrap failed for category "
                    f"{category.provider_category_id}: {exc}"
                )
                continue

            for tournament in category_tournaments:
                existing = tournaments_by_id.get(tournament.provider_tournament_id)
                if existing is None:
                    tournaments_by_id[tournament.provider_tournament_id] = tournament
                    continue

                if (
                    existing.category_provider_id is None
                    and tournament.category_provider_id is not None
                ):
                    existing.category_provider_id = tournament.category_provider_id

        return list(tournaments_by_id.values())

    async def get_extended_categories(
        self,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> list[BootstrapCategorySeed]:
        try:
            payload = await self._get_json("/api/countries/all", client=client)
        except (httpx.HTTPError, ValueError):
            payload = await self._get_json("/api/countries", client=client)
        seeds_by_id: dict[str, BootstrapCategorySeed] = {}
        raw_categories = self._extract_categories(payload)

        def walk(items: list[dict], parent_id: str | None = None) -> None:
            for item in items:
                if not isinstance(item, dict):
                    continue

                category_id = self._pick_first(item, "id", "categoryId", "category_id")
                name = self._pick_first(item, "name", "title")

                if category_id is not None and name:
                    category_id_str = str(category_id)
                    seeds_by_id.setdefault(
                        category_id_str,
                        self._build_category_seed(
                            item,
                            provider_category_id=category_id_str,
                            fallback_name=str(name),
                            parent_provider_category_id=parent_id,
                        ),
                    )

                next_parent = str(category_id) if category_id is not None else parent_id
                for child_key in ("categories", "subcategories", "children"):
                    children = item.get(child_key)
                    if isinstance(children, list):
                        walk(children, next_parent)

        walk(raw_categories)
        return list(seeds_by_id.values())

    async def get_all_tournaments(
        self,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> list[BootstrapTournamentSeed]:
        payload = await self._get_json("/api/tournaments", client=client)
        tournaments: list[BootstrapTournamentSeed] = []

        for item in self._extract_tournaments(payload):
            if not isinstance(item, dict):
                continue

            tournament_id = self._pick_first(item, "id", "tournamentId", "tournament_id")
            name = self._pick_first(item, "name", "title")
            if tournament_id is None or not name:
                continue

            tournaments.append(
                BootstrapTournamentSeed(
                    provider_tournament_id=str(tournament_id),
                    name=str(name),
                    slug=self._string_or_none(self._pick_first(item, "slug")),
                    category_provider_id=self._extract_category_provider_id(item),
                    category=self._extract_category_seed(item),
                    raw=item,
                )
            )

        return tournaments

    async def get_category_tournaments(
        self,
        category_id: str,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> list[BootstrapTournamentSeed]:
        payload = await self._get_json(f"/api/categories/{category_id}/tournaments", client=client)
        tournaments: list[BootstrapTournamentSeed] = []

        for item in self._extract_tournaments(payload):
            if not isinstance(item, dict):
                continue

            tournament_id = self._pick_first(item, "id", "tournamentId", "tournament_id")
            name = self._pick_first(item, "name", "title")
            if tournament_id is None or not name:
                continue

            tournaments.append(
                BootstrapTournamentSeed(
                    provider_tournament_id=str(tournament_id),
                    name=str(name),
                    slug=self._string_or_none(self._pick_first(item, "slug")),
                    category_provider_id=category_id,
                    category=self._extract_category_seed(item, default_category_id=category_id),
                    raw=item,
                )
            )

        return tournaments

    async def get_tournament_seasons(
        self,
        tournament_id: str,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> list[BootstrapSeasonSeed]:
        payload = await self._get_json(f"/api/tournaments/{tournament_id}/seasons", client=client)
        seasons: list[BootstrapSeasonSeed] = []

        for item in self._extract_seasons(payload):
            if not isinstance(item, dict):
                continue

            season_id = self._pick_first(item, "id", "seasonId", "season_id")
            name = self._pick_first(item, "name", "label", "year")
            if season_id is None or not name:
                continue

            seasons.append(
                BootstrapSeasonSeed(
                    provider_season_id=str(season_id),
                    tournament_provider_id=tournament_id,
                    name=str(name),
                    year=self._string_or_none(self._pick_first(item, "year")),
                    is_current=self._bool_or_none(self._pick_first(item, "isCurrent", "current")),
                    raw=item,
                )
            )

        return seasons

    async def get_schedule_matches(
        self,
        target_date: date,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> list[ProviderMatchSeed]:
        payload = await self._get_json(f"/api/schedule/{target_date.isoformat()}", client=client)
        matches: list[ProviderMatchSeed] = []

        for item in self._extract_schedule_events(payload):
            seed = self._build_match_seed_from_event(item)
            if seed is not None:
                matches.append(seed)

        return matches

    async def get_match_detail(
        self,
        match_id: str,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> ProviderMatchSeed | None:
        payload = await self._get_json(f"/api/match/{match_id}", client=client)
        event_payload = self._extract_match_event(payload)
        if event_payload is None:
            return None
        return self._build_match_seed_from_event(event_payload)

    async def get_team_players(
        self,
        team_provider_id: str,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> list[ProviderPlayerSeed]:
        payload = await self._get_json(f"/api/teams/{team_provider_id}/players", client=client)
        players: list[ProviderPlayerSeed] = []

        raw_items = None
        if isinstance(payload, dict):
            data = payload.get("data")
            if isinstance(data, dict):
                raw_items = data.get("players")

        if not isinstance(raw_items, list):
            return players

        for item in raw_items:
            if not isinstance(item, dict):
                continue
            player_seed = self._build_player_seed(
                item.get("player"),
                team_provider_id=team_provider_id,
                raw=item,
                squad_number=self._parse_int(
                    self._pick_first(item, "shirtNumber", "jerseyNumber")
                ),
                role=self._extract_player_role(item.get("player")),
                is_current=True,
            )
            if player_seed is not None:
                players.append(player_seed)

        return players

    async def get_match_lineup(
        self,
        match_id: str,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> ProviderMatchLineupSeed | None:
        payload = await self._get_json(f"/api/match/{match_id}/lineups", client=client)
        if not isinstance(payload, dict):
            return None

        data = payload.get("data")
        if not isinstance(data, dict):
            return None

        provider_match_id = self._pick_first(payload, "matchId") or match_id
        home_payload = data.get("home")
        away_payload = data.get("away")

        home_players = self._build_match_lineup_entries(home_payload, team_side="home")
        away_players = self._build_match_lineup_entries(away_payload, team_side="away")
        if not home_players and not away_players:
            return None

        return ProviderMatchLineupSeed(
            provider_match_id=str(provider_match_id),
            confirmed=self._bool_or_none(data.get("confirmed")),
            home_formation=self._string_or_none(
                home_payload.get("formation") if isinstance(home_payload, dict) else None
            ),
            away_formation=self._string_or_none(
                away_payload.get("formation") if isinstance(away_payload, dict) else None
            ),
            home_players=home_players,
            away_players=away_players,
            raw=payload,
        )

    def _build_http_client(self) -> httpx.AsyncClient:
        timeout = httpx.Timeout(self.settings.sportsapipro_timeout_seconds)
        return httpx.AsyncClient(base_url=self.base_url, headers=self.headers, timeout=timeout)

    async def _get_json(
        self,
        path: str,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> dict | list:
        if client is not None:
            return await self._request_json(client=client, path=path)

        async with self._build_http_client() as transient_client:
            return await self._request_json(client=transient_client, path=path)

    async def _request_json(self, *, client: httpx.AsyncClient, path: str) -> dict | list:
        attempt = 0
        max_attempts = max(self.settings.sportsapipro_max_retries, 0) + 1

        while attempt < max_attempts:
            attempt += 1
            try:
                response = await client.get(path)
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

    @staticmethod
    def _extract_categories(payload: dict | list) -> list[dict]:
        if isinstance(payload, dict):
            data = payload.get("data")
            if isinstance(data, dict):
                categories = data.get("categories")
                if isinstance(categories, list):
                    return [item for item in categories if isinstance(item, dict)]
        return SportsAPIProFootballV2Client._extract_items(payload)

    @staticmethod
    def _extract_tournaments(payload: dict | list) -> list[dict]:
        if isinstance(payload, dict):
            data = payload.get("data")
            if isinstance(data, dict):
                groups = data.get("groups")
                if isinstance(groups, list):
                    tournaments: list[dict] = []
                    for group in groups:
                        if not isinstance(group, dict):
                            continue
                        unique_tournaments = group.get("uniqueTournaments")
                        if isinstance(unique_tournaments, list):
                            tournaments.extend(
                                item for item in unique_tournaments if isinstance(item, dict)
                            )
                    if tournaments:
                        return tournaments
        return SportsAPIProFootballV2Client._extract_items(payload)

    @staticmethod
    def _extract_seasons(payload: dict | list) -> list[dict]:
        if isinstance(payload, dict):
            seasons = payload.get("seasons")
            if isinstance(seasons, list):
                return [item for item in seasons if isinstance(item, dict)]

            data = payload.get("data")
            if isinstance(data, dict):
                nested_seasons = data.get("seasons")
                if isinstance(nested_seasons, list):
                    return [item for item in nested_seasons if isinstance(item, dict)]
        return SportsAPIProFootballV2Client._extract_items(payload)

    @staticmethod
    def _extract_schedule_events(payload: dict | list) -> list[dict]:
        if isinstance(payload, dict):
            data = payload.get("data")
            if isinstance(data, dict):
                events = data.get("events")
                if isinstance(events, list):
                    return [item for item in events if isinstance(item, dict)]
        return SportsAPIProFootballV2Client._extract_items(payload)

    @staticmethod
    def _extract_match_event(payload: dict | list) -> dict | None:
        if isinstance(payload, dict):
            data = payload.get("data")
            if isinstance(data, dict):
                event = data.get("event")
                if isinstance(event, dict):
                    return event

            event = payload.get("match")
            if isinstance(event, dict):
                return event
        return None

    @staticmethod
    def _extract_items(payload: dict | list) -> list:
        if isinstance(payload, list):
            return payload

        if not isinstance(payload, dict):
            return []

        for key in (
            "data",
            "results",
            "countries",
            "categories",
            "tournaments",
            "seasons",
            "items",
        ):
            value = payload.get(key)
            if isinstance(value, list):
                return value

        for value in payload.values():
            if isinstance(value, list):
                return value

        return []

    @staticmethod
    def _pick_first(payload: dict, *keys: str):
        for key in keys:
            value = payload.get(key)
            if value is not None:
                return value
        return None

    def _extract_category_provider_id(self, payload: dict) -> str | None:
        direct_id = self._pick_first(
            payload,
            "categoryId",
            "category_id",
            "countryId",
            "country_id",
        )
        if direct_id is not None:
            return str(direct_id)

        for nested_key in ("category", "country"):
            nested_value = payload.get(nested_key)
            if isinstance(nested_value, dict):
                nested_id = self._pick_first(nested_value, "id", "categoryId", "category_id")
                if nested_id is not None:
                    return str(nested_id)

        return None

    def _build_competition_seed(self, event_payload: dict) -> BootstrapTournamentSeed | None:
        tournament_payload = event_payload.get("tournament")
        if not isinstance(tournament_payload, dict):
            return None

        unique_tournament = tournament_payload.get("uniqueTournament")
        if not isinstance(unique_tournament, dict):
            unique_tournament = tournament_payload

        tournament_id = self._pick_first(unique_tournament, "id", "tournamentId", "tournament_id")
        name = self._pick_first(unique_tournament, "name", "title") or self._pick_first(
            tournament_payload, "name", "title"
        )
        if tournament_id is None or not name:
            return None

        return BootstrapTournamentSeed(
            provider_tournament_id=str(tournament_id),
            name=str(name),
            slug=self._string_or_none(self._pick_first(unique_tournament, "slug")),
            category_provider_id=self._extract_category_provider_id(unique_tournament)
            or self._extract_category_provider_id(tournament_payload),
            category=self._extract_category_seed(unique_tournament)
            or self._extract_category_seed(tournament_payload),
            raw=tournament_payload,
        )

    def _build_season_seed(self, event_payload: dict) -> BootstrapSeasonSeed | None:
        season_payload = event_payload.get("season")
        if not isinstance(season_payload, dict):
            return None

        season_id = self._pick_first(season_payload, "id", "seasonId", "season_id")
        name = self._pick_first(season_payload, "name", "label", "year")
        tournament_id = None
        tournament_payload = event_payload.get("tournament")
        if isinstance(tournament_payload, dict):
            unique_tournament = tournament_payload.get("uniqueTournament")
            if isinstance(unique_tournament, dict):
                tournament_id = self._pick_first(
                    unique_tournament,
                    "id",
                    "tournamentId",
                    "tournament_id",
                )
            if tournament_id is None:
                tournament_id = self._pick_first(
                    tournament_payload,
                    "id",
                    "tournamentId",
                    "tournament_id",
                )

        if season_id is None or not name or tournament_id is None:
            return None

        return BootstrapSeasonSeed(
            provider_season_id=str(season_id),
            tournament_provider_id=str(tournament_id),
            name=str(name),
            year=self._string_or_none(self._pick_first(season_payload, "year")),
            is_current=self._bool_or_none(self._pick_first(season_payload, "isCurrent", "current")),
            raw=season_payload,
        )

    def _build_match_seed_from_event(self, event_payload: dict) -> ProviderMatchSeed | None:
        if not isinstance(event_payload, dict):
            return None

        match_id = self._pick_first(event_payload, "id", "matchId", "eventId")
        start_timestamp = self._pick_first(event_payload, "startTimestamp", "kickoffTimestamp")
        home_team_payload = event_payload.get("homeTeam")
        away_team_payload = event_payload.get("awayTeam")

        if (
            match_id is None
            or start_timestamp is None
            or not isinstance(home_team_payload, dict)
            or not isinstance(away_team_payload, dict)
        ):
            return None

        competition_seed = self._build_competition_seed(event_payload)
        season_seed = self._build_season_seed(event_payload)
        home_team_seed = self._build_team_seed(home_team_payload)
        away_team_seed = self._build_team_seed(away_team_payload)

        if home_team_seed is None or away_team_seed is None:
            return None

        kickoff_at = datetime.fromtimestamp(int(start_timestamp), tz=UTC)
        status_payload = event_payload.get("status")
        status_type = None
        status_description = None
        if isinstance(status_payload, dict):
            status_type = self._string_or_none(self._pick_first(status_payload, "type"))
            status_description = self._string_or_none(
                self._pick_first(status_payload, "description", "name")
            )

        return ProviderMatchSeed(
            provider_match_id=str(match_id),
            kickoff_at=kickoff_at,
            status=status_type or "unknown",
            provider_status=status_description or status_type,
            home_team=home_team_seed,
            away_team=away_team_seed,
            competition=competition_seed,
            season=season_seed,
            venue_name=self._extract_venue_name(event_payload),
            score_home=self._extract_score(event_payload.get("homeScore")),
            score_away=self._extract_score(event_payload.get("awayScore")),
            raw=event_payload,
        )

    def _build_team_seed(self, payload: dict) -> ProviderTeamSeed | None:
        team_id = self._pick_first(payload, "id", "teamId", "team_id")
        name = self._pick_first(payload, "name", "title")
        if team_id is None or not name:
            return None

        country_seed = None
        country_payload = payload.get("country")
        if isinstance(country_payload, dict) and country_payload.get("name"):
            country_seed = self._build_country_seed(country_payload)

        return ProviderTeamSeed(
            provider_team_id=str(team_id),
            name=str(name),
            slug=self._string_or_none(self._pick_first(payload, "slug"))
            or slugify_text(str(name), fallback=f"team-{team_id}"),
            short_name=self._string_or_none(self._pick_first(payload, "shortName", "nameCode")),
            sport=self._build_sport_seed(payload.get("sport")),
            country=country_seed,
            gender=self._string_or_none(payload.get("gender")),
            national=self._bool_or_none(payload.get("national")),
            team_type=self._int_or_none(payload.get("type")),
            raw=payload,
        )

    def _build_player_seed(
        self,
        payload: object,
        *,
        team_provider_id: str | None,
        raw: dict,
        squad_number: int | None,
        role: str | None,
        is_current: bool | None,
    ) -> ProviderPlayerSeed | None:
        if not isinstance(payload, dict):
            return None

        player_id = self._pick_first(payload, "id", "playerId", "player_id")
        name = self._pick_first(payload, "name", "fullName", "full_name")
        if player_id is None or not name:
            return None

        resolved_squad_number = squad_number
        if resolved_squad_number is None:
            resolved_squad_number = self._parse_int(
                self._pick_first(payload, "shirtNumber", "jerseyNumber")
            )

        return ProviderPlayerSeed(
            provider_player_id=str(player_id),
            full_name=str(name),
            short_name=self._string_or_none(
                self._pick_first(payload, "shortName", "displayName")
            ),
            slug=self._string_or_none(self._pick_first(payload, "slug")),
            date_of_birth=self._parse_player_birth_date(payload),
            country=self._build_country_seed(payload.get("country")),
            team_provider_id=team_provider_id,
            squad_number=resolved_squad_number,
            role=role,
            is_current=is_current,
            raw=raw,
        )

    def _build_match_lineup_entries(
        self,
        side_payload: object,
        *,
        team_side: str,
    ) -> list[ProviderMatchLineupEntrySeed]:
        if not isinstance(side_payload, dict):
            return []

        players_payload = side_payload.get("players")
        if not isinstance(players_payload, list):
            return []

        entries: list[ProviderMatchLineupEntrySeed] = []
        for item in players_payload:
            if not isinstance(item, dict):
                continue

            player_seed = self._build_player_seed(
                item.get("player"),
                team_provider_id=self._string_or_none(self._pick_first(item, "teamId")),
                raw=item,
                squad_number=self._parse_int(
                    self._pick_first(item, "shirtNumber", "jerseyNumber")
                ),
                role=self._string_or_none(self._pick_first(item, "position")),
                is_current=True,
            )
            if player_seed is None:
                continue

            is_substitute = bool(item.get("substitute"))
            played = bool(item.get("played"))
            statistics = item.get("statistics")
            entries.append(
                ProviderMatchLineupEntrySeed(
                    player=player_seed,
                    team_side=team_side,
                    is_starter=not is_substitute,
                    is_substitute=is_substitute,
                    played=played,
                    minutes_played=self._parse_int(item.get("minutesPlayed")),
                    position=self._string_or_none(self._pick_first(item, "position")),
                    squad_number=player_seed.squad_number,
                    statistics=statistics if isinstance(statistics, dict) else {},
                    raw=item,
                )
            )

        return entries

    def _extract_category_seed(
        self,
        payload: dict,
        *,
        default_category_id: str | None = None,
    ) -> BootstrapCategorySeed | None:
        category_payload = payload.get("category") if isinstance(payload, dict) else None
        if not isinstance(category_payload, dict):
            return None

        category_id = self._pick_first(category_payload, "id", "categoryId", "category_id")
        if category_id is None:
            category_id = default_category_id

        name = self._pick_first(category_payload, "name", "title")
        if category_id is None or not name:
            return None

        return self._build_category_seed(
            category_payload,
            provider_category_id=str(category_id),
            fallback_name=str(name),
        )

    def _build_category_seed(
        self,
        payload: dict,
        *,
        provider_category_id: str,
        fallback_name: str,
        parent_provider_category_id: str | None = None,
    ) -> BootstrapCategorySeed:
        return BootstrapCategorySeed(
            provider_category_id=provider_category_id,
            name=str(self._pick_first(payload, "name", "title") or fallback_name),
            slug=self._string_or_none(self._pick_first(payload, "slug")),
            sport=self._build_sport_seed(payload.get("sport")),
            country=self._build_country_seed(payload.get("country")),
            priority=self._int_or_none(payload.get("priority")),
            flag=self._string_or_none(payload.get("flag")),
            parent_provider_category_id=parent_provider_category_id,
            raw=payload,
        )

    def _build_sport_seed(self, payload: object) -> ProviderSportSeed | None:
        if not isinstance(payload, dict):
            return None

        name = self._pick_first(payload, "name", "title")
        if not name:
            return None

        sport_id = self._pick_first(payload, "id", "sportId", "sport_id")
        return ProviderSportSeed(
            provider_sport_id=str(sport_id) if sport_id is not None else None,
            name=str(name),
            slug=self._string_or_none(self._pick_first(payload, "slug", "nameForURL")),
            raw=payload,
        )

    def _build_country_seed(self, payload: object) -> ProviderCountrySeed | None:
        if not isinstance(payload, dict):
            return None

        name = self._pick_first(payload, "name", "title")
        if not name:
            return None

        country_id = self._pick_first(payload, "id", "countryId", "country_id")
        return ProviderCountrySeed(
            provider_country_id=str(country_id) if country_id is not None else None,
            name=str(name),
            slug=self._string_or_none(self._pick_first(payload, "slug", "nameForURL")),
            iso_code2=self._string_or_none(
                self._pick_first(payload, "alpha2", "code", "countryCode", "country_code")
            ),
            iso_code3=self._string_or_none(self._pick_first(payload, "alpha3", "iso3")),
            raw=payload,
        )

    def _extract_player_role(self, payload: object) -> str | None:
        if not isinstance(payload, dict):
            return None

        detailed_positions = payload.get("positionsDetailed")
        if isinstance(detailed_positions, list) and detailed_positions:
            first_position = detailed_positions[0]
            if isinstance(first_position, dict):
                return self._string_or_none(
                    self._pick_first(first_position, "abbreviation", "code", "name")
                )
            return self._string_or_none(first_position)

        return self._string_or_none(self._pick_first(payload, "position"))

    @staticmethod
    def _extract_venue_name(event_payload: dict) -> str | None:
        venue = event_payload.get("venue")
        if isinstance(venue, dict):
            name = venue.get("name")
            if isinstance(name, str) and name.strip():
                return name.strip()
        return None

    @staticmethod
    def _extract_score(score_payload: object) -> int | None:
        if isinstance(score_payload, int):
            return score_payload
        if isinstance(score_payload, dict):
            for key in ("current", "display", "normalTime", "score"):
                value = score_payload.get(key)
                if isinstance(value, int):
                    return value
        return None

    @staticmethod
    def _parse_player_birth_date(player_payload: dict) -> date | None:
        value = player_payload.get("dateOfBirth")
        if isinstance(value, str) and value.strip():
            try:
                return datetime.fromisoformat(value.strip()).date()
            except ValueError:
                pass

        timestamp = player_payload.get("dateOfBirthTimestamp")
        if isinstance(timestamp, int):
            return datetime.fromtimestamp(timestamp, tz=UTC).date()
        if isinstance(timestamp, str):
            text = timestamp.strip()
            if text.isdigit():
                return datetime.fromtimestamp(int(text), tz=UTC).date()
        return None

    @staticmethod
    def _parse_int(value: object) -> int | None:
        if isinstance(value, int):
            return value
        if isinstance(value, str):
            text = value.strip()
            if text.isdigit():
                return int(text)
        return None

    @staticmethod
    def _int_or_none(value: object) -> int | None:
        if value is None:
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, str):
            text = value.strip()
            if text.isdigit():
                return int(text)
        return None

    @staticmethod
    def _string_or_none(value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _bool_or_none(value: object) -> bool | None:
        if value is None:
            return None
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            lowered = value.strip().lower()
            if lowered in {"true", "1", "yes"}:
                return True
            if lowered in {"false", "0", "no"}:
                return False
        return None
