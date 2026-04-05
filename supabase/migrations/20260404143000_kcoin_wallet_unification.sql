-- K-Coin wallet unification and gamification settlement

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS k_coin_balance INTEGER;

UPDATE public.users
SET k_coin_balance = COALESCE(k_coin_balance, virtual_currency_balance, 0)
WHERE k_coin_balance IS NULL;

ALTER TABLE public.users
  ALTER COLUMN k_coin_balance SET DEFAULT 0;

ALTER TABLE public.users
  ALTER COLUMN k_coin_balance SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.k_coin_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL,
  transaction_type TEXT NOT NULL,
  reference_id TEXT,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.k_coin_transactions
  ADD COLUMN IF NOT EXISTS source_type TEXT,
  ADD COLUMN IF NOT EXISTS source_id TEXT,
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS metadata JSONB,
  ADD COLUMN IF NOT EXISTS balance_after INTEGER;

UPDATE public.k_coin_transactions
SET metadata = '{}'::jsonb
WHERE metadata IS NULL;

UPDATE public.k_coin_transactions
SET idempotency_key = gen_random_uuid()::text
WHERE idempotency_key IS NULL OR btrim(idempotency_key) = '';

ALTER TABLE public.k_coin_transactions
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb;

ALTER TABLE public.k_coin_transactions
  ALTER COLUMN metadata SET NOT NULL;

ALTER TABLE public.k_coin_transactions
  ALTER COLUMN idempotency_key SET DEFAULT gen_random_uuid()::text;

ALTER TABLE public.k_coin_transactions
  ALTER COLUMN idempotency_key SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_k_coin_transactions_idempotency_key
  ON public.k_coin_transactions(idempotency_key);

CREATE INDEX IF NOT EXISTS idx_k_coin_transactions_user_created_at
  ON public.k_coin_transactions(user_id, created_at DESC);

ALTER TABLE public.k_coin_transactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'k_coin_transactions'
      AND policyname = 'Users can view own K-Coin transactions'
  ) THEN
    CREATE POLICY "Users can view own K-Coin transactions"
      ON public.k_coin_transactions
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END;
$$;

ALTER TABLE public.k_coin_purchasing_history
  ADD COLUMN IF NOT EXISTS ledger_transaction_id UUID REFERENCES public.k_coin_transactions(id) ON DELETE SET NULL;

ALTER TABLE public.user_bets
  ADD COLUMN IF NOT EXISTS request_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_bets_user_request_id
  ON public.user_bets(user_id, request_id)
  WHERE request_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.check_ad_eligibility_for_user(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_daily_limit INT;
    v_cooldown_mins INT;
    v_today_watch_count INT;
    v_last_watch_time TIMESTAMPTZ;
    v_next_available_time TIMESTAMPTZ;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'not_authenticated');
    END IF;

    SELECT COALESCE(
      (SELECT value FROM public.app_settings WHERE key = 'daily_ad_limit'),
      '5'
    )::INT
    INTO v_daily_limit;

    SELECT COALESCE(
      (SELECT value FROM public.app_settings WHERE key = 'ad_cooldown_minutes'),
      '10'
    )::INT
    INTO v_cooldown_mins;

    SELECT COUNT(*)
    INTO v_today_watch_count
    FROM public.k_coin_transactions
    WHERE user_id = p_user_id
      AND transaction_type = 'rewarded_ad'
      AND created_at >= date_trunc('day', timezone('utc'::text, now()));

    IF v_today_watch_count >= v_daily_limit THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'daily_limit_reached');
    END IF;

    SELECT MAX(created_at)
    INTO v_last_watch_time
    FROM public.k_coin_transactions
    WHERE user_id = p_user_id
      AND transaction_type = 'rewarded_ad';

    IF v_last_watch_time IS NOT NULL THEN
        v_next_available_time := v_last_watch_time + (v_cooldown_mins || ' minutes')::interval;

        IF timezone('utc'::text, now()) < v_next_available_time THEN
            RETURN jsonb_build_object(
                'eligible', false,
                'reason', 'cooling_down',
                'next_available', v_next_available_time
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
      'eligible', true,
      'remaining_daily', v_daily_limit - v_today_watch_count
    );
END;
$$;

