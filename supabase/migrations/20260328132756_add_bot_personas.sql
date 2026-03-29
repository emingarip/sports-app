-- Add is_bot flag to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_bot boolean DEFAULT false;

-- Create bot_personas table
CREATE TABLE IF NOT EXISTS public.bot_personas (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    team text,
    persona_prompt text NOT NULL,
    activity_level text DEFAULT 'medium',
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.bot_personas ENABLE ROW LEVEL SECURITY;

-- Allow admins to manage bot_personas
CREATE POLICY "Admins can manage bot_personas" ON public.bot_personas
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE users.id = auth.uid() AND users.is_admin = true
        )
    );

-- Add to realtime publication if needed (not strictly necessary for bots, but good for dashboard)
ALTER PUBLICATION supabase_realtime ADD TABLE bot_personas;
