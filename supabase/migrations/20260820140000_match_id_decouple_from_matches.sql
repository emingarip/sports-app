-- ============================================================================
-- Sohbet, tahmin ve analiz tablolarini eski `matches` tablosundan ayir.
--
-- SORUN
-- Uygulama maclari AI Sport Agent'tan okuyor (lib/providers/match_provider.dart:21
-- -> AiSportAgentMatchProvider) ve agent KENDI UUID'lerini uretiyor. Supabase'deki
-- `matches` tablosu ise Highlightly kaynakli, bambaska UUID'ler tasiyor
-- (provider_id = 'highlightly_*').
--
-- `chat_messages.match_id` hala `matches(id)`'ye FK ile bagliydi, dolayisiyla
-- uygulamadan sohbete yazmak HER SEFERINDE su hatayi veriyordu:
--
--   insert or update on table "chat_messages" violates foreign key constraint
--   "chat_messages_match_id_fkey" — Key is not present in table "matches"
--
-- Yani canli sohbet ozelligi uygulamada tamamen calismiyordu.
--
-- NEDEN FK'YI KALDIRIYORUZ
-- Projenin yonu zaten bu: agent kimligine gecen tum yeni ozellikler serbest
-- anahtar kullaniyor ve HICBIRINDE FK yok --
--   audio_rooms.match_id            TEXT  (20260324000000)
--   user_favorite_matches.match_id  TEXT  (trigger NEW.id::text ile karsilastiriyor)
--   notifications.external_match_id TEXT  (20260508132000)
--   bulletin_matches.agent_match_id TEXT  (20260711120000)
--
-- Geriye `matches(id)`'ye baglanan 4 tablo kalmisti; bunlarin ucu istemciden
-- yaziliyor ve ayni bombayi tasiyordu. `predictions` ve `match_insights` henuz
-- patlamamisti cunku o akislar daha az kullaniliyor.
--
-- Agent kimlikleri de UUID oldugu icin KOLON TIPI DEGISMIYOR; yalnizca kisit
-- kaldiriliyor. Veri tasinmiyor, mevcut satirlar aynen kaliyor.
--
-- KAYBEDILEN
-- ON DELETE CASCADE: Supabase'de bir mac silinince sohbeti otomatik silinmez.
-- Pratikte zaten islevsizdi — agent kimlikli odalarin `matches`'te karsiligi yok.
--
-- DOKUNULMAYAN
-- `notifications.match_id` FK'si KALIYOR: o satirlari `matches` uzerindeki
-- trigger uretiyor, yani kendi icinde tutarli.
-- ============================================================================

ALTER TABLE public.chat_messages
  DROP CONSTRAINT IF EXISTS chat_messages_match_id_fkey;

ALTER TABLE public.predictions
  DROP CONSTRAINT IF EXISTS predictions_match_id_fkey;

ALTER TABLE public.match_insights
  DROP CONSTRAINT IF EXISTS match_insights_match_id_fkey;

-- FK kalkinca match_id uzerinden filtreleme icin indeks daha da onemli.
CREATE INDEX IF NOT EXISTS idx_predictions_match ON public.predictions (match_id);
CREATE INDEX IF NOT EXISTS idx_match_insights_match ON public.match_insights (match_id);

NOTIFY pgrst, 'reload schema';
