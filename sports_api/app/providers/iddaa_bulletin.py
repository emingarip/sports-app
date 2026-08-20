"""Turkish iddaa bulletin provider (Nesine pre-bulletin feed).

Ingests the daily iddaa program and its prematch odds into the canonical
schema from Nesine's public pre-bulletin JSON
(``GET {base}/api/bulten/getprebultenfull``, default base
``https://cdnbulten.nesine.com``). The base URL and path are configurable via
``SPORTS_API_IDDAA_BULLETIN_*`` so a mirror or licensed replacement feed with
the same shape can be swapped in without code changes.

Feed shape (verified live on 2026-07-11 by aligning the site's market names
with the JSON odds tuples for a full 134-market event)::

    {"sg": {
       "LA": [{"LID": 354, "N": "Çin Super Lig", "CC": "Çin", ...}],
       "EA": [{
          "C": 2991142,          # event code (provider match id)
          "GT": 1,               # game type: 1 = football
          "HN": "...", "AN": "...",       # home / away names
          "ESD": 1783769700000,  # kickoff epoch ms
          "D": "11.07.2026", "T": "14:35",# kickoff fallback (Europe/Istanbul)
          "LC": 354,             # league code -> LA.LID
          "MA": [{
             "MTID": 1,          # market type id (mapping below)
             "SOV": 2.5,         # special odds value (line)
             "MBS": 3,           # min coupon selections for this market
             "OCA": [{"N": 1, "O": 2.36}, ...]   # outcome no + decimal odds
          }, ...]
       }, ...]
    }}

Verified MTID mapping (odds-tuple aligned against the rendered market names):

    1   Maç Sonucu                    3   Çifte Şans
    5   İlk Yarı/Maç Sonucu           7   1. Yarı Sonucu
    11  1,5 Gol Alt/Üst               12  2,5 Gol Alt/Üst
    13  3,5 Gol Alt/Üst               14  1. Yarı 1,5 Gol Alt/Üst
    38  Karşılıklı Gol                43  Toplam Gol Aralığı
    209 1. Yarı 0,5 Gol Alt/Üst       268 Handikaplı Maç Sonucu (SOV=çizgi)

Outcome order conventions (verified): result markets are 1/X/2; totals are
Alt (under) then Üst (over); KG is Var then Yok; İY/MS follows the standard
1/1, 1/X, 1/2, X/1, X/X, X/2, 2/1, 2/X, 2/2 order; goal range buckets are
0-1, 2-3, 4-5, 6+. An odds value of 1 (or below) means the selection is
closed and is skipped.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

import httpx

from app.core.config import Settings
from app.domain.iddaa_markets import (
    MARKET_1X2,
    MARKET_BTTS,
    MARKET_DOUBLE_CHANCE,
    MARKET_FIRST_HALF_RESULT,
    MARKET_FIRST_HALF_TOTALS,
    MARKET_GOAL_RANGE,
    MARKET_HANDICAP,
    MARKET_HT_FT,
    MARKET_TOTALS,
)
from app.providers.base import (
    BootstrapTournamentSeed,
    ProviderBatch,
    ProviderClient,
    ProviderMatchMarketTickSeed,
    ProviderMatchSeed,
    ProviderTeamSeed,
)

logger = logging.getLogger(__name__)

_ISTANBUL = ZoneInfo("Europe/Istanbul")

_RESULT_SELECTIONS = ("home", "draw", "away")
_TOTALS_SELECTIONS = ("under", "over")
_HT_FT_SELECTIONS = (
    "home_home",
    "home_draw",
    "home_away",
    "draw_home",
    "draw_draw",
    "draw_away",
    "away_home",
    "away_draw",
    "away_away",
)

# MTID -> (canonical market_type, selection key per outcome N, line comes from SOV)
_NESINE_MARKETS: dict[int, tuple[str, tuple[str, ...], bool]] = {
    1: (MARKET_1X2, _RESULT_SELECTIONS, False),
    3: (MARKET_DOUBLE_CHANCE, ("home_draw", "home_away", "draw_away"), False),
    5: (MARKET_HT_FT, _HT_FT_SELECTIONS, False),
    7: (MARKET_FIRST_HALF_RESULT, _RESULT_SELECTIONS, False),
    11: (MARKET_TOTALS, _TOTALS_SELECTIONS, True),
    12: (MARKET_TOTALS, _TOTALS_SELECTIONS, True),
    13: (MARKET_TOTALS, _TOTALS_SELECTIONS, True),
    14: (MARKET_FIRST_HALF_TOTALS, _TOTALS_SELECTIONS, True),
    38: (MARKET_BTTS, ("yes", "no"), False),
    43: (MARKET_GOAL_RANGE, ("0_1", "2_3", "4_5", "6_plus"), False),
    209: (MARKET_FIRST_HALF_TOTALS, _TOTALS_SELECTIONS, True),
    268: (MARKET_HANDICAP, _RESULT_SELECTIONS, True),
}

_FOOTBALL_GAME_TYPE = 1


class IddaaBulletinClient(ProviderClient):
    slug = "iddaa-bulletin"
    display_name = "İddaa Bülteni (Nesine)"

    def __init__(self, *, settings: Settings | None = None) -> None:
        super().__init__(settings=settings)
        self._client: httpx.AsyncClient | None = None
        # Prematch markets parsed together with the program payload, keyed by
        # provider match id, so market-backfill does not refetch the feed.
        self._market_cache: dict[str, list[ProviderMatchMarketTickSeed]] = {}

    @property
    def base_url(self) -> str:
        return self.settings.iddaa_bulletin_base_url

    async def fetch(self, *, scope: str, target_date: date | None) -> ProviderBatch:
        if scope not in {"matches", "market-backfill"}:
            return ProviderBatch(scope=scope, target_date=target_date)

        payload = await self._get_program_payload()
        matches, market_cache = self.parse_program_payload(payload, target_date=target_date)
        self._market_cache = market_cache
        return ProviderBatch(scope=scope, target_date=target_date, matches=matches)

    async def get_prematch_markets(self, match_id: str) -> list[ProviderMatchMarketTickSeed]:
        return self._market_cache.get(str(match_id), [])

    async def get_live_markets(self, match_id: str) -> list[ProviderMatchMarketTickSeed]:
        # The pre-bulletin feed is prematch-only; live odds come from other providers.
        return []

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    # ------------------------------------------------------------------
    # HTTP
    # ------------------------------------------------------------------

    def _http_client(self) -> httpx.AsyncClient:
        if self._client is None:
            if not self.base_url:
                raise RuntimeError(
                    "SPORTS_API_IDDAA_BULLETIN_BASE_URL is not configured. "
                    "Set it to the bulletin feed origin before syncing."
                )
            headers = {
                "Accept": "application/json",
                # gzip only: some brotli decoder builds choke on this feed's
                # chunked br stream, and the payload is small enough anyway.
                "Accept-Encoding": "gzip, deflate",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            }
            if self.settings.iddaa_bulletin_api_key:
                headers["Authorization"] = f"Bearer {self.settings.iddaa_bulletin_api_key}"
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                headers=headers,
                timeout=self.settings.iddaa_bulletin_timeout_seconds,
            )
        return self._client

    async def _get_program_payload(self) -> dict:
        client = self._http_client()
        retries = max(1, self.settings.iddaa_bulletin_max_retries)
        last_error: Exception | None = None
        for attempt in range(retries):
            try:
                response = await client.get(self.settings.iddaa_bulletin_program_path)
                response.raise_for_status()
                payload = response.json()
                if isinstance(payload, dict):
                    return payload
                raise ValueError("Bulletin program payload is not a JSON object.")
            except (httpx.HTTPError, ValueError) as exc:
                last_error = exc
                if attempt < retries - 1:
                    await asyncio.sleep(
                        self.settings.iddaa_bulletin_retry_backoff_seconds * (attempt + 1)
                    )
        raise RuntimeError(f"Bulletin program fetch failed: {last_error}") from last_error

    # ------------------------------------------------------------------
    # Parsing (pure functions — fixture-testable without network)
    # ------------------------------------------------------------------

    @classmethod
    def parse_program_payload(
        cls,
        payload: dict,
        *,
        target_date: date | None,
    ) -> tuple[list[ProviderMatchSeed], dict[str, list[ProviderMatchMarketTickSeed]]]:
        sg = payload.get("sg") if isinstance(payload.get("sg"), dict) else payload
        leagues = cls._index_leagues(sg)
        raw_events = sg.get("EA") if isinstance(sg.get("EA"), list) else []

        matches: list[ProviderMatchSeed] = []
        market_cache: dict[str, list[ProviderMatchMarketTickSeed]] = {}
        skipped_non_football = 0
        skipped_unparseable = 0

        for raw_event in raw_events:
            if not isinstance(raw_event, dict):
                continue
            if raw_event.get("GT") != _FOOTBALL_GAME_TYPE:
                skipped_non_football += 1
                continue
            seed = cls._build_match_seed(raw_event, leagues)
            if seed is None:
                skipped_unparseable += 1
                continue
            if target_date is not None:
                local_date = seed.kickoff_at.astimezone(_ISTANBUL).date()
                if local_date != target_date:
                    continue
            matches.append(seed)
            ticks = cls._build_market_ticks(raw_event, seed)
            if ticks:
                market_cache[seed.provider_match_id] = ticks

        logger.info(
            "iddaa bulletin parsed matches=%s (date=%s, non_football=%s, unparseable=%s)",
            len(matches),
            target_date,
            skipped_non_football,
            skipped_unparseable,
        )
        return matches, market_cache

    @staticmethod
    def _index_leagues(sg: dict) -> dict[str, dict]:
        leagues: dict[str, dict] = {}
        raw_leagues = sg.get("LA") if isinstance(sg.get("LA"), list) else []
        for league in raw_leagues:
            if isinstance(league, dict) and league.get("LID") is not None:
                leagues[str(league["LID"])] = league
        return leagues

    @classmethod
    def _build_match_seed(
        cls,
        raw_event: dict,
        leagues: dict[str, dict],
    ) -> ProviderMatchSeed | None:
        code = raw_event.get("C")
        home_name = cls._clean_str(raw_event.get("HN"))
        away_name = cls._clean_str(raw_event.get("AN"))
        kickoff = cls._parse_kickoff(raw_event)
        if code is None or not home_name or not away_name or kickoff is None:
            return None

        competition = None
        league_code = raw_event.get("LC")
        league = leagues.get(str(league_code)) if league_code is not None else None
        league_name = cls._clean_str((league or {}).get("N"))
        if league_name:
            country = cls._clean_str((league or {}).get("CC"))
            competition = BootstrapTournamentSeed(
                provider_tournament_id=str(league_code),
                name=f"{country} {league_name}" if country else league_name,
            )

        mbs_values = [
            market.get("MBS")
            for market in raw_event.get("MA", [])
            if isinstance(market, dict)
            and market.get("MTID") in _NESINE_MARKETS
            and isinstance(market.get("MBS"), int)
        ]

        raw = {key: value for key, value in raw_event.items() if key not in ("MA", "MSA")}
        if mbs_values:
            raw["_mbs"] = min(mbs_values)

        return ProviderMatchSeed(
            provider_match_id=str(code),
            kickoff_at=kickoff,
            status="scheduled",
            provider_status="bulletin",
            home_team=ProviderTeamSeed(provider_team_id=home_name, name=home_name),
            away_team=ProviderTeamSeed(provider_team_id=away_name, name=away_name),
            competition=competition,
            raw=raw,
        )

    @classmethod
    def _build_market_ticks(
        cls,
        raw_event: dict,
        seed: ProviderMatchSeed,
    ) -> list[ProviderMatchMarketTickSeed]:
        raw_markets = raw_event.get("MA")
        if not isinstance(raw_markets, list):
            return []

        tick_time = datetime.now(UTC)
        ticks: list[ProviderMatchMarketTickSeed] = []
        for raw_market in raw_markets:
            if not isinstance(raw_market, dict):
                continue
            mapping = _NESINE_MARKETS.get(raw_market.get("MTID"))
            if mapping is None:
                continue
            market_type, selection_keys, line_from_sov = mapping

            line_value: float | None = None
            if line_from_sov:
                line_value = cls._as_float(raw_market.get("SOV"))

            outcomes = raw_market.get("OCA")
            if not isinstance(outcomes, list):
                continue
            parsed: list[tuple[str, float]] = []
            for outcome in outcomes:
                if not isinstance(outcome, dict):
                    continue
                number = outcome.get("N")
                odds = cls._as_float(outcome.get("O"))
                if not isinstance(number, int) or not (1 <= number <= len(selection_keys)):
                    continue
                # Odds of 1 (or lower) mean the selection is closed.
                if odds is None or odds <= 1.0:
                    continue
                parsed.append((selection_keys[number - 1], odds))

            if not parsed:
                continue
            overround = sum(1.0 / odds for _, odds in parsed)
            for selection_key, odds in parsed:
                implied = 1.0 / odds
                ticks.append(
                    ProviderMatchMarketTickSeed(
                        provider_match_id=seed.provider_match_id,
                        phase="pre",
                        market_type=market_type,
                        selection_key=selection_key,
                        tick_time=tick_time,
                        line_value=line_value,
                        odds_decimal=odds,
                        implied_prob=implied,
                        normalized_prob=implied / overround if overround > 0 else None,
                        bookmaker_key="iddaa",
                        suspended=False,
                        raw={"mtid": raw_market.get("MTID"), "sov": raw_market.get("SOV")},
                    )
                )
        return ticks

    @classmethod
    def _parse_kickoff(cls, raw_event: dict) -> datetime | None:
        # Primary: epoch milliseconds.
        for key in ("ESD", "ED"):
            value = raw_event.get(key)
            if isinstance(value, (int, float)) and value > 0:
                timestamp = float(value)
                if timestamp > 1e12:  # milliseconds
                    timestamp /= 1000.0
                try:
                    return datetime.fromtimestamp(timestamp, tz=UTC)
                except (OverflowError, OSError, ValueError):
                    continue
        # Fallback: "11.07.2026" + "14:35" in Europe/Istanbul.
        date_part = cls._clean_str(raw_event.get("D"))
        time_part = cls._clean_str(raw_event.get("T")) or "00:00"
        if date_part:
            try:
                parsed = datetime.strptime(f"{date_part} {time_part}", "%d.%m.%Y %H:%M")
            except ValueError:
                return None
            return parsed.replace(tzinfo=_ISTANBUL).astimezone(UTC)
        return None

    @staticmethod
    def _clean_str(value: object) -> str | None:
        if isinstance(value, str) and value.strip():
            return value.strip()
        return None

    @staticmethod
    def _as_float(value: object) -> float | None:
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            try:
                return float(value.strip().replace(",", "."))
            except ValueError:
                return None
        return None
