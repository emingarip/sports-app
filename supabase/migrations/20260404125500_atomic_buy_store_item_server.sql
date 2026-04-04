CREATE OR REPLACE FUNCTION public.buy_store_item_server(
  p_user_id UUID,
  p_product_code TEXT
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
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User is required';
  END IF;

  IF p_product_code IS NULL OR btrim(p_product_code) = '' THEN
    RAISE EXCEPTION 'Product code is required';
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
    description
  ) VALUES (
    p_user_id,
    -v_product.price,
    'store_purchase',
    p_product_code,
    'Purchased store item: ' || v_product.title
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
    'theme_code', v_product.theme_code
  );
END;
$$;

REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION public.buy_store_item_server(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.buy_store_item_server(UUID, TEXT) TO service_role;
