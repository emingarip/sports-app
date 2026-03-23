-- Migration to update Knowledge Graph scoring for onboarding events

-- Replace the recalculate_user_interests function to add onboarding_selected event type
CREATE OR REPLACE FUNCTION public.recalculate_user_interests(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- Needs to bypass RLS to upset/update interests
AS $$
DECLARE
    v_event RECORD;
    v_weight FLOAT;
    v_decay FLOAT;
    v_days_old INT;
BEGIN
    -- Reset current scores to 0 to rebuild them
    UPDATE public.user_interests 
    SET interest_score = 0 
    WHERE user_id = p_user_id;

    -- Process all events from the last 30 days for this user
    FOR v_event IN 
        SELECT entity_type, entity_id, event_type, created_at, count(*) as count
        FROM public.user_events
        WHERE user_id = p_user_id 
          AND created_at > (NOW() - INTERVAL '30 days')
        GROUP BY entity_type, entity_id, event_type, created_at
    LOOP
        -- 1. Determine base weight by event type
        CASE v_event.event_type
            WHEN 'onboarding_selected' THEN v_weight := 20.0; -- High initial baseline weight
            WHEN 'match_favorited' THEN v_weight := 10.0;
            WHEN 'prediction_placed' THEN v_weight := 8.0;
            WHEN 'chat_message_sent' THEN v_weight := 5.0;
            WHEN 'match_viewed' THEN v_weight := 3.0;
            ELSE v_weight := 1.0;
        END CASE;

        -- 2. Apply time decay (older events matter less)
        v_days_old := EXTRACT(DAY FROM (NOW() - v_event.created_at));
        
        IF v_days_old <= 1 THEN
            v_decay := 1.0;
        ELSIF v_days_old <= 7 THEN
            v_decay := 0.7;
        ELSIF v_days_old <= 14 THEN
            v_decay := 0.4;
        ELSE
            v_decay := 0.1;
        END IF;

        -- For onboarding, we can optionally lessen the decay or keep it the same.
        -- Keeping the same decay for now, but 20.0 * 0.1 will still leave a 2.0 trace 
        -- after 14 days, which is stronger than a normal view.

        -- 3. Upsert the calculated score
        INSERT INTO public.user_interests (user_id, entity_type, entity_id, interest_score, interaction_count, last_interaction)
        VALUES (
            p_user_id, 
            v_event.entity_type, 
            v_event.entity_id, 
            (v_weight * v_decay * v_event.count), 
            v_event.count,
            v_event.created_at
        )
        ON CONFLICT (user_id, entity_type, entity_id) 
        DO UPDATE SET 
            interest_score = user_interests.interest_score + EXCLUDED.interest_score,
            interaction_count = user_interests.interaction_count + EXCLUDED.interaction_count,
            last_interaction = GREATEST(user_interests.last_interaction, EXCLUDED.last_interaction);

    END LOOP;
END;
$$;
