-- Insert the default values for the new ad limits
INSERT INTO public.app_settings (key, value)
VALUES 
  ('daily_ad_limit', '5'),
  ('ad_cooldown_minutes', '10')
ON CONFLICT (key) DO NOTHING;

-- Create the readonly check eligibility RPC
CREATE OR REPLACE FUNCTION public.check_ad_eligibility()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_daily_limit INT;
    v_cooldown_mins INT;
    v_today_watch_count INT;
    v_last_watch_time TIMESTAMP WITH TIME ZONE;
    v_next_available_time TIMESTAMP WITH TIME ZONE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'not_authenticated');
    END IF;

    -- Fetch settings (default limit 5, cooldown 10)
    SELECT COALESCE((SELECT value FROM public.app_settings WHERE key = 'daily_ad_limit'), '5')::INT INTO v_daily_limit;
    SELECT COALESCE((SELECT value FROM public.app_settings WHERE key = 'ad_cooldown_minutes'), '10')::INT INTO v_cooldown_mins;

    -- Count today's watched ads
    SELECT COUNT(*) INTO v_today_watch_count
    FROM public.k_coin_transactions
    WHERE user_id = v_user_id
      AND transaction_type = 'rewarded_ad'
      AND created_at >= date_trunc('day', timezone('utc'::text, now()));

    IF v_today_watch_count >= v_daily_limit THEN
        RETURN jsonb_build_object('eligible', false, 'reason', 'daily_limit_reached');
    END IF;

    -- Check cooldown
    SELECT MAX(created_at) INTO v_last_watch_time
    FROM public.k_coin_transactions
    WHERE user_id = v_user_id
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

    RETURN jsonb_build_object('eligible', true, 'remaining_daily', v_daily_limit - v_today_watch_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_ad_eligibility() TO authenticated;


-- Modify existing reward_k_coins to enforce these checks securely (server side hard-block)
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
    v_eligibility JSONB;
BEGIN
    -- 1. Check authentication
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to receive rewards.';
    END IF;

    -- 1.5 CHECK ELIGIBILITY
    v_eligibility := public.check_ad_eligibility();
    IF NOT (v_eligibility->>'eligible')::boolean THEN
        RAISE EXCEPTION 'Ad limit or cooldown violated. Reason: %', v_eligibility->>'reason';
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

-- Force PostgREST schema cache clear
NOTIFY pgrst, 'reload schema';
