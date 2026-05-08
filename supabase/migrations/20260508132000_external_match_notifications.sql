ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS external_match_id TEXT,
  ADD COLUMN IF NOT EXISTS source TEXT,
  ADD COLUMN IF NOT EXISTS event_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_external_event
  ON public.notifications (user_id, source, external_match_id, event_key);
