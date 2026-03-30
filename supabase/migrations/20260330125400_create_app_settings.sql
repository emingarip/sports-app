CREATE TABLE IF NOT EXISTS public.app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Turn on RLS
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Allow public read access
CREATE POLICY "Allow public read access to app_settings"
ON public.app_settings FOR SELECT
TO public
USING (true);

-- Allow admin full access (requires `is_admin = true` from users table)
CREATE POLICY "Allow admin full access to app_settings"
ON public.app_settings FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  )
);

-- Create a generic trigger to auto-update 'updated_at'
CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_set_updated_at_app_settings
BEFORE UPDATE ON public.app_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_current_timestamp_updated_at();

-- Insert the default value for the adsterra/monetag link
INSERT INTO public.app_settings (key, value)
VALUES ('adsterra_direct_link', 'https://www.highcpmgate.com/example-adsterra-link')
ON CONFLICT (key) DO NOTHING;

-- Force PostgREST schema cache clear
NOTIFY pgrst, 'reload schema';
