-- Migration: 20260328082441_atomic_mini_games.sql
-- Description: Adds atomic PL/pgSQL RPCs for mini-game participation and finalization

-- 1. Atomic Process Mini Game (Participation Reward)
CREATE OR REPLACE FUNCTION atomic_process_mini_game(
  p_game_id TEXT,
  p_room_id TEXT,
  p_user_id UUID,
  p_score INTEGER,
  p_reward INTEGER
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing_id UUID;
  v_existing_score INTEGER;
  v_result jsonb;
BEGIN
  -- 1. Check if user already played this specific game
  SELECT id, score INTO v_existing_id, v_existing_score 
  FROM mini_game_logs 
  WHERE game_id = p_game_id AND user_id = p_user_id 
  FOR UPDATE; -- Lock row if exists to prevent concurrent inserts

  IF v_existing_id IS NOT NULL THEN
    -- User already played
    IF p_score > v_existing_score THEN
      UPDATE mini_game_logs SET score = p_score WHERE id = v_existing_id;
      v_result := '{"status": "new_high_score", "rewardAmount": 0}'::jsonb;
    ELSE
      v_result := '{"status": "score_submitted", "rewardAmount": 0}'::jsonb;
    END IF;
  ELSE
    -- First time playing! 
    INSERT INTO mini_game_logs (game_id, room_id, user_id, score, reward)
    VALUES (p_game_id, p_room_id, p_user_id, p_score, p_reward);
    
    -- Give reward atomically
    PERFORM process_user_balance_transaction(p_user_id, p_reward, 'add');
    
    v_result := jsonb_build_object('status', 'success', 'rewardAmount', p_reward);
  END IF;

  RETURN v_result;
END;
$$;


-- 2. Atomic Finalize Mini Game (Leaderboard Rewards)
CREATE OR REPLACE FUNCTION atomic_finalize_mini_game(
  p_game_id TEXT
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_check_rank_reward INTEGER;
  v_top_log RECORD;
  v_reward INTEGER;
  v_rank INTEGER := 1;
  v_winners jsonb := '[]'::jsonb;
  v_winner_obj jsonb;
BEGIN
  -- Check if game is already finalized by looking for any rank_reward
  SELECT rank_reward INTO v_check_rank_reward 
  FROM mini_game_logs 
  WHERE game_id = p_game_id AND rank_reward IS NOT NULL 
  LIMIT 1;

  IF v_check_rank_reward IS NOT NULL THEN
    RAISE EXCEPTION 'Game is already finalized.';
  END IF;

  -- Distribute rewards
  FOR v_top_log IN (
    SELECT m.id, m.user_id, m.score, u.username
    FROM mini_game_logs m
    LEFT JOIN users u ON m.user_id = u.id
    WHERE m.game_id = p_game_id
    ORDER BY m.score DESC
    LIMIT 3
  ) LOOP
    -- Determine reward based on rank
    IF v_rank = 1 THEN
      v_reward := 100;
    ELSIF v_rank = 2 THEN
      v_reward := 70;
    ELSIF v_rank = 3 THEN
      v_reward := 50;
    ELSE
      v_reward := 0;
    END IF;

    IF v_reward > 0 THEN
      -- Log the assigned rank reward to prevent double execution
      UPDATE mini_game_logs 
      SET rank_reward = v_reward, rank = v_rank 
      WHERE id = v_top_log.id;

      -- Use the existing balance RPC to grant the coins atomically
      PERFORM process_user_balance_transaction(v_top_log.user_id, v_reward, 'add');

      -- Construct JSON object for the winner
      v_winner_obj := jsonb_build_object(
        'userId', v_top_log.user_id,
        'username', COALESCE(v_top_log.username, 'Top Sektirme'),
        'score', v_top_log.score,
        'reward', v_reward,
        'rank', v_rank
      );

      -- Append to winners array
      v_winners := v_winners || v_winner_obj;
    END IF;

    v_rank := v_rank + 1;
  END LOOP;

  RETURN v_winners;
END;
$$;
