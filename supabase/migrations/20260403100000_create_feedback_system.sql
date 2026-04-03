-- Create feedback table
CREATE TABLE IF NOT EXISTS feedbacks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    feedback_type TEXT NOT NULL, -- 'bug', 'feature_request', 'other'
    message TEXT NOT NULL,
    screenshot_url TEXT,
    device_info JSONB,
    app_version TEXT,
    os_version TEXT,
    status TEXT DEFAULT 'new', -- 'new', 'in_progress', 'resolved'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for feedbacks
ALTER TABLE feedbacks ENABLE ROW LEVEL SECURITY;

-- Users can insert their own feedbacks
CREATE POLICY "Users can insert their own feedbacks"
    ON feedbacks FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can view their own feedbacks
CREATE POLICY "Users can view their own feedbacks"
    ON feedbacks FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- Admins can view all feedbacks
CREATE POLICY "Admins can view all feedbacks"
    ON feedbacks FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.is_admin = true));

-- Create storage bucket for feedback-screenshots
insert into storage.buckets (id, name, public)
values ('feedback-screenshots', 'feedback-screenshots', true)
on conflict (id) do nothing;

-- RLS for feedback-screenshots
CREATE POLICY "Users can upload their own screenshots"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'feedback-screenshots' AND auth.role() = 'authenticated');

CREATE POLICY "Anyone can view screenshots"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'feedback-screenshots');
