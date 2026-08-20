from app.domain.iddaa_markets import (
    IDDAA_MARKETS,
    MARKET_1X2,
    MARKET_BTTS,
    MARKET_DOUBLE_CHANCE,
    MARKET_FIRST_HALF_RESULT,
    MARKET_FIRST_HALF_TOTALS,
    MARKET_GOAL_RANGE,
    MARKET_HANDICAP,
    MARKET_HT_FT,
    MARKET_TOTALS,
    UNMAPPED_MARKET,
    get_market_by_code,
    get_market_for_tick,
    normalize_provider_market,
    normalize_provider_selection,
    selection_label_tr,
)


def test_market_codes_are_unique() -> None:
    codes = [market.code for market in IDDAA_MARKETS]
    assert len(codes) == len(set(codes))


def test_every_market_has_selections() -> None:
    for market in IDDAA_MARKETS:
        assert market.selections, market.code
        assert market.name_tr, market.code


def test_get_market_by_code_is_case_insensitive() -> None:
    assert get_market_by_code("ms") is get_market_by_code("MS")
    assert get_market_by_code("MS").market_type == MARKET_1X2
    assert get_market_by_code("does-not-exist") is None


def test_get_market_for_tick_resolves_lines() -> None:
    over_25 = get_market_for_tick(MARKET_TOTALS, 2.5)
    assert over_25 is not None
    assert over_25.code == "AU_2_5"

    assert get_market_for_tick(MARKET_TOTALS, 9.5) is None
    assert get_market_for_tick(MARKET_1X2).code == "MS"


def test_selection_labels_are_turkish() -> None:
    assert selection_label_tr(MARKET_1X2, "home") == "1"
    assert selection_label_tr(MARKET_TOTALS, "over", 2.5) == "Üst"
    assert selection_label_tr(MARKET_BTTS, "yes") == "Var"
    assert selection_label_tr(MARKET_HT_FT, "draw_away") == "X/2"
    assert selection_label_tr(MARKET_1X2, "nonsense") is None


def test_normalize_provider_market_known_aliases() -> None:
    assert normalize_provider_market("1X2") == MARKET_1X2
    assert normalize_provider_market("Maç Sonucu") == MARKET_1X2
    assert normalize_provider_market("Çifte Şans") == MARKET_DOUBLE_CHANCE
    assert normalize_provider_market("Over/Under") == MARKET_TOTALS
    assert normalize_provider_market("Karşılıklı Gol") == MARKET_BTTS
    assert normalize_provider_market("İlk Yarı/Maç Sonucu".casefold()) == MARKET_HT_FT
    assert normalize_provider_market("Handikaplı Maç Sonucu") == MARKET_HANDICAP
    assert normalize_provider_market("İlk Yarı Sonucu".casefold()) == MARKET_FIRST_HALF_RESULT
    assert normalize_provider_market("1st Half Over/Under") == MARKET_FIRST_HALF_TOTALS
    assert normalize_provider_market("Toplam Gol Aralığı") == MARKET_GOAL_RANGE


def test_normalize_provider_market_heuristics() -> None:
    assert normalize_provider_market("Total Goals") == MARKET_TOTALS
    assert normalize_provider_market("Asian Handicap") == MARKET_HANDICAP
    assert normalize_provider_market("Both Teams To Score in 2nd Half") == MARKET_BTTS


def test_normalize_provider_market_unknown_is_unmapped() -> None:
    assert normalize_provider_market("Corners 3-Way") == UNMAPPED_MARKET
    assert normalize_provider_market(None) == UNMAPPED_MARKET
    assert normalize_provider_market("   ") == UNMAPPED_MARKET


def test_normalize_provider_selection_round_trip() -> None:
    # Every canonical selection key must map back to itself for its market.
    for market in IDDAA_MARKETS:
        for selection_key in market.selections:
            label = market.selections[selection_key]
            assert (
                normalize_provider_selection(market.market_type, label) == selection_key
                or normalize_provider_selection(market.market_type, selection_key)
                == selection_key
            ), (market.code, selection_key)


def test_normalize_provider_selection_examples() -> None:
    assert normalize_provider_selection(MARKET_1X2, "1") == "home"
    assert normalize_provider_selection(MARKET_1X2, "X") == "draw"
    assert normalize_provider_selection(MARKET_DOUBLE_CHANCE, "1-X") == "home_draw"
    assert normalize_provider_selection(MARKET_TOTALS, "Alt") == "under"
    assert normalize_provider_selection(MARKET_BTTS, "Var") == "yes"
    assert normalize_provider_selection(MARKET_HT_FT, "X/2") == "draw_away"
    assert normalize_provider_selection(MARKET_GOAL_RANGE, "6+") == "6_plus"
    assert normalize_provider_selection(MARKET_1X2, None) == "unknown"
