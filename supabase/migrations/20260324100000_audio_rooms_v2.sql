ALTER TABLE public.audio_rooms
ADD COLUMN IF NOT EXISTS listener_count INT DEFAULT 0;
