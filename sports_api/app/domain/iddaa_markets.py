"""Iddaa market taxonomy.

Maps the Turkish iddaa bulletin markets onto the canonical odds schema used by
``MatchMarketTick`` (``market_type`` + ``selection_key`` + ``line_value``).

The taxonomy is provider-agnostic: bulletin sources (Nesine, Misli, licensed
feeds) and generic odds providers (SportsAPIPro) are normalized into the same
canonical market types so that analysis, prediction and UI layers never depend
on a specific upstream naming scheme.

Canonical market types already emitted by existing providers are reused:
``1x2``, ``totals``, ``next_goal``. This module adds the remaining iddaa core
markets and the Turkish display metadata for all of them.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field


def _fold_text(value: str) -> str:
    """Casefold + strip diacritics so Turkish and ASCII spellings compare equal."""
    text = " ".join(value.strip().casefold().split())
    decomposed = unicodedata.normalize("NFKD", text.replace("ı", "i"))
    return "".join(char for char in decomposed if not unicodedata.combining(char))

# Canonical market_type values. Existing providers already emit the first three.
MARKET_1X2 = "1x2"
MARKET_TOTALS = "totals"
MARKET_NEXT_GOAL = "next_goal"
MARKET_DOUBLE_CHANCE = "double_chance"
MARKET_BTTS = "btts"
MARKET_HT_FT = "ht_ft"
MARKET_HANDICAP = "handicap"
MARKET_FIRST_HALF_RESULT = "first_half_result"
MARKET_FIRST_HALF_TOTALS = "first_half_totals"
MARKET_GOAL_RANGE = "goal_range"

UNMAPPED_MARKET = "unmapped"

_RESULT_SELECTIONS = {"home": "1", "draw": "X", "away": "2"}
_DOUBLE_CHANCE_SELECTIONS = {"home_draw": "1-X", "home_away": "1-2", "draw_away": "X-2"}
_TOTALS_SELECTIONS = {"over": "Üst", "under": "Alt"}
_BTTS_SELECTIONS = {"yes": "Var", "no": "Yok"}
_HT_FT_SELECTIONS = {
    "home_home": "1/1",
    "home_draw": "1/X",
    "home_away": "1/2",
    "draw_home": "X/1",
    "draw_draw": "X/X",
    "draw_away": "X/2",
    "away_home": "2/1",
    "away_draw": "2/X",
    "away_away": "2/2",
}
_GOAL_RANGE_SELECTIONS = {
    "0_1": "0-1",
    "2_3": "2-3",
    "4_5": "4-5",
    "6_plus": "6+",
}


@dataclass(frozen=True, slots=True)
class IddaaMarketDef:
    """One iddaa bulletin market and its canonical representation."""

    code: str
    """Stable internal code (used by API responses and the Flutter client)."""

    name_tr: str
    market_type: str
    selections: dict[str, str] = field(default_factory=dict)
    """Canonical ``selection_key`` -> Turkish selection label."""

    line_value: float | None = None
    """Fixed line for line-based markets (e.g. 2.5 for Alt/Üst 2,5)."""

    def selection_label(self, selection_key: str) -> str | None:
        return self.selections.get(selection_key)


IDDAA_MARKETS: tuple[IddaaMarketDef, ...] = (
    IddaaMarketDef(
        code="MS",
        name_tr="Maç Sonucu",
        market_type=MARKET_1X2,
        selections=dict(_RESULT_SELECTIONS),
    ),
    IddaaMarketDef(
        code="CS",
        name_tr="Çifte Şans",
        market_type=MARKET_DOUBLE_CHANCE,
        selections=dict(_DOUBLE_CHANCE_SELECTIONS),
    ),
    IddaaMarketDef(
        code="AU_1_5",
        name_tr="Alt/Üst 1,5 Gol",
        market_type=MARKET_TOTALS,
        selections=dict(_TOTALS_SELECTIONS),
        line_value=1.5,
    ),
    IddaaMarketDef(
        code="AU_2_5",
        name_tr="Alt/Üst 2,5 Gol",
        market_type=MARKET_TOTALS,
        selections=dict(_TOTALS_SELECTIONS),
        line_value=2.5,
    ),
    IddaaMarketDef(
        code="AU_3_5",
        name_tr="Alt/Üst 3,5 Gol",
        market_type=MARKET_TOTALS,
        selections=dict(_TOTALS_SELECTIONS),
        line_value=3.5,
    ),
    IddaaMarketDef(
        code="KG",
        name_tr="Karşılıklı Gol",
        market_type=MARKET_BTTS,
        selections=dict(_BTTS_SELECTIONS),
    ),
    IddaaMarketDef(
        code="IY_MS",
        name_tr="İlk Yarı / Maç Sonucu",
        market_type=MARKET_HT_FT,
        selections=dict(_HT_FT_SELECTIONS),
    ),
    IddaaMarketDef(
        code="H_MS_1",
        name_tr="Handikaplı Maç Sonucu (1,0)",
        market_type=MARKET_HANDICAP,
        selections=dict(_RESULT_SELECTIONS),
        line_value=1.0,
    ),
    IddaaMarketDef(
        code="H_MS_MINUS_1",
        name_tr="Handikaplı Maç Sonucu (-1,0)",
        market_type=MARKET_HANDICAP,
        selections=dict(_RESULT_SELECTIONS),
        line_value=-1.0,
    ),
    IddaaMarketDef(
        code="IY",
        name_tr="İlk Yarı Sonucu",
        market_type=MARKET_FIRST_HALF_RESULT,
        selections=dict(_RESULT_SELECTIONS),
    ),
    IddaaMarketDef(
        code="IY_AU_0_5",
        name_tr="İlk Yarı Alt/Üst 0,5 Gol",
        market_type=MARKET_FIRST_HALF_TOTALS,
        selections=dict(_TOTALS_SELECTIONS),
        line_value=0.5,
    ),
    IddaaMarketDef(
        code="IY_AU_1_5",
        name_tr="İlk Yarı Alt/Üst 1,5 Gol",
        market_type=MARKET_FIRST_HALF_TOTALS,
        selections=dict(_TOTALS_SELECTIONS),
        line_value=1.5,
    ),
    IddaaMarketDef(
        code="TG",
        name_tr="Toplam Gol Aralığı",
        market_type=MARKET_GOAL_RANGE,
        selections=dict(_GOAL_RANGE_SELECTIONS),
    ),
)

_MARKETS_BY_CODE: dict[str, IddaaMarketDef] = {market.code: market for market in IDDAA_MARKETS}


def get_market_by_code(code: str) -> IddaaMarketDef | None:
    return _MARKETS_BY_CODE.get(code.strip().upper())


def get_market_for_tick(
    market_type: str,
    line_value: float | None = None,
) -> IddaaMarketDef | None:
    """Resolve the iddaa market definition matching a canonical odds tick."""
    for market in IDDAA_MARKETS:
        if market.market_type != market_type:
            continue
        if market.line_value is None and line_value is None:
            return market
        if (
            market.line_value is not None
            and line_value is not None
            and abs(market.line_value - line_value) < 1e-9
        ):
            return market
    return None


def selection_label_tr(
    market_type: str,
    selection_key: str,
    line_value: float | None = None,
) -> str | None:
    market = get_market_for_tick(market_type, line_value)
    if market is None:
        return None
    return market.selection_label(selection_key)


# ---------------------------------------------------------------------------
# Provider normalization
# ---------------------------------------------------------------------------

_PROVIDER_MARKET_ALIASES: dict[str, str] = {
    # 1X2 / match result
    "1x2": MARKET_1X2,
    "ms": MARKET_1X2,
    "mac sonucu": MARKET_1X2,
    "maç sonucu": MARKET_1X2,
    "full time result": MARKET_1X2,
    "full-time result": MARKET_1X2,
    "match result": MARKET_1X2,
    "match winner": MARKET_1X2,
    # Double chance
    "double chance": MARKET_DOUBLE_CHANCE,
    "cifte sans": MARKET_DOUBLE_CHANCE,
    "çifte şans": MARKET_DOUBLE_CHANCE,
    "cs": MARKET_DOUBLE_CHANCE,
    # Totals
    "totals": MARKET_TOTALS,
    "o/u": MARKET_TOTALS,
    "ou": MARKET_TOTALS,
    "over/under": MARKET_TOTALS,
    "alt/ust": MARKET_TOTALS,
    "alt/üst": MARKET_TOTALS,
    "toplam gol alt/ust": MARKET_TOTALS,
    "toplam gol alt/üst": MARKET_TOTALS,
    # BTTS
    "btts": MARKET_BTTS,
    "both teams to score": MARKET_BTTS,
    "karsilikli gol": MARKET_BTTS,
    "karşılıklı gol": MARKET_BTTS,
    "kg": MARKET_BTTS,
    "kg var/yok": MARKET_BTTS,
    # HT/FT
    "ht/ft": MARKET_HT_FT,
    "half time/full time": MARKET_HT_FT,
    "halftime/fulltime": MARKET_HT_FT,
    "ilk yari/mac sonucu": MARKET_HT_FT,
    "ilk yarı/maç sonucu": MARKET_HT_FT,
    "iy/ms": MARKET_HT_FT,
    # Handicap
    "handicap": MARKET_HANDICAP,
    "handicap result": MARKET_HANDICAP,
    "european handicap": MARKET_HANDICAP,
    "handikapli mac sonucu": MARKET_HANDICAP,
    "handikaplı maç sonucu": MARKET_HANDICAP,
    "h1": MARKET_HANDICAP,
    "h2": MARKET_HANDICAP,
    # First half result
    "first half result": MARKET_FIRST_HALF_RESULT,
    "half time result": MARKET_FIRST_HALF_RESULT,
    "1st half result": MARKET_FIRST_HALF_RESULT,
    "ilk yari sonucu": MARKET_FIRST_HALF_RESULT,
    "ilk yarı sonucu": MARKET_FIRST_HALF_RESULT,
    "iy": MARKET_FIRST_HALF_RESULT,
    # First half totals
    "first half totals": MARKET_FIRST_HALF_TOTALS,
    "1st half over/under": MARKET_FIRST_HALF_TOTALS,
    "ilk yari alt/ust": MARKET_FIRST_HALF_TOTALS,
    "ilk yarı alt/üst": MARKET_FIRST_HALF_TOTALS,
    "iy au": MARKET_FIRST_HALF_TOTALS,
    # Goal range
    "goal range": MARKET_GOAL_RANGE,
    "total goals range": MARKET_GOAL_RANGE,
    "toplam gol araligi": MARKET_GOAL_RANGE,
    "toplam gol aralığı": MARKET_GOAL_RANGE,
    "tg": MARKET_GOAL_RANGE,
    # Next goal (live)
    "next goal": MARKET_NEXT_GOAL,
    "siradaki gol": MARKET_NEXT_GOAL,
    "sıradaki gol": MARKET_NEXT_GOAL,
}


_FOLDED_MARKET_ALIASES: dict[str, str] = {
    _fold_text(alias): market_type for alias, market_type in _PROVIDER_MARKET_ALIASES.items()
}


def normalize_provider_market(value: str | None) -> str:
    """Normalize a provider market name into a canonical ``market_type``.

    Unknown markets return :data:`UNMAPPED_MARKET` so callers can persist the
    tick without breaking while flagging it for taxonomy follow-up.
    """
    if value is None:
        return UNMAPPED_MARKET
    text = _fold_text(value)
    if not text:
        return UNMAPPED_MARKET
    alias = _FOLDED_MARKET_ALIASES.get(text)
    if alias is not None:
        return alias
    if "first half" in text or "1st half" in text or "ilk yari" in text:
        if "over" in text or "under" in text or "alt" in text or "ust" in text:
            return MARKET_FIRST_HALF_TOTALS
        return MARKET_FIRST_HALF_RESULT
    if "next goal" in text or "first to score" in text or "next to score" in text:
        return MARKET_NEXT_GOAL
    if "handic" in text or "handikap" in text:
        return MARKET_HANDICAP
    if "both teams" in text or "karsilikli" in text:
        return MARKET_BTTS
    if "double chance" in text or "cifte" in text:
        return MARKET_DOUBLE_CHANCE
    if "over" in text or "under" in text or "total" in text:
        return MARKET_TOTALS
    return UNMAPPED_MARKET


_RESULT_SELECTION_ALIASES = {
    "1": "home",
    "x": "draw",
    "2": "away",
    "home": "home",
    "draw": "draw",
    "away": "away",
}

_SELECTION_ALIASES: dict[str, dict[str, str]] = {
    MARKET_1X2: {**_RESULT_SELECTION_ALIASES, "ms1": "home", "ms0": "draw", "ms2": "away"},
    MARKET_FIRST_HALF_RESULT: dict(_RESULT_SELECTION_ALIASES),
    MARKET_HANDICAP: dict(_RESULT_SELECTION_ALIASES),
    MARKET_DOUBLE_CHANCE: {
        "1-x": "home_draw",
        "1x": "home_draw",
        "1 veya x": "home_draw",
        "home or draw": "home_draw",
        "1-2": "home_away",
        "12": "home_away",
        "1 veya 2": "home_away",
        "home or away": "home_away",
        "x-2": "draw_away",
        "x2": "draw_away",
        "x veya 2": "draw_away",
        "draw or away": "draw_away",
    },
    MARKET_TOTALS: {"over": "over", "under": "under", "üst": "over", "alt": "under"},
    MARKET_FIRST_HALF_TOTALS: {"over": "over", "under": "under", "üst": "over", "alt": "under"},
    MARKET_BTTS: {
        "yes": "yes",
        "no": "no",
        "var": "yes",
        "yok": "no",
        "evet": "yes",
        "hayır": "no",
    },
    MARKET_HT_FT: {
        "1/1": "home_home",
        "1/x": "home_draw",
        "1/2": "home_away",
        "x/1": "draw_home",
        "x/x": "draw_draw",
        "x/2": "draw_away",
        "2/1": "away_home",
        "2/x": "away_draw",
        "2/2": "away_away",
    },
    MARKET_GOAL_RANGE: {
        "0-1": "0_1",
        "0_1": "0_1",
        "2-3": "2_3",
        "2_3": "2_3",
        "4-5": "4_5",
        "4_5": "4_5",
        "6+": "6_plus",
        "6 ve ustu": "6_plus",
        "6 ve üstü": "6_plus",
        "6_plus": "6_plus",
    },
    MARKET_NEXT_GOAL: {
        "1": "home",
        "2": "away",
        "home": "home",
        "away": "away",
        "no goal": "no_goal",
        "yok": "no_goal",
    },
}


_FOLDED_SELECTION_ALIASES: dict[str, dict[str, str]] = {
    market_type: {_fold_text(alias): key for alias, key in aliases.items()}
    for market_type, aliases in _SELECTION_ALIASES.items()
}


def normalize_provider_selection(market_type: str, value: str | None) -> str:
    """Normalize a provider selection name into a canonical ``selection_key``."""
    text = _fold_text(str(value or ""))
    aliases = _FOLDED_SELECTION_ALIASES.get(market_type, {})
    if text in aliases:
        return aliases[text]
    # Common fallbacks shared across markets.
    if "under" in text or text == "alt":
        return "under"
    if "over" in text or text == "ust":
        return "over"
    if "draw" in text:
        return "draw"
    if "home" in text:
        return "home"
    if "away" in text:
        return "away"
    return text or "unknown"
