-- Canlı skor (AI Sport Agent) maçları ile bülten kayıtları arasındaki kimlik köprüsü.
-- Eşleme anahtarı resmi iddaa program kodudur; yerel köprü (scripts/bulletin_bridge.py)
-- doldurur. Ana ekran maç kartlarının oran/analiz gösterebilmesinin ön koşulu (ADR 8).

ALTER TABLE public.bulletin_matches
  ADD COLUMN IF NOT EXISTS agent_match_id TEXT;

CREATE INDEX IF NOT EXISTS idx_bulletin_matches_agent_match_id
  ON public.bulletin_matches (agent_match_id)
  WHERE agent_match_id IS NOT NULL;
