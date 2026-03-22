-- Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL, -- 'GOAL', 'MATCH_START', 'HALF_TIME', 'SYSTEM'
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own notifications"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications (e.g., mark as read)"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own notifications"
  ON public.notifications FOR DELETE
  USING (auth.uid() = user_id);

-- Create a logical PostgreSQL Trigger Function for Real-time Notification Insertion
CREATE OR REPLACE FUNCTION public.process_match_events_for_notifications()
RETURNS TRIGGER AS $$
DECLARE
  home_team_name TEXT;
  away_team_name TEXT;
  notification_title TEXT;
  notification_message TEXT;
  notification_type TEXT;
  fav_record RECORD;
BEGIN
  -- We only proceed if this is an UPDATE and it's interesting
  IF TG_OP = 'UPDATE' THEN
    
    -- Detect Home Goal
    IF NEW.home_score > OLD.home_score THEN
      notification_type := 'GOAL';
      SELECT t.name INTO home_team_name FROM public.teams t WHERE t.id = NEW.home_team_id;
      SELECT t.name INTO away_team_name FROM public.teams t WHERE t.id = NEW.away_team_id;
      
      notification_title := '🚨 GOL! ' || home_team_name;
      notification_message := home_team_name || ' golü buldu! Skor: ' || NEW.home_score || ' - ' || NEW.away_score || ' (' || away_team_name || ')';
      
    -- Detect Away Goal
    ELSIF NEW.away_score > OLD.away_score THEN
      notification_type := 'GOAL';
      SELECT t.name INTO home_team_name FROM public.teams t WHERE t.id = NEW.home_team_id;
      SELECT t.name INTO away_team_name FROM public.teams t WHERE t.id = NEW.away_team_id;
      
      notification_title := '🚨 GOL! ' || away_team_name;
      notification_message := away_team_name || ' golü buldu! Skor: ' || NEW.home_score || ' - ' || NEW.away_score || ' (' || home_team_name || ')';
      
    -- Detect Match Start
    ELSIF OLD.status != 'LIVE' AND NEW.status = 'LIVE' THEN
      notification_type := 'MATCH_START';
      SELECT t.name INTO home_team_name FROM public.teams t WHERE t.id = NEW.home_team_id;
      SELECT t.name INTO away_team_name FROM public.teams t WHERE t.id = NEW.away_team_id;
      
      notification_title := '⚽ Maç Başladı!';
      notification_message := home_team_name || ' - ' || away_team_name || ' maçı an itibariyle başladı.';
      
    ELSE
      -- Nothing worth notifying
      RETURN NEW;
    END IF;

    -- If a notification was formulated, broadcast it to all users who Favorited this match
    FOR fav_record IN (SELECT user_id FROM public.user_favorite_matches WHERE match_id = NEW.id) LOOP
      INSERT INTO public.notifications (user_id, match_id, title, message, type)
      VALUES (fav_record.user_id, NEW.id, notification_title, notification_message, notification_type);
    END LOOP;
    
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Map the Trigger to the 'matches' table
DROP TRIGGER IF EXISTS trg_match_events_notifications ON public.matches;
CREATE TRIGGER trg_match_events_notifications
  AFTER UPDATE ON public.matches
  FOR EACH ROW
  EXECUTE FUNCTION public.process_match_events_for_notifications();

-- Turn ON real-time replication for notifications
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND schemaname = 'public'
    AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;
END $$;
