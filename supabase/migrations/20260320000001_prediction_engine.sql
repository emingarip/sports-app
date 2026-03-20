-- Migration: Prediction Engine & Payout Transactions

-- 1. Function to place a bet safely (ACID compliant)
CREATE OR REPLACE FUNCTION public.place_bet(p_user_id UUID, p_prediction_id UUID, p_amount INT)
RETURNS VOID AS $$
DECLARE
  v_balance INT;
  v_odds DECIMAL;
BEGIN
  -- Lock the user row for update to prevent concurrent race conditions
  SELECT virtual_currency_balance INTO v_balance FROM public.users WHERE id = p_user_id FOR UPDATE;
  
  IF v_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient prediction coin balance';
  END IF;

  -- Lock the prediction row and ensure it is still open for voting
  SELECT odds INTO v_odds FROM public.predictions WHERE id = p_prediction_id AND status = 'open' FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prediction market is not open or does not exist';
  END IF;

  -- Deduct user balance
  UPDATE public.users SET virtual_currency_balance = virtual_currency_balance - p_amount WHERE id = p_user_id;

  -- Record the bet securely
  INSERT INTO public.user_bets (user_id, prediction_id, amount_staked, potential_payout, status)
  VALUES (p_user_id, p_prediction_id, p_amount, (p_amount * v_odds)::INT, 'pending');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Function to resolve a prediction and dynamically process payouts for all bets
CREATE OR REPLACE FUNCTION public.resolve_prediction(p_prediction_id UUID, p_result TEXT)
RETURNS VOID AS $$
DECLARE
  v_bet RECORD;
BEGIN
  -- Ensure result is valid ('won', 'lost', or 'null' for refunds)
  IF p_result NOT IN ('won', 'lost', 'null') THEN
    RAISE EXCEPTION 'Invalid result type. Must be won, lost, or null.';
  END IF;

  -- Lock prediction row and update status
  UPDATE public.predictions 
  SET status = 'resolved', result = p_result 
  WHERE id = p_prediction_id AND status = 'open';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prediction is already resolved or does not exist';
  END IF;

  -- Iterate through pending bets to process payouts
  FOR v_bet IN SELECT * FROM public.user_bets WHERE prediction_id = p_prediction_id AND status = 'pending' FOR UPDATE LOOP
    IF p_result = 'won' THEN
      -- Payout to user's wallet
      UPDATE public.users SET virtual_currency_balance = virtual_currency_balance + v_bet.potential_payout WHERE id = v_bet.user_id;
      UPDATE public.user_bets SET status = 'won' WHERE id = v_bet.id;
    ELSIF p_result = 'lost' THEN
      -- House keeps the stake
      UPDATE public.user_bets SET status = 'lost' WHERE id = v_bet.id;
    ELSIF p_result = 'null' THEN
      -- Market cancelled, refund stake
      UPDATE public.users SET virtual_currency_balance = virtual_currency_balance + v_bet.amount_staked WHERE id = v_bet.user_id;
      UPDATE public.user_bets SET status = 'refunded' WHERE id = v_bet.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
