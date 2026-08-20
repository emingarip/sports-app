-- Verifiable tipster infrastructure (Faz 4.1 of the betting-analysis pivot).
-- Analysis coupons with server-locked odds, settlement + CLV computation and
-- skill-based tipster statistics.
--
-- Coupons are created exclusively through the share_coupon RPC (odds are
-- re-validated and locked server-side, post-kickoff sharing is rejected) and
-- settled by the resolve-coupons edge function through the service-role-only
-- resolve_coupon_selections RPC. After insert, owners may only edit title and
-- is_public; everything else is frozen by trigger.

-- =========================================
-- 1. Tables
-- =========================================

CREATE TABLE public.analysis_coupons (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- Set when the coupon was copied from another tipster's coupon.
  origin_coupon_id UUID REFERENCES public.analysis_coupons(id) ON DELETE SET NULL,
  title TEXT,
  -- Array of selection objects:
  -- {bulletin_match_id, sports_api_match_id, match_label, kickoff_at,
  --  market_code, market_name, selection_key, selection_label, odds_at_share,
  --  line_value, result ('pending'|'won'|'lost'|'void'),
  --  closing_odds (null until resolved), clv (null until resolved)}
  selections JSONB NOT NULL CHECK (
    jsonb_typeof(selections) = 'array'
    AND jsonb_array_length(selections) >= 1
    AND jsonb_array_length(selections) <= 20
  ),
  total_odds NUMERIC NOT NULL,
  combined_model_prob NUMERIC,
  expected_value NUMERIC,
  stake_kcoin INT CHECK (stake_kcoin IS NULL OR stake_kcoin > 0),
  status TEXT CHECK (status IN ('pending', 'won', 'lost', 'void')) DEFAULT 'pending',
  is_public BOOLEAN DEFAULT TRUE,
  -- Odds are locked at share time; sharing after first_kickoff_at is rejected.
  locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  first_kickoff_at TIMESTAMPTZ NOT NULL,
  resolved_at TIMESTAMPTZ,
  avg_clv NUMERIC,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_analysis_coupons_user_created
  ON public.analysis_coupons (user_id, created_at DESC);
CREATE INDEX idx_analysis_coupons_pending
  ON public.analysis_coupons (status) WHERE status = 'pending';
CREATE INDEX idx_analysis_coupons_public_created
  ON public.analysis_coupons (is_public, created_at DESC);

CREATE TABLE public.coupon_likes (
  coupon_id UUID NOT NULL REFERENCES public.analysis_coupons(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (coupon_id, user_id)
);

CREATE TABLE public.coupon_comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  coupon_id UUID NOT NULL REFERENCES public.analysis_coupons(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (char_length(content) <= 500),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_coupon_comments_coupon
  ON public.coupon_comments (coupon_id, created_at);

-- Aggregated, recomputable tipster performance per period ('all' lifetime or
-- a 'YYYY-MM' month). ROI is flat-stake: coupons without a K-Coin stake count
-- as 1 unit staked.
CREATE TABLE public.tipster_stats (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  period TEXT NOT NULL CHECK (period = 'all' OR period ~ '^\d{4}-\d{2}$'),
  coupons_total INT NOT NULL DEFAULT 0,
  coupons_settled INT NOT NULL DEFAULT 0,
  coupons_won INT NOT NULL DEFAULT 0,
  total_staked NUMERIC NOT NULL DEFAULT 0,
  total_returned NUMERIC NOT NULL DEFAULT 0,
  roi NUMERIC,
  avg_clv NUMERIC,
  clv_sample INT NOT NULL DEFAULT 0,
  -- market_code -> {picks, won} over settled coupons.
  market_breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, period)
);

-- =========================================
-- 2. Anti-gaming guard (immutable after insert)
-- =========================================

-- Only the service role may mutate a coupon after insert (settlement flow);
-- owners are limited to title / is_public. Direct connections carry no
-- request.jwt.claims, PostgREST service-role requests carry
-- {"role": "service_role"}.
CREATE OR REPLACE FUNCTION public.guard_analysis_coupon_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_claims TEXT;
BEGIN
  v_claims := NULLIF(current_setting('request.jwt.claims', TRUE), '');
  IF v_claims IS NULL OR COALESCE(v_claims::jsonb ->> 'role', '') = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.origin_coupon_id IS DISTINCT FROM OLD.origin_coupon_id
     OR NEW.selections IS DISTINCT FROM OLD.selections
     OR NEW.total_odds IS DISTINCT FROM OLD.total_odds
     OR NEW.combined_model_prob IS DISTINCT FROM OLD.combined_model_prob
     OR NEW.expected_value IS DISTINCT FROM OLD.expected_value
     OR NEW.stake_kcoin IS DISTINCT FROM OLD.stake_kcoin
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
     OR NEW.first_kickoff_at IS DISTINCT FROM OLD.first_kickoff_at
     OR NEW.resolved_at IS DISTINCT FROM OLD.resolved_at
     OR NEW.avg_clv IS DISTINCT FROM OLD.avg_clv
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'Only title and is_public can be changed after a coupon is shared';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER guard_analysis_coupon_update
  BEFORE UPDATE ON public.analysis_coupons
  FOR EACH ROW EXECUTE PROCEDURE public.guard_analysis_coupon_update();

-- =========================================
-- 3. Tipster stats recomputation (idempotent)
-- =========================================

-- Recalculates every period row for a user straight from analysis_coupons so
-- repeated settlement runs can never drift the aggregates.
CREATE OR REPLACE FUNCTION public.recompute_tipster_stats(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  WITH scoped AS (
    -- Every coupon counts once for the lifetime period and once for the month
    -- it was created in.
    SELECT c.*, periods.period
    FROM public.analysis_coupons c
    CROSS JOIN LATERAL (
      VALUES ('all'), (to_char(c.created_at, 'YYYY-MM'))
    ) AS periods(period)
    WHERE c.user_id = p_user_id
  ),
  coupon_stats AS (
    SELECT
      period,
      count(*)::int AS coupons_total,
      (count(*) FILTER (WHERE status <> 'pending'))::int AS coupons_settled,
      (count(*) FILTER (WHERE status = 'won'))::int AS coupons_won,
      -- Flat-stake ROI over settled coupons: a missing stake counts as 1 unit.
      COALESCE(sum(COALESCE(stake_kcoin, 1)) FILTER (WHERE status <> 'pending'), 0) AS total_staked,
      COALESCE(sum(
        CASE status
          WHEN 'won' THEN total_odds * COALESCE(stake_kcoin, 1)
          WHEN 'void' THEN COALESCE(stake_kcoin, 1)
          ELSE 0
        END
      ) FILTER (WHERE status <> 'pending'), 0) AS total_returned
    FROM scoped
    GROUP BY period
  ),
  clv_stats AS (
    -- CLV is sampled per selection across all settled coupons.
    SELECT
      s.period,
      avg((sel ->> 'clv')::numeric) AS avg_clv,
      (count(*) FILTER (WHERE (sel ->> 'clv') IS NOT NULL))::int AS clv_sample
    FROM scoped s
    CROSS JOIN LATERAL jsonb_array_elements(s.selections) AS sel
    WHERE s.status <> 'pending'
    GROUP BY s.period
  ),
  market_stats AS (
    SELECT
      period,
      jsonb_object_agg(market_code, jsonb_build_object('picks', picks, 'won', won)) AS market_breakdown
    FROM (
      SELECT
        s.period,
        sel ->> 'market_code' AS market_code,
        count(*)::int AS picks,
        (count(*) FILTER (WHERE sel ->> 'result' = 'won'))::int AS won
      FROM scoped s
      CROSS JOIN LATERAL jsonb_array_elements(s.selections) AS sel
      WHERE s.status <> 'pending'
      GROUP BY s.period, sel ->> 'market_code'
    ) per_market
    GROUP BY period
  )
  INSERT INTO public.tipster_stats AS ts (
    user_id, period, coupons_total, coupons_settled, coupons_won,
    total_staked, total_returned, roi, avg_clv, clv_sample,
    market_breakdown, updated_at
  )
  SELECT
    p_user_id,
    cs.period,
    cs.coupons_total,
    cs.coupons_settled,
    cs.coupons_won,
    cs.total_staked,
    cs.total_returned,
    CASE WHEN cs.total_staked > 0
         THEN (cs.total_returned - cs.total_staked) / cs.total_staked
    END,
    cl.avg_clv,
    COALESCE(cl.clv_sample, 0),
    COALESCE(ms.market_breakdown, '{}'::jsonb),
    NOW()
  FROM coupon_stats cs
  LEFT JOIN clv_stats cl USING (period)
  LEFT JOIN market_stats ms USING (period)
  ON CONFLICT (user_id, period)
  DO UPDATE SET
    coupons_total = EXCLUDED.coupons_total,
    coupons_settled = EXCLUDED.coupons_settled,
    coupons_won = EXCLUDED.coupons_won,
    total_staked = EXCLUDED.total_staked,
    total_returned = EXCLUDED.total_returned,
    roi = EXCLUDED.roi,
    avg_clv = EXCLUDED.avg_clv,
    clv_sample = EXCLUDED.clv_sample,
    market_breakdown = EXCLUDED.market_breakdown,
    updated_at = EXCLUDED.updated_at;
END;
$$;

-- =========================================
-- 4. share_coupon RPC (the only insert path)
-- =========================================

CREATE OR REPLACE FUNCTION public.share_coupon(
  p_selections JSONB,
  p_title TEXT,
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
  v_count INT;
  v_item JSONB;
  v_match_id UUID;
  v_market_code TEXT;
  v_selection_key TEXT;
  v_client_odds NUMERIC;
  v_model_prob NUMERIC;
  v_row RECORD;
  v_locked JSONB := '[]'::jsonb;
  v_total_odds NUMERIC := 1;
  v_combined_prob NUMERIC := 1;
  v_prob_complete BOOLEAN := TRUE;
  v_first_kickoff TIMESTAMPTZ;
  v_seen TEXT[] := ARRAY[]::TEXT[];
  v_dup_key TEXT;
  v_coupon public.analysis_coupons;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_selections IS NULL OR jsonb_typeof(p_selections) <> 'array' THEN
    RAISE EXCEPTION 'Selections must be a JSON array';
  END IF;

  v_count := jsonb_array_length(p_selections);
  IF v_count < 1 OR v_count > 20 THEN
    RAISE EXCEPTION 'A coupon must contain between 1 and 20 selections';
  END IF;

  IF p_stake_kcoin IS NOT NULL AND p_stake_kcoin <= 0 THEN
    RAISE EXCEPTION 'Stake must be positive';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_selections) LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'Each selection must be a JSON object';
    END IF;

    v_match_id := (v_item ->> 'bulletin_match_id')::uuid;
    v_market_code := NULLIF(btrim(COALESCE(v_item ->> 'market_code', '')), '');
    v_selection_key := NULLIF(btrim(COALESCE(v_item ->> 'selection_key', '')), '');
    v_client_odds := (v_item ->> 'odds_at_share')::numeric;

    IF v_match_id IS NULL OR v_market_code IS NULL OR v_selection_key IS NULL THEN
      RAISE EXCEPTION 'Each selection requires bulletin_match_id, market_code and selection_key';
    END IF;

    IF v_client_odds IS NULL OR v_client_odds <= 1.0 THEN
      RAISE EXCEPTION 'Each selection requires odds_at_share greater than 1.0';
    END IF;

    -- One pick per market per match: a doubled pick would inflate total_odds
    -- without adding any risk (leaderboard gaming).
    v_dup_key := v_match_id::text || '|' || v_market_code;
    IF v_dup_key = ANY (v_seen) THEN
      RAISE EXCEPTION 'Duplicate selection for market % on match %', v_market_code, v_match_id;
    END IF;
    v_seen := array_append(v_seen, v_dup_key);

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
      RAISE EXCEPTION 'Selection %/% not found in the bulletin for match %',
        v_market_code, v_selection_key, v_match_id;
    END IF;

    IF v_row.suspended THEN
      RAISE EXCEPTION 'Selection %/% is currently suspended', v_market_code, v_selection_key;
    END IF;

    IF v_row.odds IS NULL OR v_row.odds <= 1.0 THEN
      RAISE EXCEPTION 'No valid current odds for selection %/%', v_market_code, v_selection_key;
    END IF;

    -- Stale-client guard: the odds the user saw must be within 10% of the
    -- current bulletin odds. The current server-side odds are what gets
    -- locked on the coupon.
    IF abs(v_client_odds - v_row.odds) > v_row.odds * 0.10 THEN
      RAISE EXCEPTION 'Odds for %/% moved more than 10%% (client %, current %). Refresh the bulletin.',
        v_market_code, v_selection_key, v_client_odds, v_row.odds;
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
    p_title,
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

-- =========================================
-- 5. resolve_coupon_selections RPC (service role)
-- =========================================

-- Called by the resolve-coupons edge function with
-- p_results = [{index, result, closing_odds}], index being the zero-based
-- position inside the selections array. Selections may be settled across
-- several runs; the coupon resolves once none are left pending.
CREATE OR REPLACE FUNCTION public.resolve_coupon_selections(
  p_coupon_id UUID,
  p_results JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coupon public.analysis_coupons;
  v_selections JSONB;
  v_item JSONB;
  v_idx INT;
  v_result TEXT;
  v_closing NUMERIC;
  v_odds_at_share NUMERIC;
  v_clv NUMERIC;
  v_total INT;
  v_pending INT;
  v_void INT;
  v_lost INT;
  v_avg_clv NUMERIC;
  v_status TEXT;
BEGIN
  SELECT * INTO v_coupon
  FROM public.analysis_coupons
  WHERE id = p_coupon_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Coupon % does not exist', p_coupon_id;
  END IF;

  IF v_coupon.status <> 'pending' THEN
    RETURN jsonb_build_object(
      'success', true,
      'coupon_id', p_coupon_id,
      'status', v_coupon.status,
      'already_resolved', true
    );
  END IF;

  IF p_results IS NULL OR jsonb_typeof(p_results) <> 'array' THEN
    RAISE EXCEPTION 'Results must be a JSON array';
  END IF;

  v_selections := v_coupon.selections;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_results) LOOP
    v_idx := (v_item ->> 'index')::int;
    v_result := v_item ->> 'result';
    v_closing := (v_item ->> 'closing_odds')::numeric;

    IF v_idx IS NULL OR v_idx < 0 OR v_idx >= jsonb_array_length(v_selections) THEN
      RAISE EXCEPTION 'Selection index % out of range', v_item ->> 'index';
    END IF;

    IF v_result IS NULL OR v_result NOT IN ('won', 'lost', 'void') THEN
      RAISE EXCEPTION 'Invalid selection result: %', v_result;
    END IF;

    v_odds_at_share := (v_selections -> v_idx ->> 'odds_at_share')::numeric;

    -- CLV = closing implied prob / shared implied prob - 1
    --     = odds_at_share / closing_odds - 1 (positive = beat the close).
    v_clv := NULL;
    IF v_closing IS NOT NULL AND v_closing > 0 AND v_odds_at_share IS NOT NULL THEN
      v_clv := (v_odds_at_share / v_closing) - 1;
    END IF;

    v_selections := jsonb_set(
      v_selections,
      ARRAY[v_idx::text],
      (v_selections -> v_idx) || jsonb_build_object(
        'result', v_result,
        'closing_odds', v_closing,
        'clv', v_clv
      )
    );
  END LOOP;

  SELECT
    count(*),
    count(*) FILTER (WHERE sel ->> 'result' = 'pending'),
    count(*) FILTER (WHERE sel ->> 'result' = 'void'),
    count(*) FILTER (WHERE sel ->> 'result' = 'lost'),
    avg((sel ->> 'clv')::numeric)
  INTO v_total, v_pending, v_void, v_lost, v_avg_clv
  FROM jsonb_array_elements(v_selections) AS sel;

  IF v_pending > 0 THEN
    UPDATE public.analysis_coupons
    SET selections = v_selections
    WHERE id = p_coupon_id;

    RETURN jsonb_build_object(
      'success', true,
      'coupon_id', p_coupon_id,
      'status', 'pending',
      'pending_selections', v_pending
    );
  END IF;

  v_status := CASE
    WHEN v_void = v_total THEN 'void'
    WHEN v_lost = 0 THEN 'won'
    ELSE 'lost'
  END;

  UPDATE public.analysis_coupons
  SET selections = v_selections,
      status = v_status,
      resolved_at = NOW(),
      avg_clv = v_avg_clv
  WHERE id = p_coupon_id;

  -- Coin movement: payouts/refunds are credited through the existing ledger
  -- function credit_k_coins_server, but only when the stake was actually
  -- debited from the wallet (share_coupon cannot debit yet — see the
  -- TODO(k-coin) there). Without this guard a stake that never left the
  -- wallet would mint stake * total_odds out of thin air.
  IF v_coupon.stake_kcoin IS NOT NULL
     AND v_status IN ('won', 'void')
     AND EXISTS (
       SELECT 1
       FROM public.k_coin_transactions
       WHERE user_id = v_coupon.user_id
         AND idempotency_key = format('coupon_stake:%s', v_coupon.id)
         AND amount < 0
     )
  THEN
    IF v_status = 'won' THEN
      PERFORM public.credit_k_coins_server(
        v_coupon.user_id,
        FLOOR(v_coupon.stake_kcoin * v_coupon.total_odds)::int,
        'prediction_payout',
        v_coupon.id::text,
        'Analysis coupon payout',
        'analysis_coupon',
        v_coupon.id::text,
        format('coupon_payout:%s', v_coupon.id),
        jsonb_build_object(
          'coupon_id', v_coupon.id,
          'stake_kcoin', v_coupon.stake_kcoin,
          'total_odds', v_coupon.total_odds
        )
      );
    ELSE
      PERFORM public.credit_k_coins_server(
        v_coupon.user_id,
        v_coupon.stake_kcoin,
        'prediction_refund',
        v_coupon.id::text,
        'Analysis coupon void refund',
        'analysis_coupon',
        v_coupon.id::text,
        format('coupon_refund:%s', v_coupon.id),
        jsonb_build_object(
          'coupon_id', v_coupon.id,
          'stake_kcoin', v_coupon.stake_kcoin
        )
      );
    END IF;
  END IF;

  PERFORM public.recompute_tipster_stats(v_coupon.user_id);

  RETURN jsonb_build_object(
    'success', true,
    'coupon_id', p_coupon_id,
    'status', v_status,
    'avg_clv', v_avg_clv,
    'resolved', true
  );
END;
$$;

-- =========================================
-- 6. Leaderboard view
-- =========================================

-- SECURITY INVOKER: RLS of tipster_stats/users applies to the caller. Only
-- tipsters with a meaningful sample (>= 10 settled coupons) are ranked.
CREATE VIEW public.tipster_leaderboard
WITH (security_invoker = true)
AS
SELECT
  ts.user_id,
  u.username,
  u.avatar_url,
  ts.period,
  ts.roi,
  ts.avg_clv,
  ts.clv_sample,
  ts.coupons_settled,
  round(ts.coupons_won::numeric / NULLIF(ts.coupons_settled, 0), 4) AS win_rate
FROM public.tipster_stats ts
JOIN public.users u ON u.id = ts.user_id
WHERE ts.coupons_settled >= 10;

-- =========================================
-- 7. Row Level Security
-- =========================================

ALTER TABLE public.analysis_coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipster_stats ENABLE ROW LEVEL SECURITY;

-- COUPONS: public coupons for everyone, private ones for their owner. Inserts
-- happen only through share_coupon, updates are trigger-guarded, deletes are
-- service role only (no policy).
CREATE POLICY "Public coupons or own coupons are viewable."
  ON public.analysis_coupons FOR SELECT
  USING (is_public = true OR user_id = auth.uid());
CREATE POLICY "Owners can update own coupons."
  ON public.analysis_coupons FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- LIKES: visible to authenticated users, each user manages own likes.
CREATE POLICY "Likes are viewable by authenticated users."
  ON public.coupon_likes FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "Users can like coupons."
  ON public.coupon_likes FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can remove own likes."
  ON public.coupon_likes FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- COMMENTS: visible to authenticated users, each user manages own comments.
CREATE POLICY "Comments are viewable by authenticated users."
  ON public.coupon_comments FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "Users can comment on coupons."
  ON public.coupon_comments FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own comments."
  ON public.coupon_comments FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- STATS: readable by everyone (feeds the leaderboard), written only by the
-- SECURITY DEFINER functions above.
CREATE POLICY "Tipster stats are viewable by everyone."
  ON public.tipster_stats FOR SELECT
  USING (true);

-- =========================================
-- 8. Privileges
-- =========================================

-- Coupons are written through the RPCs only; owners keep column-level UPDATE
-- on title/is_public (further guarded by the trigger + RLS).
REVOKE INSERT, UPDATE, DELETE ON public.analysis_coupons FROM anon, authenticated;
GRANT UPDATE (title, is_public) ON public.analysis_coupons TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.tipster_stats FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.share_coupon(JSONB, TEXT, INT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.share_coupon(JSONB, TEXT, INT, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.share_coupon(JSONB, TEXT, INT, BOOLEAN) TO authenticated;

REVOKE ALL ON FUNCTION public.resolve_coupon_selections(UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_coupon_selections(UUID, JSONB) FROM authenticated;
REVOKE ALL ON FUNCTION public.resolve_coupon_selections(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_coupon_selections(UUID, JSONB) TO service_role;

REVOKE ALL ON FUNCTION public.recompute_tipster_stats(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recompute_tipster_stats(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION public.recompute_tipster_stats(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.recompute_tipster_stats(UUID) TO service_role;

GRANT SELECT ON public.tipster_leaderboard TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
