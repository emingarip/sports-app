-- Migration: Add Reward K-Coins RPC
-- Description: Safely increments user's k_coin_balance when they watch a rewarded AdMob video and logs the transaction.

CREATE OR REPLACE FUNCTION public.reward_k_coins(p_amount INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_current_balance INT;
    v_new_balance INT;
    v_transaction_id UUID;
BEGIN
    -- 1. Check authentication
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to receive rewards.';
    END IF;

    -- 2. Validate amount to prevent client-side spoofing (e.g. max 50 per ad)
    IF p_amount <= 0 OR p_amount > 100 THEN
        RAISE EXCEPTION 'Invalid reward amount: %', p_amount;
    END IF;

    -- 3. Get current balance and lock row
    SELECT k_coin_balance INTO v_current_balance
    FROM public.users
    WHERE id = v_user_id
    FOR UPDATE;

    -- 4. Calculate new balance
    v_new_balance := v_current_balance + p_amount;

    -- 5. Update user balance
    UPDATE public.users
    SET k_coin_balance = v_new_balance
    WHERE id = v_user_id;

    -- 6. Record the transaction in the ledger
    INSERT INTO public.k_coin_transactions (
        user_id, 
        amount, 
        transaction_type, 
        reference_id, 
        description
    )
    VALUES (
        v_user_id, 
        p_amount, 
        'rewarded_ad', 
        'admob_reward', 
        'Earned ' || p_amount || ' K-Coins from Rewarded Ad'
    ) RETURNING id INTO v_transaction_id;

    -- 7. Return success
    RETURN jsonb_build_object(
        'success', true,
        'new_balance', v_new_balance,
        'transaction_id', v_transaction_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE; -- Auto rollback
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION public.reward_k_coins(INT) TO authenticated;
