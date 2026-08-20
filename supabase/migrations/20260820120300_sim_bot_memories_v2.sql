-- ==========================================================================
-- simulation_engine v2 — cok dilli hafiza (bge-m3, 1024-dim)
-- ==========================================================================

-- 6. Hafıza v2 — çok dilli embedding
--
-- Eski bot_memories, Xenova/all-MiniLM-L6-v2 (384-dim) ile dolduruluyordu ve
-- bu model YALNIZCA İNGİLİZCE eğitimli. Türkçe tribün argosunu o uzaya gömüp
-- kosinüs benzerliği aramak anlamsız sonuç veriyordu. Ayrıca canlı sohbet
-- okuyor ama hiç yazmıyordu (yazma yolu yalnızca DM’deydi), yani tablo
-- pratikte boştu — diagnose.js bunu doğruladı: 0 satır.
--
-- Yeni tablo bge-m3 (1024-dim, çok dilli) kullanıyor. Boyut değiştiği için
-- geriye dönük taşıma yapılmıyor; eski satırlar farklı bir uzaya ait ve zaten
-- anlamsız.
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.bot_memories_v2 (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  interacted_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  match_id uuid,
  kind text NOT NULL DEFAULT 'chat'
    CHECK (kind IN ('dm', 'chat', 'match_digest')),
  content text NOT NULL,
  embedding vector(1024),
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_bot_memories_v2_bot
  ON public.bot_memories_v2 (bot_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bot_memories_v2_vec
  ON public.bot_memories_v2 USING hnsw (embedding vector_cosine_ops);

ALTER TABLE public.bot_memories_v2 ENABLE ROW LEVEL SECURITY;
-- Politika yok: yalnızca service role (motor) erişir. Son kullanıcının bot
-- hafızasını okuması için bir sebep yok.

-- Eşik 0.35; eski koddaki 0.1 ("Very low threshold to ensure matches")
-- pratikte alakasız her şeyi getiriyordu ve sahtelik üretiyordu.

NOTIFY pgrst, 'reload schema';
