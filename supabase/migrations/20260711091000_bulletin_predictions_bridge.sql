-- Model prediction bridge table.
-- Mirrors sports_api match predictions (Dixon-Coles market probabilities +
-- value picks) next to the bulletin so the Flutter client reads everything
-- from Supabase. Written by the sync-predictions edge function (service role).

CREATE TABLE public.bulletin_predictions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  bulletin_match_id UUID UNIQUE NOT NULL REFERENCES public.bulletin_matches(id) ON DELETE CASCADE,
  sports_api_match_id UUID NOT NULL,
  model_version TEXT NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL,
  lambda_home NUMERIC,
  lambda_away NUMERIC,
  rho NUMERIC,
  -- market_code -> selection_key -> probability
  market_probs JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- [{market_code, selection_key, model_probability, odds_decimal, expected_value, kelly_stake}]
  value_picks JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_bulletin_predictions_api_match
  ON public.bulletin_predictions (sports_api_match_id);

ALTER TABLE public.bulletin_predictions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Bulletin predictions are viewable by everyone."
  ON public.bulletin_predictions FOR SELECT USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.bulletin_predictions;
