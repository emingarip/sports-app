CREATE TABLE IF NOT EXISTS public.audio_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_name TEXT NOT NULL UNIQUE,
  match_id TEXT,
  host_id UUID REFERENCES auth.users(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'ended')),
  metadata JSONB DEFAULT '{}'::jsonb
);

ALTER TABLE public.audio_rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active rooms" ON public.audio_rooms
  FOR SELECT USING (status = 'active');

CREATE POLICY "Authenticated users can create rooms" ON public.audio_rooms
  FOR INSERT WITH CHECK (auth.uid() = host_id);

CREATE POLICY "Hosts can update their rooms" ON public.audio_rooms
  FOR UPDATE USING (auth.uid() = host_id);
