CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    notify_match_start BOOLEAN DEFAULT TRUE,
    notify_match_end BOOLEAN DEFAULT TRUE,
    notify_goals BOOLEAN DEFAULT TRUE,
    notify_predictions BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- RLS Policies
ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own preferences."
    ON public.user_notification_preferences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read their own preferences."
    ON public.user_notification_preferences FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own preferences."
    ON public.user_notification_preferences FOR UPDATE
    USING (auth.uid() = user_id);
