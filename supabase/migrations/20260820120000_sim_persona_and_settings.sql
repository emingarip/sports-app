-- ==========================================================================
-- simulation_engine v2 — persona kolonlari, indeksler, simulasyon ayarlari
-- ==========================================================================

-- ============================================================================
-- simulation_engine v2 — bot motoru yeniden tasarımının şema gereksinimleri
--
-- Tümü KATKISAL ve IDEMPOTENT. Canlı ortamda zaten var olan nesnelere
-- dokunmaz; `simulation_engine/diagnose.js` ile doğrulanmış durum:
--   - chat_messages.reply_to_id / _username / _text  -> canlıda VAR (eklenmez)
--   - bot_personas.traits / is_active                -> canlıda YOK (eklenir)
--   - bot_memories (384-dim, İngilizce embedding)    -> boş, yeni tablo kurulur
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. bot_personas: kişilik geçersiz kılma + tek botu susturma
--
-- Motor kişilik özelliklerini bot UUID’sinden deterministik türetiyor
-- (src/persona/traits.js), yani bu kolon boş kalsa da sistem çalışır. Kolonun
-- amacı belirli bir botu elle ayarlayabilmek ("şu bot çok saldırgan, kıs").
-- ----------------------------------------------------------------------------
ALTER TABLE public.bot_personas
  ADD COLUMN IF NOT EXISTS traits jsonb,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_bot_personas_team_active
  ON public.bot_personas (team) WHERE is_active;

-- ----------------------------------------------------------------------------
-- 2. chat_messages: eksik indeks
--
-- Motorun "son N mesaj" sorgusu ve istemcinin .stream() sıralaması bugün
-- indekssiz çalışıyor. Bot hacmi artınca ilk hissedilecek yer burası.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_chat_messages_match_created
  ON public.chat_messages (match_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- 3. Simülasyon ayarları — kill switch ve yoğunluk kontrolü
--
-- Motor bunları 30 saniyede bir okur (src/director/density.js), yani yeniden
-- başlatmadan kapatılabilir. Admin panelindeki Settings.tsx deseniyle
-- düzenlenebilir.
-- ----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value) VALUES
  ('sim_bots_enabled',         'true'),
  ('sim_dry_run',              'false'),
  ('sim_bot_human_ratio',      '1.5'),
  ('sim_max_msgs_per_min',     '6'),
  ('sim_max_viewers_for_bots', '40')
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
