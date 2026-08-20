import json
from datetime import UTC, date, datetime
from pathlib import Path

import pytest

from app.core.config import Settings
from app.providers.iddaa_bulletin import IddaaBulletinClient
from app.providers.registry import REGISTERED_PROVIDER_CLIENTS

FIXTURES_DIR = Path(__file__).parent / "fixtures"

# The fixture is a trimmed capture of the real Nesine pre-bulletin feed
# (2026-07-11): event 2990958 Norveç - İngiltere (Dünya Kupası) with the full
# mapped market set, event 2991142 Sh. Peng City - Qingdao Yth. Is. (Çin Süper
# Lig) without ESD to exercise the D/T fallback, and one non-football special
# event that must be skipped.


def load_fixture() -> dict:
    return json.loads((FIXTURES_DIR / "nesine_prebulten.json").read_text(encoding="utf-8"))


def test_registry_contains_iddaa_bulletin_client() -> None:
    assert REGISTERED_PROVIDER_CLIENTS[IddaaBulletinClient.slug] is IddaaBulletinClient


def test_parse_program_payload_builds_match_seeds() -> None:
    matches, market_cache = IddaaBulletinClient.parse_program_payload(
        load_fixture(), target_date=None
    )

    assert len(matches) == 2  # special (GT != 1) event skipped
    by_id = {match.provider_match_id: match for match in matches}
    assert set(by_id) == {"2990958", "2991142"}

    norway = by_id["2990958"]
    assert norway.home_team.name == "Norveç"
    assert norway.away_team.name == "İngiltere"
    # ESD epoch ms is authoritative.
    assert norway.kickoff_at == datetime.fromtimestamp(1783803600, tz=UTC)
    assert norway.competition is not None
    assert norway.competition.provider_tournament_id == "10151"
    assert "Dünya Kupası" in norway.competition.name
    assert norway.status == "scheduled"
    assert norway.raw["_mbs"] == 1
    assert "MA" not in norway.raw  # odds are not duplicated into the match raw

    china = by_id["2991142"]
    # No ESD in fixture: 11.07.2026 14:35 Europe/Istanbul == 11:35 UTC.
    assert china.kickoff_at == datetime(2026, 7, 11, 11, 35, tzinfo=UTC)
    assert china.competition.name == "CN Çin Süper Lig"
    assert china.raw["_mbs"] == 2

    assert set(market_cache) == {"2990958", "2991142"}


def test_parse_program_payload_maps_verified_mtids() -> None:
    _, market_cache = IddaaBulletinClient.parse_program_payload(
        load_fixture(), target_date=None
    )
    ticks = market_cache["2990958"]
    by_market: dict[tuple[str, float | None], dict[str, float]] = {}
    for tick in ticks:
        key = (tick.market_type, tick.line_value)
        by_market.setdefault(key, {})[tick.selection_key] = tick.odds_decimal

    # MS 1X2 (MTID 1): 3.59 / 3.25 / 1.65
    ms = by_market[("1x2", None)]
    assert ms == {"home": 3.59, "draw": 3.25, "away": 1.65}

    # AU 2,5 (MTID 12): Alt 1.88 / Üst 1.51 -> under first.
    au_25 = by_market[("totals", 2.5)]
    assert au_25 == {"under": 1.88, "over": 1.51}
    # AU 1,5 (MTID 11) and 3,5 (MTID 13) share the family with their lines.
    assert ("totals", 1.5) in by_market and ("totals", 3.5) in by_market

    # KG (MTID 38): Var 1.46 / Yok 1.97.
    assert by_market[("btts", None)] == {"yes": 1.46, "no": 1.97}

    # Handikap (MTID 268): SOV=1.0 -> line +1 (home +1 favours home).
    handicap_plus = by_market[("handicap", 1.0)]
    assert handicap_plus["home"] == 1.65
    handicap_minus = by_market[("handicap", -1.0)]
    assert handicap_minus["away"] == 1.07

    # İY/MS (MTID 5): all 9 selections present; away favourite -> away_away lowest.
    ht_ft = by_market[("ht_ft", None)]
    assert len(ht_ft) == 9
    assert min(ht_ft, key=ht_ft.get) == "away_away"

    # Toplam Gol Aralığı (MTID 43): buckets in verified order.
    goal_range = by_market[("goal_range", None)]
    assert goal_range == {"0_1": 3.81, "2_3": 1.81, "4_5": 3.07, "6_plus": 10.1}

    # İY AU (MTID 209 / 14).
    assert ("first_half_totals", 0.5) in by_market
    assert ("first_half_totals", 1.5) in by_market
    # İY Sonucu (MTID 7).
    assert ("first_half_result", None) in by_market

    # Unmapped MTIDs (e.g. 49 Tek/Çift) are skipped.
    mapped_types = {tick.market_type for tick in ticks}
    assert "unmapped" not in mapped_types


