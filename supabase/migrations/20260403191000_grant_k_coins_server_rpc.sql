-- Migration: Server-side atomic coin grant for webhooks
-- The existing reward_k_coins uses auth.uid() which won't work from service_role context.
-- This creates a separate function for trusted server-side calls (webhook, admin).

CREATE OR REPLACE FUNCTION public.grant_k_coins_server(p_user_id UUID, p_amount INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_balance INT;
BEGIN
    -- Validate inputs
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID is required';
    END IF;
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive: %', p_amount;
    END IF;

    -- Atomic increment with row lock to prevent race conditions
    UPDATE public.users
    SET k_coin_balance = COALESCE(k_coin_balance, 0) + p_amount
    WHERE id = p_user_id
    RETURNING k_coin_balance INTO v_new_balance;

    IF v_new_balance IS NULL THEN
        RAISE EXCEPTION 'User not found: %', p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'new_balance', v_new_balance,
        'coins_granted', p_amount
    );
END;
$$;

-- Only allow service_role to call this (not exposed to client)
REVOKE ALL ON FUNCTION public.grant_k_coins_server(UUID, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_k_coins_server(UUID, INT) FROM authenticated;
REVOKE ALL ON FUNCTION public.grant_k_coins_server(UUID, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.grant_k_coins_server(UUID, INT) TO service_role;
