CREATE TABLE public.bot_follow_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.bot_follow_suggestions ENABLE ROW LEVEL SECURITY;

-- Admins can view suggestions
CREATE POLICY "Admins can view bot_follow_suggestions"
  ON public.bot_follow_suggestions
  FOR SELECT
  TO authenticated
  USING (
      EXISTS (
          SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.is_admin = true
      )
  );

-- Admins can update suggestions
CREATE POLICY "Admins can update bot_follow_suggestions"
  ON public.bot_follow_suggestions
  FOR UPDATE
  TO authenticated
  USING (
      EXISTS (
          SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.is_admin = true
      )
  );

-- Helper trigger function to automatically follow when approved
CREATE OR REPLACE FUNCTION handle_approved_bot_follow()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'approved' AND OLD.status = 'pending' THEN
        -- Insert into user_follows avoiding duplicate conflicts
        INSERT INTO public.user_follows (follower_id, followed_id)
        SELECT NEW.bot_id, NEW.target_user_id
        WHERE NOT EXISTS (
            SELECT 1 FROM public.user_follows 
            WHERE follower_id = NEW.bot_id AND followed_id = NEW.target_user_id
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_bot_follow_approved
    AFTER UPDATE ON public.bot_follow_suggestions
    FOR EACH ROW
    EXECUTE FUNCTION handle_approved_bot_follow();
