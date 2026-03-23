-- Knowledge Graph Migration: Event tracking and personalized interests
-- Contains user_events, user_interests, entity_relations and calculation functions

-- 1. Create user_events table
CREATE TABLE public.user_events (
    id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    event_type TEXT NOT NULL, -- e.g., 'match_viewed', 'match_favorited', 'prediction_placed'
    entity_type TEXT NOT NULL, -- e.g., 'team', 'league', 'match'
    entity_id TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Index for querying events by user
CREATE INDEX idx_user_events_user_id ON public.user_events(user_id);
-- Index for quick event type / entity filtering
CREATE INDEX idx_user_events_entity ON public.user_events(entity_type, entity_id);

-- 2. Create user_interests table (Materialized profile scores)
CREATE TABLE public.user_interests (
    id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    entity_type TEXT NOT NULL, 
    entity_id TEXT NOT NULL,
    interest_score FLOAT DEFAULT 0.0 NOT NULL,
    interaction_count INT DEFAULT 0 NOT NULL,
    last_interaction TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    -- Ensure one interest score row per user per entity
    UNIQUE(user_id, entity_type, entity_id)
);

CREATE INDEX idx_user_interests_user_scores ON public.user_interests(user_id, interest_score DESC);

-- 3. Create entity_relations table (Graph edges)
CREATE TABLE public.entity_relations (
    id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    entity_a_type TEXT NOT NULL,
    entity_a_id TEXT NOT NULL,
    entity_b_type TEXT NOT NULL,
    entity_b_id TEXT NOT NULL,
    relation_type TEXT NOT NULL, -- e.g., 'plays_in', 'rival', 'similar_league'
    strength FLOAT DEFAULT 1.0 NOT NULL,
    UNIQUE(entity_a_type, entity_a_id, entity_b_type, entity_b_id, relation_type)
);

-- Index for graph traversal
CREATE INDEX idx_entity_relations_a ON public.entity_relations(entity_a_type, entity_a_id);
CREATE INDEX idx_entity_relations_b ON public.entity_relations(entity_b_type, entity_b_id);


-- 4. Set up Row Level Security (RLS)
ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_relations ENABLE ROW LEVEL SECURITY;

-- Users can insert their own events but cannot modify/delete them (append-only log)
CREATE POLICY "Users can insert their own events"
    ON public.user_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read their own events"
    ON public.user_events FOR SELECT
    USING (auth.uid() = user_id);

-- Users can read their own interests, but backend functions modify them
CREATE POLICY "Users can read their own interests"
    ON public.user_interests FOR SELECT
    USING (auth.uid() = user_id);

-- Entity relations are read-only for all authenticated users
CREATE POLICY "Anyone can read entity relations"
    ON public.entity_relations FOR SELECT
    USING (auth.role() = 'authenticated');


-- 5. Function to recalculate user interests based on recent events
-- This can be called via trigger, cron, or manually from Edge Function
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
    -- Reset current scores to 0 to rebuild them (could also just decay, but full rebuild is safer for MVP)
    -- In a massive scale app, we would only apply delta updates. For MVP, we recount last 30 days.
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

-- 6. Trigger to automatically queue recalculation on new event (Simplistic approach for MVP)
-- In production with high traffic, batch processing via chron is better than per-row triggers.
CREATE OR REPLACE FUNCTION public.trigger_recalculate_interests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Recalculate asynchronously or locally. For simplicity in MVP, we just call it directly.
    -- To prevent transaction bottlenecks, ideally move this to pg_cron or edge function.
    PERFORM public.recalculate_user_interests(NEW.user_id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER async_update_interests
    AFTER INSERT ON public.user_events
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_recalculate_interests();


-- 7. Function to fetch personalized match scores based on interests and relations
-- Returns match IDs alongside their computed relevance score
CREATE OR REPLACE FUNCTION public.get_personalized_match_scores(
    p_user_id UUID,
    p_match_data JSONB -- Array of current active matches to score: [{"id": "m1", "home": "t1", "away": "t2", "league": "l1"}]
)
RETURNS TABLE (match_id TEXT, relevance_score FLOAT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_match JSONB;
    v_score FLOAT;
    v_home_interest FLOAT;
    v_away_interest FLOAT;
    v_league_interest FLOAT;
BEGIN
    FOR v_match IN SELECT * FROM jsonb_array_elements(p_match_data)
    LOOP
        v_score := 0.0;
        
        -- Get direct interest in Home Team
        SELECT COALESCE(MAX(interest_score), 0) INTO v_home_interest
        FROM public.user_interests 
        WHERE user_id = p_user_id AND entity_type = 'team' AND entity_id = v_match->>'home';
        
        -- Get direct interest in Away Team
        SELECT COALESCE(MAX(interest_score), 0) INTO v_away_interest
        FROM public.user_interests 
        WHERE user_id = p_user_id AND entity_type = 'team' AND entity_id = v_match->>'away';

        -- Get interest in League
        SELECT COALESCE(MAX(interest_score), 0) INTO v_league_interest
        FROM public.user_interests 
        WHERE user_id = p_user_id AND entity_type = 'league' AND entity_id = v_match->>'league';

        -- Base score comes from direct interests
        v_score := (v_home_interest * 1.5) + (v_away_interest * 1.5) + v_league_interest;

        -- [Future Enhancement]: Traverse entity_relations to find indirect matches 
        -- (e.g., user likes GS, match is FB vs BJK -> derived interest because rival)
        
        -- Default minor score just to not rank everything 0
        IF v_score = 0.0 THEN
            v_score := 0.1; 
        END IF;

        match_id := v_match->>'id';
        relevance_score := v_score;
        RETURN NEXT;
    END LOOP;
END;
$$;