def test_parse_program_payload_normalizes_probabilities() -> None:
    _, market_cache = IddaaBulletinClient.parse_program_payload(
        load_fixture(), target_date=None
    )
    ms_ticks = [tick for tick in market_cache["2990958"] if tick.market_type == "1x2"]
    assert all(tick.phase == "pre" for tick in ms_ticks)
    assert all(tick.bookmaker_key == "iddaa" for tick in ms_ticks)
    for tick in ms_ticks:
        assert tick.implied_prob == pytest.approx(1.0 / tick.odds_decimal)
    assert sum(tick.normalized_prob for tick in ms_ticks) == pytest.approx(1.0)


def test_parse_program_payload_filters_by_bulletin_date() -> None:
    # Norway kicks off 2026-07-12 00:00 Istanbul; China match 2026-07-11 14:35.
    matches_11, _ = IddaaBulletinClient.parse_program_payload(
        load_fixture(), target_date=date(2026, 7, 11)
    )
    assert [match.provider_match_id for match in matches_11] == ["2991142"]

    matches_12, _ = IddaaBulletinClient.parse_program_payload(
        load_fixture(), target_date=date(2026, 7, 12)
    )
    assert [match.provider_match_id for match in matches_12] == ["2990958"]


def test_closed_selections_are_skipped() -> None:
    payload = load_fixture()
    event = payload["sg"]["EA"][0]
    ms = next(market for market in event["MA"] if market["MTID"] == 1)
    ms["OCA"][0]["O"] = 1  # closed selection (renders as "-")

    _, market_cache = IddaaBulletinClient.parse_program_payload(payload, target_date=None)
    ms_ticks = [tick for tick in market_cache["2990958"] if tick.market_type == "1x2"]
    assert {tick.selection_key for tick in ms_ticks} == {"draw", "away"}
    assert sum(tick.normalized_prob for tick in ms_ticks) == pytest.approx(1.0)


async def test_fetch_populates_market_cache(monkeypatch) -> None:
    client = IddaaBulletinClient(settings=Settings())
    payload = load_fixture()

    async def fake_get_program_payload():
        return payload

    monkeypatch.setattr(client, "_get_program_payload", fake_get_program_payload)

    batch = await client.fetch(scope="matches", target_date=None)
    assert len(batch.matches) == 2

    ticks = await client.get_prematch_markets("2990958")
    assert ticks
    assert all(tick.provider_match_id == "2990958" for tick in ticks)

    assert await client.get_prematch_markets("does-not-exist") == []
    assert await client.get_live_markets("2990958") == []


async def test_fetch_without_base_url_raises_helpful_error() -> None:
    client = IddaaBulletinClient(settings=Settings(iddaa_bulletin_base_url=""))
    with pytest.raises(RuntimeError, match="IDDAA_BULLETIN_BASE_URL"):
        await client.fetch(scope="matches", target_date=date(2026, 7, 12))


def test_default_settings_point_at_live_feed() -> None:
    settings = Settings()
    assert settings.iddaa_bulletin_base_url == "https://cdnbulten.nesine.com"
    assert settings.iddaa_bulletin_program_path == "/api/bulten/getprebultenfull"
