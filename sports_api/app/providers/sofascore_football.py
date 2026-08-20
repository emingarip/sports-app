from __future__ import annotations

import asyncio
import inspect
import json
import logging
import random
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from functools import partial

from app.providers.base import (
    ProviderBatch,
    ProviderBootstrapCatalog,
    ProviderCountrySeed,
    ProviderMatchLineupEntrySeed,
    ProviderMatchLineupSeed,
    ProviderMatchSeed,
    ProviderPlayerSeed,
)
from app.providers.sportsapipro_football_v2 import SportsAPIProFootballV2Client

logger = logging.getLogger(__name__)


class SofascoreRequestError(RuntimeError):
    def __init__(self, *, path: str, status_code: int, body: str | None = None) -> None:
        self.path = path
        self.status_code = status_code
        self.body = body
        super().__init__(f"Sofascore request failed for {path}: {status_code}")


class SofascoreFootballClient(SportsAPIProFootballV2Client):
    slug = "sofascore-football"
    display_name = "Sofascore Football"

    def __init__(self, *, settings=None) -> None:
        super().__init__(settings=settings)
        self._playwright = None
        self._browser = None
        self._context = None
        self._page = None
        self._sync_playwright = None
        self._sync_browser = None
        self._sync_context = None
        self._sync_page = None
        self._sync_executor: ThreadPoolExecutor | None = None
        self._sleep = asyncio.sleep
        self._random_uniform = random.uniform
        self._last_prepared_page_url: str | None = None
        self._sync_last_prepared_page_url: str | None = None

    @property
    def base_url(self) -> str:
        return self.settings.sofascore_base_url.rstrip("/")

    @property
    def headers(self) -> dict[str, str]:
        return {"User-Agent": "Mozilla/5.0"}

    async def fetch(self, *, scope: str, target_date: date | None) -> ProviderBatch:
        if scope != "matches":
            raise NotImplementedError(
                "Sofascore provider currently supports only matches schedule scraping."
            )

        effective_date = target_date or date.today()
        matches = await self.get_schedule_matches(effective_date)
        return ProviderBatch(scope=scope, target_date=effective_date, matches=matches)

    async def bootstrap_catalog(self) -> ProviderBootstrapCatalog:
        raise NotImplementedError("Sofascore bootstrap discovery is not implemented.")

    async def get_extended_categories(self, *, client=None):
        raise NotImplementedError("Sofascore bootstrap discovery is not implemented.")

    async def get_all_tournaments(self, *, client=None):
        raise NotImplementedError("Sofascore bootstrap discovery is not implemented.")

    async def get_tournament_seasons(self, tournament_id: str, *, client=None):
        raise NotImplementedError("Sofascore bootstrap discovery is not implemented.")

    async def get_schedule_matches(
        self,
        target_date: date,
        *,
        client=None,
    ) -> list[ProviderMatchSeed]:
        logger.info(
            "sofascore schedule fetch started target_date=%s",
            target_date.isoformat(),
        )
        await self._emit_progress(
            message=f"Sofascore schedule fetch started for {target_date.isoformat()}.",
        )
        payload = await self._get_json_via_browser(
            f"/api/v1/sport/football/scheduled-events/{target_date.isoformat()}"
        )
        matches: list[ProviderMatchSeed] = []
        for item in self._extract_schedule_events(payload):
            seed = self._build_match_seed_from_event(item)
            if seed is not None:
                matches.append(seed)
        logger.info(
            "sofascore schedule fetch finished target_date=%s matches=%s",
            target_date.isoformat(),
            len(matches),
        )
        await self._emit_progress(
            message=(
                f"Sofascore schedule fetch finished for {target_date.isoformat()}. "
                f"matches={len(matches)}"
            ),
        )
        return matches

    async def get_team_players(self, team_provider_id: str) -> list[ProviderPlayerSeed]:
        logger.info("sofascore team players fetch started team_provider_id=%s", team_provider_id)
        await self._emit_progress(
            message=f"Sofascore team players fetch started team_provider_id={team_provider_id}.",
        )
        payload = await self._get_json_via_browser(f"/api/v1/team/{team_provider_id}/players")
        players: list[ProviderPlayerSeed] = []
        raw_items = payload.get("players") if isinstance(payload, dict) else None
        if not isinstance(raw_items, list):
            return players

        for item in raw_items:
            if not isinstance(item, dict):
                continue
            raw_player = item.get("player")
            if not isinstance(raw_player, dict):
                continue

            player_id = raw_player.get("id")
            name = raw_player.get("name")
            if player_id is None or not name:
                continue

            country = self._build_country_seed(raw_player.get("country"))
            role = None
            positions_detailed = raw_player.get("positionsDetailed")
            if isinstance(positions_detailed, list) and positions_detailed:
                role = str(positions_detailed[0])
            elif raw_player.get("position"):
                role = str(raw_player["position"])

            players.append(
                ProviderPlayerSeed(
                    provider_player_id=str(player_id),
                    full_name=str(name),
                    short_name=self._string_or_none(raw_player.get("shortName")),
                    slug=self._string_or_none(raw_player.get("slug")),
                    date_of_birth=self._parse_player_birth_date(raw_player),
                    country=country,
                    team_provider_id=str(team_provider_id),
                    squad_number=self._parse_int(
                        raw_player.get("shirtNumber") or raw_player.get("jerseyNumber")
                    ),
                    role=role,
                    is_current=True,
                    raw=raw_player,
                )
            )
        logger.info(
            "sofascore team players fetch finished team_provider_id=%s players=%s",
            team_provider_id,
            len(players),
        )
        await self._emit_progress(
            message=(
                f"Sofascore team players fetch finished team_provider_id={team_provider_id} "
                f"players={len(players)}."
            ),
        )
        return players

    async def get_match_lineup(self, match_id: str) -> ProviderMatchLineupSeed | None:
        logger.info("sofascore match lineup fetch started match_id=%s", match_id)
        await self._emit_progress(message=f"Sofascore match lineup fetch started match_id={match_id}.")
        payload = await self._get_json_via_browser(
            f"/api/v1/event/{match_id}/lineups",
            allow_not_found=True,
        )
        if payload is None:
            logger.info("sofascore match lineup missing match_id=%s", match_id)
            await self._emit_progress(
                message=f"Sofascore match lineup missing for match_id={match_id}.",
            )
            return None
        if not isinstance(payload, dict):
            logger.warning("sofascore match lineup payload is not dict match_id=%s", match_id)
            await self._emit_progress(message=f"Sofascore match lineup payload invalid for match_id={match_id}.")
            return None

        home_payload = self._extract_lineup_side(payload, "home")
        away_payload = self._extract_lineup_side(payload, "away")
        home_players = self._build_match_lineup_entries(home_payload, team_side="home")
        away_players = self._build_match_lineup_entries(away_payload, team_side="away")
        if not home_players and not away_players:
            logger.warning("sofascore match lineup empty match_id=%s", match_id)
            await self._emit_progress(message=f"Sofascore match lineup empty for match_id={match_id}.")
            return None

        provider_match_id = payload.get("eventId") or payload.get("id") or match_id
        logger.info(
            "sofascore match lineup fetch finished match_id=%s provider_match_id=%s home_players=%s away_players=%s",
            match_id,
            provider_match_id,
            len(home_players),
            len(away_players),
        )
        await self._emit_progress(
            message=(
                f"Sofascore match lineup fetch finished match_id={match_id} "
                f"home_players={len(home_players)} away_players={len(away_players)}."
            ),
        )
        return ProviderMatchLineupSeed(
            provider_match_id=str(provider_match_id),
            confirmed=self._parse_confirmed_flag(payload),
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

    async def get_match_event(self, match_id: str) -> dict | None:
        logger.info("sofascore match event fetch started match_id=%s", match_id)
        payload = await self._get_json_via_browser(
            f"/api/v1/event/{match_id}",
            allow_not_found=True,
        )
        if not isinstance(payload, dict):
            return None
        return payload

    async def aclose(self) -> None:
        if self._use_threaded_playwright():
            if self._sync_executor is not None:
                await self._run_sync_browser_call(self._sync_stop_playwright)
                self._sync_executor.shutdown(wait=True, cancel_futures=False)
                self._sync_executor = None
            return

        await self._reset_browser_session()
        if self._playwright is not None:
            await self._playwright.stop()
            self._playwright = None

    async def _get_json_via_browser(
        self,
        path: str,
        *,
        allow_not_found: bool = False,
    ) -> dict | list | None:
        attempts = max(1, int(self.settings.sofascore_max_retries))
        last_error: Exception | None = None
        logger.info("sofascore request started path=%s attempts=%s", path, attempts)
        await self._emit_progress(
            message=f"Sofascore request started path={path} attempts={attempts}.",
            path=path,
            attempts=attempts,
        )

        for attempt in range(1, attempts + 1):
            try:
                logger.info("sofascore request attempt path=%s attempt=%s", path, attempt)
                await self._emit_progress(
                    message=f"Sofascore request attempt {attempt}/{attempts} for {path}.",
                    path=path,
                    attempt=attempt,
                    attempts=attempts,
                )
                result = await self._fetch_json_via_browser_once(path)
            except Exception as exc:
                last_error = exc
                logger.warning(
                    "sofascore request transport error path=%s attempt=%s error=%s",
                    path,
                    attempt,
                    exc,
                )
                if attempt >= attempts:
                    logger.exception(
                        "sofascore request exhausted after transport error path=%s attempt=%s",
                        path,
                        attempt,
                    )
                    await self._emit_progress(
                        message=f"Sofascore request crashed for {path}: {exc}",
                        path=path,
                        attempt=attempt,
                        attempts=attempts,
                        error=str(exc),
                    )
                    raise
                await self._reset_browser_session()
                retry_delay = self._retry_delay_seconds(status_code=None, attempt=attempt)
                await self._emit_progress(
                    message=(
                        f"Sofascore transport error for {path}. "
                        f"Retrying in {retry_delay:.1f}s ({attempt}/{attempts})."
                    ),
                    path=path,
                    attempt=attempt,
                    attempts=attempts,
                    wait_seconds=retry_delay,
                    error=str(exc),
                )
                await self._sleep(retry_delay)
                continue

            status = int(result["status"])
            if status == 200:
                logger.info("sofascore request succeeded path=%s attempt=%s status=%s", path, attempt, status)
                await self._emit_progress(
                    message=f"Sofascore request succeeded for {path} on attempt {attempt}/{attempts}.",
                    path=path,
                    attempt=attempt,
                    attempts=attempts,
                    status_code=status,
                )
                return json.loads(result["text"])

            if allow_not_found and status == 404:
                logger.info(
                    "sofascore request missing path=%s attempt=%s status=%s referrer=%s body=%s",
                    path,
                    attempt,
                    status,
                    self._page_url_for_path(path),
                    self._short_body_preview(result.get("text")),
                )
                await self._emit_progress(
                    message=f"Sofascore request missing for {path}.",
                    path=path,
                    attempt=attempt,
                    attempts=attempts,
                    status_code=status,
                )
                return None

            error = SofascoreRequestError(
                path=path,
                status_code=status,
                body=result.get("text"),
            )
            logger.warning(
                "sofascore request non-200 path=%s attempt=%s status=%s referrer=%s body=%s",
                path,
                attempt,
                status,
                self._page_url_for_path(path),
                self._short_body_preview(result.get("text")),
            )
            if status not in {403, 429} or attempt >= attempts:
                logger.error(
                    "sofascore request failed path=%s attempt=%s status=%s body=%s",
                    path,
                    attempt,
                    status,
                    self._short_body_preview(result.get("text")),
                )
                await self._emit_progress(
                    message=f"Sofascore request failed for {path} with status={status}.",
                    path=path,
                    attempt=attempt,
                    attempts=attempts,
                    status_code=status,
                    error=self._short_body_preview(result.get("text")),
                )
                raise error

            last_error = error
            await self._reset_browser_session()
            retry_delay = self._retry_delay_seconds(status_code=status, attempt=attempt)
            await self._emit_progress(
                message=(
                    f"Sofascore returned {status} for {path}. "
                    f"Retrying in {retry_delay:.1f}s ({attempt}/{attempts})."
                ),
                path=path,
                attempt=attempt,
                attempts=attempts,
                status_code=status,
                wait_seconds=retry_delay,
                error=self._short_body_preview(result.get("text")),
            )
            await self._sleep(retry_delay)

        if last_error is not None:
            raise last_error
        raise RuntimeError(f"Sofascore request failed for {path}")

    async def _fetch_json_via_browser_once(self, path: str) -> dict[str, object]:
        if self._use_threaded_playwright():
            return await self._run_sync_browser_call(self._sync_fetch_json_via_browser_once, path)

        page = await self._get_or_create_page()
        await self._prepare_page_for_path(page, path)
        result = await page.evaluate(
            """
            async ({ path, referrer }) => {
              const response = await fetch(path, {
                method: "GET",
                credentials: "include",
                referrer,
                referrerPolicy: "strict-origin-when-cross-origin",
                headers: { "accept": "application/json" },
              });
              return {
                status: response.status,
                text: await response.text(),
              };
            }
            """,
            {"path": path, "referrer": self._page_url_for_path(path)},
        )
        if not isinstance(result, dict):
            raise RuntimeError(f"Unexpected Sofascore response for {path}")
        return result

    async def _get_or_create_page(self):
        if self._page is not None:
            return self._page

        try:
            from playwright.async_api import async_playwright
        except ImportError as exc:
            raise RuntimeError(
                "Playwright is required for Sofascore scraping. "
                "Install the optional scrape dependencies and Chromium first."
            ) from exc

        try:
            if self._playwright is None:
                self._playwright = await async_playwright().start()
            if self._browser is None:
                self._browser = await self._playwright.chromium.launch(
                    headless=self.settings.sofascore_browser_headless
                )
            if self._context is None:
                self._context = await self._browser.new_context(
                    user_agent=self.headers["User-Agent"],
                    locale="en-US",
                )
            if self._page is None:
                self._page = await self._context.new_page()
                await self._prepare_page_for_url(self._page, f"{self.base_url}/", initial=True)
        except PermissionError as exc:
            raise RuntimeError(f"Playwright browser launch failed: {exc}") from exc
        return self._page

    async def _reset_browser_session(self) -> None:
        if self._use_threaded_playwright():
            if self._sync_executor is not None:
                await self._run_sync_browser_call(self._sync_reset_browser_session)
            return

        if self._page is not None:
            await self._page.close()
            self._page = None
            self._last_prepared_page_url = None
        if self._context is not None:
            await self._context.close()
            self._context = None
        if self._browser is not None:
            await self._browser.close()
            self._browser = None

    def _use_threaded_playwright(self) -> bool:
        return sys.platform.startswith("win")

    async def _run_sync_browser_call(self, func, *args):
        loop = asyncio.get_running_loop()
        if self._sync_executor is None:
            self._sync_executor = ThreadPoolExecutor(
                max_workers=1,
                thread_name_prefix="sofascore-playwright",
            )
        return await loop.run_in_executor(self._sync_executor, partial(func, *args))

    def _sync_fetch_json_via_browser_once(self, path: str) -> dict[str, object]:
        page = self._sync_get_or_create_page()
        self._sync_prepare_page_for_path(page, path)
        result = page.evaluate(
            """
            async ({ path, referrer }) => {
              const response = await fetch(path, {
                method: "GET",
                credentials: "include",
                referrer,
                referrerPolicy: "strict-origin-when-cross-origin",
                headers: { "accept": "application/json" },
              });
              return {
                status: response.status,
                text: await response.text(),
              };
            }
            """,
            {"path": path, "referrer": self._page_url_for_path(path)},
        )
        if not isinstance(result, dict):
            raise RuntimeError(f"Unexpected Sofascore response for {path}")
        return result

    def _sync_get_or_create_page(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError as exc:
            raise RuntimeError(
                "Playwright is required for Sofascore scraping. "
                "Install the optional scrape dependencies and Chromium first."
            ) from exc

        try:
            if self._sync_playwright is None:
                self._sync_playwright = sync_playwright().start()
            if self._sync_browser is None:
                self._sync_browser = self._sync_playwright.chromium.launch(
                    headless=self.settings.sofascore_browser_headless
                )
            if self._sync_context is None:
                self._sync_context = self._sync_browser.new_context(
                    user_agent=self.headers["User-Agent"],
                    locale="en-US",
                )
            if self._sync_page is None:
                self._sync_page = self._sync_context.new_page()
                self._sync_prepare_page_for_url(self._sync_page, f"{self.base_url}/", initial=True)
        except PermissionError as exc:
            raise RuntimeError(f"Playwright browser launch failed: {exc}") from exc
        return self._sync_page

    def _sync_reset_browser_session(self) -> None:
        if self._sync_page is not None:
            self._sync_page.close()
            self._sync_page = None
            self._sync_last_prepared_page_url = None
        if self._sync_context is not None:
            self._sync_context.close()
            self._sync_context = None
        if self._sync_browser is not None:
            self._sync_browser.close()
            self._sync_browser = None

    def _sync_stop_playwright(self) -> None:
        self._sync_reset_browser_session()
        if self._sync_playwright is not None:
            self._sync_playwright.stop()
            self._sync_playwright = None

    def _retry_delay_seconds(self, *, status_code: int | None, attempt: int) -> float:
        if status_code == 403:
            base = max(self.settings.sofascore_forbidden_backoff_seconds, 0.0)
        else:
            base = max(self.settings.sofascore_retry_backoff_seconds * attempt, 0.0)
        jitter = self._random_uniform(0.0, min(base, 5.0)) if base > 0 else 0.0
        return base + jitter

    async def _prepare_page_for_path(self, page, path: str) -> None:
        await self._prepare_page_for_url(page, self._page_url_for_path(path))

    async def _prepare_page_for_url(self, page, url: str, *, initial: bool = False) -> None:
        if not initial and self._last_prepared_page_url == url:
            logger.info("sofascore page reuse url=%s", url)
            await self._sleep(self._request_delay_seconds())
            return

        logger.info("sofascore page navigate url=%s initial=%s", url, initial)
        await page.goto(url, wait_until="domcontentloaded")
        await page.wait_for_timeout(int(self.settings.sofascore_browser_wait_seconds * 1000))
        self._last_prepared_page_url = url
        await self._sleep(self._request_delay_seconds())

    def _sync_prepare_page_for_path(self, page, path: str) -> None:
        self._sync_prepare_page_for_url(page, self._page_url_for_path(path))

    def _sync_prepare_page_for_url(self, page, url: str, *, initial: bool = False) -> None:
        if not initial and self._sync_last_prepared_page_url == url:
            logger.info("sofascore sync page reuse url=%s", url)
            delay = self._request_delay_seconds()
            if delay > 0:
                page.wait_for_timeout(int(delay * 1000))
            return

        logger.info("sofascore sync page navigate url=%s initial=%s", url, initial)
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_timeout(int(self.settings.sofascore_browser_wait_seconds * 1000))
        self._sync_last_prepared_page_url = url
        delay = self._request_delay_seconds()
        if delay > 0:
            page.wait_for_timeout(int(delay * 1000))

    def _request_delay_seconds(self) -> float:
        base = max(self.settings.sofascore_request_delay_seconds, 0.0)
        jitter_cap = max(self.settings.sofascore_request_jitter_seconds, 0.0)
        if jitter_cap <= 0:
            return base
        return base + self._random_uniform(0.0, jitter_cap)

    def _page_url_for_path(self, path: str) -> str:
        schedule_match = re.match(
            r"^/api/v1/sport/football/scheduled-events/(?P<date>\d{4}-\d{2}-\d{2})$",
            path,
        )
        if schedule_match:
            return f"{self.base_url}/football/{schedule_match.group('date')}"
        return f"{self.base_url}/"

    @staticmethod
    def _short_body_preview(body: object, *, limit: int = 240) -> str | None:
        if body is None:
            return None
        text = str(body).replace("\n", " ").replace("\r", " ").strip()
        if len(text) <= limit:
            return text
        return f"{text[:limit]}..."

    async def _emit_progress(self, **payload) -> None:
        reporter = getattr(self, "progress_reporter", None)
        if reporter is None:
            return
        result = reporter(payload)
        if inspect.isawaitable(result):
            await result

    @staticmethod
    def _build_country_seed(raw_country: object) -> ProviderCountrySeed | None:
        if not isinstance(raw_country, dict):
            return None

        name = raw_country.get("name")
        if not name:
            return None

        return ProviderCountrySeed(
            provider_country_id=str(raw_country["id"]) if raw_country.get("id") is not None else None,
            name=str(name),
            slug=raw_country.get("slug"),
            iso_code2=raw_country.get("alpha2"),
            iso_code3=raw_country.get("alpha3"),
            raw=raw_country,
        )

    @staticmethod
    def _parse_player_birth_date(raw_player: dict) -> date | None:
        raw_value = raw_player.get("dateOfBirth")
        if isinstance(raw_value, str):
            try:
                return datetime.fromisoformat(raw_value).date()
            except ValueError:
                pass

        timestamp = raw_player.get("dateOfBirthTimestamp")
        if isinstance(timestamp, int | float):
            try:
                return datetime.utcfromtimestamp(timestamp).date()
            except (OverflowError, OSError, ValueError):
                return None
        return None

    @staticmethod
    def _parse_int(value: object) -> int | None:
        if value is None:
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

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

        team_provider_id = self._extract_lineup_team_id(side_payload)
        entries: list[ProviderMatchLineupEntrySeed] = []
        for item in players_payload:
            if not isinstance(item, dict):
                continue

            raw_player = item.get("player")
            if not isinstance(raw_player, dict):
                continue

            role = self._string_or_none(item.get("position")) or self._extract_player_role(raw_player)
            squad_number = self._parse_int(
                item.get("shirtNumber")
                or item.get("jerseyNumber")
                or raw_player.get("shirtNumber")
                or raw_player.get("jerseyNumber")
            )
            player_seed = self._build_player_seed(
                raw_player,
                team_provider_id=team_provider_id,
                raw=item,
                squad_number=squad_number,
                role=role,
                is_current=True,
            )
            if player_seed is None:
                continue

            statistics = item.get("statistics")
            statistics_dict = statistics if isinstance(statistics, dict) else {}
            minutes_played = self._parse_sofascore_minutes(
                item.get("minutesPlayed") or statistics_dict.get("minutesPlayed")
            )
            is_substitute = bool(item.get("substitute"))
            played = self._coerce_sofascore_played(
                item=item,
                statistics=statistics_dict,
                minutes_played=minutes_played,
            )
            entries.append(
                ProviderMatchLineupEntrySeed(
                    player=player_seed,
                    team_side=team_side,
                    is_starter=not is_substitute,
                    is_substitute=is_substitute,
                    played=played,
                    minutes_played=minutes_played,
                    position=role,
                    squad_number=player_seed.squad_number,
                    statistics=statistics_dict,
                    raw=item,
                )
            )

        return entries

    @staticmethod
    def _extract_schedule_events(payload: dict | list) -> list[dict]:
        if isinstance(payload, dict):
            events = payload.get("events")
            if isinstance(events, list):
                return [item for item in events if isinstance(item, dict)]
        return SportsAPIProFootballV2Client._extract_schedule_events(payload)

    @staticmethod
    def _extract_lineup_side(payload: dict, side: str) -> dict | None:
        direct = payload.get(side)
        if isinstance(direct, dict):
            return direct

        alt_key = f"{side}Team"
        alt = payload.get(alt_key)
        if isinstance(alt, dict):
            return alt
        return None

    @staticmethod
    def _extract_lineup_team_id(side_payload: dict) -> str | None:
        team_payload = side_payload.get("team")
        if isinstance(team_payload, dict) and team_payload.get("id") is not None:
            return str(team_payload["id"])

        team_id = side_payload.get("teamId")
        if team_id is not None:
            return str(team_id)
        return None

    @staticmethod
    def _parse_confirmed_flag(payload: dict) -> bool | None:
        for key in ("confirmed", "hasConfirmedLineups", "lineupsConfirmed"):
            value = payload.get(key)
            if isinstance(value, bool):
                return value
        return None

    @staticmethod
    def _parse_sofascore_minutes(value: object) -> int | None:
        if value is None:
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            match = re.search(r"\d+", value)
            if match:
                try:
                    return int(match.group(0))
                except ValueError:
                    return None
        return None

    def _coerce_sofascore_played(
        self,
        *,
        item: dict,
        statistics: dict,
        minutes_played: int | None,
    ) -> bool:
        played = item.get("played")
        if isinstance(played, bool):
            return played

        if minutes_played is not None:
            if minutes_played > 0:
                return True

        stat_minutes = self._parse_sofascore_minutes(statistics.get("minutesPlayed"))
        if stat_minutes is not None:
            if stat_minutes > 0:
                return True

        for key in (
            "goals",
            "goalAssist",
            "yellowCards",
            "redCards",
            "shotsOnTarget",
            "totalPass",
            "accuratePass",
            "saves",
            "rating",
            "ratingVersions",
        ):
            value = statistics.get(key)
            if isinstance(value, (int, float)) and value > 0:
                return True
            if isinstance(value, dict) and value:
                return True

        if self._has_sofascore_statistics(statistics):
            return True

        return False

    @staticmethod
    def _has_sofascore_statistics(statistics: dict) -> bool:
        if not isinstance(statistics, dict):
            return False

        for value in statistics.values():
            if value is None:
                continue
            if isinstance(value, str) and not value.strip():
                continue
            if isinstance(value, (list, tuple, set, dict)) and not value:
                continue
            return True
        return False
