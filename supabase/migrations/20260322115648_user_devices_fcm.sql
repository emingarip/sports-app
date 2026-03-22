/**
 * Table: user_devices
 * Purpose: Stores FCM tokens for push notifications per user and device.
 */
CREATE TABLE IF NOT EXISTS public.user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    fcm_token TEXT NOT NULL,
    platform TEXT, -- 'android', 'ios', 'web'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

-- RLS
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own device tokens" 
    ON public.user_devices FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own device tokens" 
    ON public.user_devices FOR UPDATE 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can read their own device tokens" 
    ON public.user_devices FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own device tokens" 
    ON public.user_devices FOR DELETE 
    USING (auth.uid() = user_id);

-- Optional trigger to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_user_devices_modtime()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_devices_modtime
BEFORE UPDATE ON public.user_devices
FOR EACH ROW
EXECUTE FUNCTION public.update_user_devices_modtime();
