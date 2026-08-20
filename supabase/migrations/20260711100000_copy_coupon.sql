-- Coupon copying (Faz 4.2 of the betting-analysis pivot).
--
-- copy_coupon lets a user clone another tipster's public, still-pending
-- coupon into their own record. Selections are NOT copied verbatim: every
-- selection is rebuilt server-side with the CURRENT bulletin odds (the copier
-- locks today's price, not the original tipster's price), so copies earn
-- their own CLV. Copying is rejected once any match of the source coupon has
-- kicked off.

CREATE OR REPLACE FUNCTION public.copy_coupon(
  p_coupon_id UUID,
  p_stake_kcoin INT DEFAULT NULL,
  p_is_public BOOLEAN DEFAULT TRUE
)
RETURNS public.analysis_coupons
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_source public.analysis_coupons;
  v_item JSONB;
  v_match_id UUID;
  v_market_code TEXT;
  v_selection_key TEXT;
  v_model_prob NUMERIC;
  v_row RECORD;
  v_locked JSONB := '[]'::jsonb;
  v_total_odds NUMERIC := 1;
  v_combined_prob NUMERIC := 1;
  v_prob_complete BOOLEAN := TRUE;
  v_first_kickoff TIMESTAMPTZ;
  v_coupon public.analysis_coupons;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_coupon_id IS NULL THEN
    RAISE EXCEPTION 'Coupon ID is required';
  END IF;

  IF p_stake_kcoin IS NOT NULL AND p_stake_kcoin <= 0 THEN
    RAISE EXCEPTION 'Stake must be positive';
  END IF;

  -- SECURITY DEFINER bypasses RLS, so visibility is re-checked by hand below.
  SELECT * INTO v_source
  FROM public.analysis_coupons
  WHERE id = p_coupon_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Coupon % does not exist', p_coupon_id;
  END IF;

  IF NOT v_source.is_public THEN
    RAISE EXCEPTION 'Only public coupons can be copied';
  END IF;

  IF v_source.user_id = v_user_id THEN
    RAISE EXCEPTION 'You cannot copy your own coupon';
  END IF;

  IF v_source.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending coupons can be copied';
  END IF;

  -- Anti-gaming: no post-hoc copies. The whole coupon must still be
  -- pre-kickoff (each selection is re-checked in the loop as well).
  IF v_source.first_kickoff_at <= NOW() THEN
    RAISE EXCEPTION 'The first match of this coupon has already kicked off';
  END IF;

  -- Rebuild every selection with the current bulletin odds. Nothing is
  -- dropped: a missing odds row or a started match aborts the whole copy.
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_source.selections) LOOP
    v_match_id := (v_item ->> 'bulletin_match_id')::uuid;
    v_market_code := NULLIF(btrim(COALESCE(v_item ->> 'market_code', '')), '');
    v_selection_key := NULLIF(btrim(COALESCE(v_item ->> 'selection_key', '')), '');

    IF v_match_id IS NULL OR v_market_code IS NULL OR v_selection_key IS NULL THEN
      RAISE EXCEPTION 'Source coupon contains a malformed selection';
    END IF;

    SELECT
      bo.odds,
      bo.line_value,
      bo.market_name_tr,
      bo.selection_label_tr,
      bo.suspended,
      bm.kickoff_at,
      bm.sports_api_match_id,
      bm.home_team,
      bm.away_team
    INTO v_row
    FROM public.bulletin_odds bo
    JOIN public.bulletin_matches bm ON bm.id = bo.bulletin_match_id
    WHERE bo.bulletin_match_id = v_match_id
      AND bo.market_code = v_market_code
      AND bo.selection_key = v_selection_key;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selection %/% is no longer available in the bulletin for match %',
        v_market_code, v_selection_key, v_match_id;
    END IF;

    IF v_row.suspended THEN
      RAISE EXCEPTION 'Selection %/% is currently suspended', v_market_code, v_selection_key;
    END IF;

    IF v_row.odds IS NULL OR v_row.odds <= 1.0 THEN
      RAISE EXCEPTION 'No valid current odds for selection %/%', v_market_code, v_selection_key;
    END IF;

    -- Anti-gaming: no post-hoc coupons. Every selection must be pre-kickoff.
    IF v_row.kickoff_at <= NOW() THEN
      RAISE EXCEPTION 'Match % - % has already kicked off', v_row.home_team, v_row.away_team;
    END IF;

    v_first_kickoff := LEAST(COALESCE(v_first_kickoff, v_row.kickoff_at), v_row.kickoff_at);
    v_total_odds := v_total_odds * v_row.odds;

    -- Combined model probability from the Dixon-Coles bridge, when available
    -- for every selection.
    SELECT (bp.market_probs -> v_market_code ->> v_selection_key)::numeric
    INTO v_model_prob
    FROM public.bulletin_predictions bp
    WHERE bp.bulletin_match_id = v_match_id;

    IF v_model_prob IS NULL THEN
      v_prob_complete := FALSE;
    ELSE
      v_combined_prob := v_combined_prob * v_model_prob;
    END IF;

    v_locked := v_locked || jsonb_build_array(jsonb_build_object(
      'bulletin_match_id', v_match_id,
      'sports_api_match_id', v_row.sports_api_match_id,
      'match_label', v_row.home_team || ' - ' || v_row.away_team,
      'kickoff_at', v_row.kickoff_at,
      'market_code', v_market_code,
      'market_name', v_row.market_name_tr,
      'selection_key', v_selection_key,
      'selection_label', v_row.selection_label_tr,
      'odds_at_share', v_row.odds,
      'line_value', v_row.line_value,
      'result', 'pending',
      'closing_odds', NULL,
      'clv', NULL
    ));
  END LOOP;

  IF NOT v_prob_complete THEN
    v_combined_prob := NULL;
  END IF;

  -- K-Coin stake: the ledger currently only exposes credit-side server
  -- functions (credit_k_coins_server / grant_k_coins_server); there is no
  -- server-side debit function, and place_bet / buy_store_item_server are
  -- bound to other domains. Per the K-Coin economy rules we do not improvise
  -- a ledger write here: the stake is recorded on the coupon without any coin
  -- movement.
  -- TODO(k-coin): once a spend_k_coins_server-style debit exists, debit
  -- p_stake_kcoin with transaction_type 'prediction_stake' and
  -- idempotency_key 'coupon_stake:<coupon id>'. resolve_coupon_selections
  -- only credits payouts/refunds when that exact debit row exists, so no
  -- coins can be minted in the meantime.

  INSERT INTO public.analysis_coupons (
    user_id,
    origin_coupon_id,
    title,
    selections,
    total_odds,
    combined_model_prob,
    expected_value,
    stake_kcoin,
    is_public,
    first_kickoff_at
  )
  VALUES (
    v_user_id,
    p_coupon_id,
    v_source.title,
    v_locked,
    v_total_odds,
    v_combined_prob,
    CASE WHEN v_combined_prob IS NOT NULL THEN v_combined_prob * v_total_odds - 1 END,
    p_stake_kcoin,
    COALESCE(p_is_public, TRUE),
    v_first_kickoff
  )
  RETURNING * INTO v_coupon;

  INSERT INTO public.tipster_stats AS ts (user_id, period, coupons_total, updated_at)
  VALUES
    (v_user_id, 'all', 1, NOW()),
    (v_user_id, to_char(NOW(), 'YYYY-MM'), 1, NOW())
  ON CONFLICT (user_id, period)
  DO UPDATE SET
    coupons_total = ts.coupons_total + 1,
    updated_at = NOW();

  RETURN v_coupon;
END;
$$;

REVOKE ALL ON FUNCTION public.copy_coupon(UUID, INT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.copy_coupon(UUID, INT, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.copy_coupon(UUID, INT, BOOLEAN) TO authenticated;

NOTIFY pgrst, 'reload schema';
