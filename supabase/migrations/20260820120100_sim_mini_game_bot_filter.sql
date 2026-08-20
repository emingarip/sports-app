-- ==========================================================================
-- simulation_engine v2 — mini oyun odul sizintisi (botlar podyumdan cikarilir)
-- ==========================================================================

-- 4. Mini oyun ödül sızıntısı
--
-- atomic_finalize_mini_game skora göre ilk 3’e 100/70/50 K-Coin dağıtıyor ama
-- bot filtrelemiyor. Bot skorları 5 saniyede bir sahte olarak birikiyor
-- (Math.random()*5+1), yani insanlardan neredeyse kesin daha yüksek oluyor.
-- Sonuç: botlar podyumu doldurup GERÇEK K-Coin alıyor (ekonomiye enflasyon) ve
-- gerçek oyuncular ödülsüz kalıyor.
--
-- LEFT JOIN users u zaten mevcuttu; tek eksik WHERE koşuluydu.
-- Orphan log’lar (u NULL) korunur: NULL IS NOT TRUE -> TRUE.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION atomic_finalize_mini_game(
  p_game_id TEXT
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $finalize$
DECLARE
  v_check_rank_reward INTEGER;
  v_top_log RECORD;
  v_reward INTEGER;
  v_rank INTEGER := 1;
  v_winners jsonb := '[]'::jsonb;
  v_winner_obj jsonb;
BEGIN
  SELECT rank_reward INTO v_check_rank_reward
  FROM mini_game_logs
  WHERE game_id = p_game_id AND rank_reward IS NOT NULL
  LIMIT 1;

  IF v_check_rank_reward IS NOT NULL THEN
    RAISE EXCEPTION 'Game is already finalized.';
  END IF;

  FOR v_top_log IN (
    SELECT m.id, m.user_id, m.score, u.username
    FROM mini_game_logs m
    LEFT JOIN users u ON m.user_id = u.id
    WHERE m.game_id = p_game_id
      AND u.is_bot IS NOT TRUE   -- <<< botlar ödül sıralamasına girmez
    ORDER BY m.score DESC
    LIMIT 3
  ) LOOP
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
      UPDATE mini_game_logs
      SET rank_reward = v_reward, rank = v_rank
      WHERE id = v_top_log.id;

      PERFORM process_user_balance_transaction(v_top_log.user_id, v_reward, 'add');

      v_winner_obj := jsonb_build_object(
        'userId', v_top_log.user_id,
        'username', COALESCE(v_top_log.username, 'Top Sektirme'),
        'score', v_top_log.score,
        'reward', v_reward,
        'rank', v_rank
      );

      v_winners := v_winners || v_winner_obj;
    END IF;

    v_rank := v_rank + 1;
  END LOOP;

  RETURN v_winners;
END;
$finalize$;

-- ----------------------------------------------------------------------------