REVOKE ALL ON FUNCTION public.check_ad_eligibility_for_user(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_ad_eligibility_for_user(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION public.check_ad_eligibility_for_user(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_ad_eligibility_for_user(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.check_ad_eligibility()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public.check_ad_eligibility_for_user(auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_ad_eligibility() TO authenticated;

CREATE OR REPLACE FUNCTION public.credit_k_coins_server(
    p_user_id UUID,
    p_amount INT,
    p_transaction_type TEXT,
    p_reference_id TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_source_type TEXT DEFAULT NULL,
    p_source_id TEXT DEFAULT NULL,
    p_idempotency_key TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_transaction_type TEXT;
    v_idempotency_key TEXT;
    v_existing RECORD;
    v_current_balance INT;
    v_new_balance INT;
    v_transaction_id UUID;
    v_allowed_types CONSTANT TEXT[] := ARRAY[
      'topup',
      'rewarded_ad',
      'daily_reward',
      'task_reward',
      'store_purchase',
      'prediction_stake',
      'prediction_payout',
      'prediction_refund',
      'admin_adjustment'
    ];
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID is required';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive';
    END IF;

    v_transaction_type := lower(btrim(COALESCE(p_transaction_type, '')));
    IF v_transaction_type = '' OR NOT (v_transaction_type = ANY (v_allowed_types)) THEN
        RAISE EXCEPTION 'Unsupported transaction type: %', p_transaction_type;
    END IF;

    v_idempotency_key := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');

    IF v_idempotency_key IS NOT NULL THEN
        SELECT id, balance_after
        INTO v_existing
        FROM public.k_coin_transactions
        WHERE user_id = p_user_id
          AND idempotency_key = v_idempotency_key
        LIMIT 1;

        IF FOUND THEN
            RETURN jsonb_build_object(
                'success', true,
                'new_balance', v_existing.balance_after,
                'transaction_id', v_existing.id,
                'already_applied', true
            );
        END IF;
    ELSE
        v_idempotency_key := gen_random_uuid()::text;
    END IF;

    SELECT k_coin_balance
    INTO v_current_balance
    FROM public.users
    WHERE id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found: %', p_user_id;
    END IF;

    v_current_balance := COALESCE(v_current_balance, 0);
    v_new_balance := v_current_balance + p_amount;

    UPDATE public.users
    SET k_coin_balance = v_new_balance
    WHERE id = p_user_id;

    INSERT INTO public.k_coin_transactions (
        user_id,
        amount,
        transaction_type,
        reference_id,
        description,
        source_type,
        source_id,
        idempotency_key,
        metadata,
        balance_after
    )
    VALUES (
        p_user_id,
        p_amount,
        v_transaction_type,
        p_reference_id,
        p_description,
        p_source_type,
        p_source_id,
        v_idempotency_key,
        COALESCE(p_metadata, '{}'::jsonb),
        v_new_balance
    )
    RETURNING id INTO v_transaction_id;

    RETURN jsonb_build_object(
        'success', true,
        'new_balance', v_new_balance,
        'transaction_id', v_transaction_id,
        'already_applied', false
    );
EXCEPTION
    WHEN unique_violation THEN
        IF v_idempotency_key IS NOT NULL THEN
            SELECT id, balance_after
            INTO v_existing
            FROM public.k_coin_transactions
            WHERE user_id = p_user_id
              AND idempotency_key = v_idempotency_key
            LIMIT 1;

            IF FOUND THEN
                RETURN jsonb_build_object(
                    'success', true,
                    'new_balance', v_existing.balance_after,
                    'transaction_id', v_existing.id,
                    'already_applied', true
                );
            END IF;
        END IF;

        RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.credit_k_coins_server(UUID, INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.credit_k_coins_server(UUID, INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) FROM authenticated;
REVOKE ALL ON FUNCTION public.credit_k_coins_server(UUID, INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.credit_k_coins_server(UUID, INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.grant_k_coins_server(p_user_id UUID, p_amount INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT public.credit_k_coins_server(
        p_user_id,
        p_amount,
        'topup',
        NULL,
        format('Granted %s K-Coins', p_amount),
        'legacy_grant',
        NULL,
        NULL,
        jsonb_build_object('legacy_wrapper', true)
    )
    INTO v_result;

    RETURN v_result || jsonb_build_object('coins_granted', p_amount);
END;
$$;

REVOKE ALL ON FUNCTION public.grant_k_coins_server(UUID, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_k_coins_server(UUID, INT) FROM authenticated;
REVOKE ALL ON FUNCTION public.grant_k_coins_server(UUID, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.grant_k_coins_server(UUID, INT) TO service_role;

CREATE OR REPLACE FUNCTION public.reward_k_coins(p_amount INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_eligibility JSONB;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to receive rewards.';
    END IF;

    v_eligibility := public.check_ad_eligibility_for_user(v_user_id);
    IF NOT COALESCE((v_eligibility->>'eligible')::boolean, false) THEN
        RAISE EXCEPTION 'Ad limit or cooldown violated. Reason: %', v_eligibility->>'reason';
    END IF;

    IF p_amount <= 0 OR p_amount > 100 THEN
        RAISE EXCEPTION 'Invalid reward amount: %', p_amount;
    END IF;

    SELECT public.credit_k_coins_server(
        v_user_id,
        p_amount,
        'rewarded_ad',
        'admob_reward',
        format('Earned %s K-Coins from Rewarded Ad', p_amount),
        'rewarded_ad',
        'admob_reward',
        NULL,
        jsonb_build_object('eligibility', v_eligibility)
    )
    INTO v_result;

    RETURN v_result || jsonb_build_object('coins_granted', p_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reward_k_coins(INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.buy_store_item_server(
  p_user_id UUID,
  p_product_code TEXT,
  p_request_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product public.store_products%ROWTYPE;
  v_theme public.app_themes%ROWTYPE;
  v_current_balance INTEGER;
  v_new_balance INTEGER;
  v_expires_at TIMESTAMPTZ;
  v_existing_expires_at TIMESTAMPTZ;
  v_transaction_id UUID;
  v_entitlement_id UUID;
  v_existing RECORD;
  v_idempotency_key TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User is required';
  END IF;

  IF p_product_code IS NULL OR btrim(p_product_code) = '' THEN
    RAISE EXCEPTION 'Product code is required';
  END IF;

  IF p_request_id IS NULL OR btrim(p_request_id) = '' THEN
    RAISE EXCEPTION 'Request ID is required';
  END IF;

  v_idempotency_key := format('store_purchase:%s:%s', p_user_id, btrim(p_request_id));

  SELECT
    tx.id,
    tx.balance_after,
    ent.id AS entitlement_id
  INTO v_existing
  FROM public.k_coin_transactions tx
  LEFT JOIN LATERAL (
    SELECT ue.id
    FROM public.user_entitlements ue
    WHERE ue.user_id = p_user_id
      AND ue.product_code = p_product_code
      AND ue.is_active = true
    ORDER BY ue.purchased_at DESC
    LIMIT 1
  ) ent ON true
  WHERE tx.user_id = p_user_id
    AND tx.idempotency_key = v_idempotency_key
  LIMIT 1;

  IF FOUND THEN
    SELECT *
    INTO v_product
    FROM public.store_products
    WHERE product_code = p_product_code;

    RETURN jsonb_build_object(
      'success', true,
      'new_balance', v_existing.balance_after,
      'transaction_id', v_existing.id,
      'entitlement_id', v_existing.entitlement_id,
      'product_code', p_product_code,
      'product_category', COALESCE(v_product.product_category, 'general'),
      'theme_code', v_product.theme_code,
      'already_applied', true
    );
  END IF;

  SELECT *
  INTO v_product
  FROM public.store_products
  WHERE product_code = p_product_code
    AND is_active = true
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found or inactive';
  END IF;

  IF COALESCE(v_product.product_category, 'general') = 'app_theme' THEN
    IF v_product.product_type <> 'lifetime' OR v_product.theme_code IS NULL THEN
      RAISE EXCEPTION 'Theme products must be lifetime products linked to an active theme';
    END IF;

    SELECT *
    INTO v_theme
    FROM public.app_themes
    WHERE theme_code = v_product.theme_code
    FOR SHARE;

    IF NOT FOUND OR v_theme.status <> 'published' OR v_theme.is_active IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'This theme is currently unavailable';
    END IF;
  END IF;

  IF v_product.product_type = 'lifetime' AND EXISTS (
    SELECT 1
    FROM public.user_entitlements
    WHERE user_id = p_user_id
      AND product_code = p_product_code
      AND is_active = true
      AND expires_at IS NULL
  ) THEN
    RAISE EXCEPTION 'This item is already owned';
  END IF;

  SELECT k_coin_balance
  INTO v_current_balance
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  v_current_balance := COALESCE(v_current_balance, 0);

  IF v_current_balance < v_product.price THEN
    RAISE EXCEPTION 'Insufficient K-Coin balance';
  END IF;

  v_new_balance := v_current_balance - v_product.price;

  UPDATE public.users
  SET k_coin_balance = v_new_balance
  WHERE id = p_user_id;

  INSERT INTO public.k_coin_transactions (
    user_id,
    amount,
    transaction_type,
    reference_id,
    description,
    source_type,
    source_id,
    idempotency_key,
    metadata,
    balance_after
  ) VALUES (
    p_user_id,
    -v_product.price,
    'store_purchase',
    p_product_code,
    'Purchased store item: ' || v_product.title,
    'store_purchase',
    p_product_code,
    v_idempotency_key,
    jsonb_build_object(
      'product_code', v_product.product_code,
      'product_category', COALESCE(v_product.product_category, 'general'),
      'theme_code', v_product.theme_code,
      'request_id', btrim(p_request_id)
    ),
    v_new_balance
  )
  RETURNING id INTO v_transaction_id;

  IF v_product.product_type <> 'consumable' THEN
    IF v_product.product_type = 'subscription' THEN
      SELECT expires_at
      INTO v_existing_expires_at
      FROM public.user_entitlements
      WHERE user_id = p_user_id
        AND product_code = p_product_code
        AND is_active = true
      ORDER BY expires_at DESC NULLS LAST
      LIMIT 1;

      IF v_existing_expires_at IS NOT NULL AND v_existing_expires_at > NOW() THEN
        v_expires_at := v_existing_expires_at + (v_product.duration_days * INTERVAL '1 day');
      ELSE
        v_expires_at := NOW() + (v_product.duration_days * INTERVAL '1 day');
      END IF;
    ELSE
      v_expires_at := NULL;
    END IF;

    INSERT INTO public.user_entitlements (
      user_id,
      product_code,
      expires_at,
      is_active
    )
    VALUES (
      p_user_id,
      p_product_code,
      v_expires_at,
      true
    )
    ON CONFLICT (user_id, product_code)
    DO UPDATE SET
      expires_at = EXCLUDED.expires_at,
      is_active = true,
      purchased_at = NOW()
    RETURNING id INTO v_entitlement_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_balance', v_new_balance,
    'transaction_id', v_transaction_id,
    'entitlement_id', v_entitlement_id,
    'product_code', v_product.product_code,
    'product_category', COALESCE(v_product.product_category, 'general'),
    'theme_code', v_product.theme_code,
    'already_applied', false
  );
EXCEPTION
  WHEN unique_violation THEN
    SELECT
      tx.id,
      tx.balance_after,
      ent.id AS entitlement_id
    INTO v_existing
    FROM public.k_coin_transactions tx
    LEFT JOIN LATERAL (
      SELECT ue.id
      FROM public.user_entitlements ue
      WHERE ue.user_id = p_user_id
        AND ue.product_code = p_product_code
        AND ue.is_active = true
      ORDER BY ue.purchased_at DESC
      LIMIT 1
    ) ent ON true
    WHERE tx.user_id = p_user_id
      AND tx.idempotency_key = v_idempotency_key
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'new_balance', v_existing.balance_after,
        'transaction_id', v_existing.id,
        'entitlement_id', v_existing.entitlement_id,
        'product_code', v_product.product_code,
        'product_category', COALESCE(v_product.product_category, 'general'),
        'theme_code', v_product.theme_code,
        'already_applied', true
      );
    END IF;

    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.buy_store_item_server(
  p_user_id UUID,
  p_product_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.buy_store_item_server(
    p_user_id,
    p_product_code,
    gen_random_uuid()::text
  );
END;
$$;

REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT, TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.buy_store_item_server(UUID, TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.buy_store_item_server(UUID, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.place_bet(
  p_user_id UUID,
  p_prediction_id UUID,
  p_amount INT,
  p_request_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance INT;
  v_new_balance INT;
  v_odds DECIMAL;
  v_potential_payout INT;
  v_bet_id UUID;
  v_transaction_id UUID;
  v_existing RECORD;
  v_idempotency_key TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User is required';
  END IF;

  IF p_request_id IS NULL OR btrim(p_request_id) = '' THEN
    RAISE EXCEPTION 'Request ID is required';
  END IF;

  v_idempotency_key := format('prediction_stake:%s:%s', p_user_id, btrim(p_request_id));

  SELECT ub.id, tx.balance_after
  INTO v_existing
  FROM public.user_bets ub
  LEFT JOIN public.k_coin_transactions tx
    ON tx.user_id = ub.user_id
   AND tx.idempotency_key = v_idempotency_key
  WHERE ub.user_id = p_user_id
    AND ub.request_id = btrim(p_request_id)
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'bet_id', v_existing.id,
      'transaction_id', NULL,
      'new_balance', v_existing.balance_after,
      'already_applied', true
    );
  END IF;

  SELECT k_coin_balance
  INTO v_balance
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  v_balance := COALESCE(v_balance, 0);

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Bet amount must be positive';
  END IF;

  IF v_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient prediction coin balance';
  END IF;

  SELECT odds
  INTO v_odds
  FROM public.predictions
  WHERE id = p_prediction_id
    AND status = 'open'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prediction market is not open or does not exist';
  END IF;

  v_potential_payout := (p_amount * v_odds)::INT;
  v_new_balance := v_balance - p_amount;

  UPDATE public.users
  SET k_coin_balance = v_new_balance
  WHERE id = p_user_id;

  INSERT INTO public.user_bets (
    user_id,
    prediction_id,
    amount_staked,
    potential_payout,
    status,
    request_id
  )
  VALUES (
    p_user_id,
    p_prediction_id,
    p_amount,
    v_potential_payout,
    'pending',
    btrim(p_request_id)
  )
  RETURNING id INTO v_bet_id;

  INSERT INTO public.k_coin_transactions (
    user_id,
    amount,
    transaction_type,
    reference_id,
    description,
    source_type,
    source_id,
    idempotency_key,
    metadata,
    balance_after
  )
  VALUES (
    p_user_id,
    -p_amount,
    'prediction_stake',
    p_prediction_id::text,
    'Placed prediction bet',
    'prediction',
    v_bet_id::text,
    v_idempotency_key,
    jsonb_build_object(
      'prediction_id', p_prediction_id,
      'bet_id', v_bet_id,
      'potential_payout', v_potential_payout,
      'request_id', btrim(p_request_id)
    ),
    v_new_balance
  )
  RETURNING id INTO v_transaction_id;

  RETURN jsonb_build_object(
    'success', true,
    'bet_id', v_bet_id,
    'transaction_id', v_transaction_id,
    'new_balance', v_new_balance,
    'already_applied', false
  );
EXCEPTION
  WHEN unique_violation THEN
    SELECT ub.id, tx.balance_after
    INTO v_existing
    FROM public.user_bets ub
    LEFT JOIN public.k_coin_transactions tx
      ON tx.user_id = ub.user_id
     AND tx.idempotency_key = v_idempotency_key
    WHERE ub.user_id = p_user_id
      AND ub.request_id = btrim(p_request_id)
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'bet_id', v_existing.id,
        'transaction_id', NULL,
        'new_balance', v_existing.balance_after,
        'already_applied', true
      );
    END IF;

    RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION public.place_bet(
  p_user_id UUID,
  p_prediction_id UUID,
  p_amount INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.place_bet(
    p_user_id,
    p_prediction_id,
    p_amount,
    gen_random_uuid()::text
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_bet(UUID, UUID, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_bet(UUID, UUID, INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_prediction(p_prediction_id UUID, p_result TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bet RECORD;
  v_new_balance INT;
BEGIN
  IF p_result NOT IN ('won', 'lost', 'null') THEN
    RAISE EXCEPTION 'Invalid result type. Must be won, lost, or null.';
  END IF;

  UPDATE public.predictions
  SET status = 'resolved', result = p_result
  WHERE id = p_prediction_id
    AND status = 'open';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prediction is already resolved or does not exist';
  END IF;

  FOR v_bet IN
    SELECT *
    FROM public.user_bets
    WHERE prediction_id = p_prediction_id
      AND status = 'pending'
    FOR UPDATE
  LOOP
    IF p_result = 'won' THEN
      UPDATE public.users
      SET k_coin_balance = COALESCE(k_coin_balance, 0) + v_bet.potential_payout
      WHERE id = v_bet.user_id
      RETURNING k_coin_balance INTO v_new_balance;

      INSERT INTO public.k_coin_transactions (
        user_id,
        amount,
        transaction_type,
        reference_id,
        description,
        source_type,
        source_id,
        idempotency_key,
        metadata,
        balance_after
      )
      VALUES (
        v_bet.user_id,
        v_bet.potential_payout,
        'prediction_payout',
        p_prediction_id::text,
        'Prediction payout',
        'prediction',
        v_bet.id::text,
        format('prediction_payout:%s', v_bet.id),
        jsonb_build_object(
          'prediction_id', p_prediction_id,
          'bet_id', v_bet.id
        ),
        v_new_balance
      )
      ON CONFLICT (idempotency_key) DO NOTHING;

      UPDATE public.user_bets
      SET status = 'won'
      WHERE id = v_bet.id;
    ELSIF p_result = 'lost' THEN
      UPDATE public.user_bets
      SET status = 'lost'
      WHERE id = v_bet.id;
    ELSIF p_result = 'null' THEN
      UPDATE public.users
      SET k_coin_balance = COALESCE(k_coin_balance, 0) + v_bet.amount_staked
      WHERE id = v_bet.user_id
      RETURNING k_coin_balance INTO v_new_balance;

      INSERT INTO public.k_coin_transactions (
        user_id,
        amount,
        transaction_type,
        reference_id,
        description,
        source_type,
        source_id,
        idempotency_key,
        metadata,
        balance_after
      )
      VALUES (
        v_bet.user_id,
        v_bet.amount_staked,
        'prediction_refund',
        p_prediction_id::text,
        'Prediction refund',
        'prediction',
        v_bet.id::text,
        format('prediction_refund:%s', v_bet.id),
        jsonb_build_object(
          'prediction_id', p_prediction_id,
          'bet_id', v_bet.id
        ),
        v_new_balance
      )
      ON CONFLICT (idempotency_key) DO NOTHING;

      UPDATE public.user_bets
      SET status = 'refunded'
      WHERE id = v_bet.id;
    END IF;
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_update_user_balance(UUID, INT);

CREATE OR REPLACE FUNCTION public.admin_update_user_balance(
  target_user_id UUID,
  new_balance INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
  v_current_balance INT;
  v_delta INT;
  v_transaction_id UUID;
BEGIN
  v_admin_id := auth.uid();

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = v_admin_id
      AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target user is required';
  END IF;

  IF new_balance < 0 THEN
    RAISE EXCEPTION 'Balance cannot be negative';
  END IF;

  SELECT k_coin_balance
  INTO v_current_balance
  FROM public.users
  WHERE id = target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  v_current_balance := COALESCE(v_current_balance, 0);
  v_delta := new_balance - v_current_balance;

  IF v_delta = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'new_balance', new_balance,
      'transaction_id', NULL,
      'delta', 0,
      'no_change', true
    );
  END IF;

  UPDATE public.users
  SET k_coin_balance = new_balance
  WHERE id = target_user_id;

  INSERT INTO public.k_coin_transactions (
    user_id,
    amount,
    transaction_type,
    reference_id,
    description,
    source_type,
    source_id,
    metadata,
    balance_after
  )
  VALUES (
    target_user_id,
    v_delta,
    'admin_adjustment',
    v_admin_id::text,
    'Admin balance adjustment',
    'admin',
    v_admin_id::text,
    jsonb_build_object(
      'previous_balance', v_current_balance,
      'new_balance', new_balance
    ),
    new_balance
  )
  RETURNING id INTO v_transaction_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_balance', new_balance,
    'transaction_id', v_transaction_id,
    'delta', v_delta
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_user_balance(UUID, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_user_balance(UUID, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_balance(UUID, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';
