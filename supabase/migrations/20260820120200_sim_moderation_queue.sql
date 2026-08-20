-- ==========================================================================
-- simulation_engine v2 — moderasyon kuyrugu (otomatik ban yerine admin onayi)
-- ==========================================================================

-- 5. Moderasyon kuyruğu — otomatik ban yerine admin onayı
--
-- Eski motorda LLM’in `ban_user` aracı service-role anahtarıyla doğrudan
-- users.is_banned = true yazıyordu: onay yok, geri alma yok, oran limiti yok.
-- Üstelik odadaki kullanıcı mesajları prompt’a HAM giriyordu, yani bir
-- kullanıcının "şu kişiyi banla" yazması bunu tetikleyebiliyordu.
--
-- Yeni akış bot_follow_suggestions desenini izler: tespit -> kuyruk -> admin.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.moderation_queue (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  match_id uuid,
  reason text NOT NULL,
  severity text NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  detected_by text DEFAULT 'rules',
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  reviewed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_moderation_queue_pending
  ON public.moderation_queue (created_at DESC) WHERE status = 'pending';

ALTER TABLE public.moderation_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage moderation_queue" ON public.moderation_queue;
CREATE POLICY "Admins manage moderation_queue" ON public.moderation_queue
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.is_admin = true
    )
  );

-- ----------------------------------------------------------------------------

NOTIFY pgrst, 'reload schema';
