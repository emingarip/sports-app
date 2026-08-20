-- İddaa bulletin bridge tables.
-- Populated by the sync-bulletin edge function from the sports_api backend
-- (GET /api/v1/bulletin). Read-only for clients; writes happen with the
-- service role key which bypasses RLS.

CREATE TABLE public.bulletin_matches (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sports_api_match_id UUID UNIQUE NOT NULL,
  event_date DATE NOT NULL,
  kickoff_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'scheduled',
  competition_name TEXT,
  home_team TEXT NOT NULL,
  away_team TEXT NOT NULL,
  mbs INT,
  -- Optional link into the existing live-score table (public.matches.provider_id).
  live_match_provider_id TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_bulletin_matches_event_date ON public.bulletin_matches (event_date, kickoff_at);

CREATE TABLE public.bulletin_odds (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  bulletin_match_id UUID NOT NULL REFERENCES public.bulletin_matches(id) ON DELETE CASCADE,
  market_code TEXT NOT NULL,
  market_type TEXT NOT NULL,
  market_name_tr TEXT NOT NULL,
  line_value NUMERIC,
  selection_key TEXT NOT NULL,
  selection_label_tr TEXT,
  odds NUMERIC NOT NULL,
  opening_odds NUMERIC,
  movement_pct NUMERIC,
  is_dropping BOOLEAN NOT NULL DEFAULT FALSE,
  implied_prob NUMERIC,
  normalized_prob NUMERIC,
  suspended BOOLEAN NOT NULL DEFAULT FALSE,
  last_tick_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (bulletin_match_id, market_code, selection_key)
);

CREATE INDEX idx_bulletin_odds_match ON public.bulletin_odds (bulletin_match_id);

ALTER TABLE public.bulletin_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bulletin_odds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Bulletin matches are viewable by everyone."
  ON public.bulletin_matches FOR SELECT USING (true);

CREATE POLICY "Bulletin odds are viewable by everyone."
  ON public.bulletin_odds FOR SELECT USING (true);

-- Realtime updates for odds movement in the client.
ALTER PUBLICATION supabase_realtime ADD TABLE public.bulletin_matches;
ALTER PUBLICATION supabase_realtime ADD TABLE public.bulletin_odds;
