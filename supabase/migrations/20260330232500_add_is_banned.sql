-- Migration: Add is_banned column to users and update chat RLS

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT false;

-- We need to prevent banned users from sending chat messages
DROP POLICY IF EXISTS "Authenticated users can insert chat messages." ON public.chat_messages;

CREATE POLICY "Authenticated users can insert chat messages." 
  ON public.chat_messages FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id 
    AND NOT EXISTS (
      SELECT 1 FROM public.users WHERE id = auth.uid() AND is_banned = true
    )
  );
