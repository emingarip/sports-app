-- Admin RPCs for reading user_events and user_interests

-- Function to get user events for admin users
CREATE OR REPLACE FUNCTION public.admin_get_user_events(target_user_id UUID)
RETURNS SETOF public.user_events
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if calling user is an admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Access denied. Only administrators can view user events.';
    END IF;

    RETURN QUERY 
    SELECT * 
    FROM public.user_events 
    WHERE user_id = target_user_id 
    ORDER BY created_at DESC 
    LIMIT 50;
END;
$$;


-- Function to get user interests for admin users
CREATE OR REPLACE FUNCTION public.admin_get_user_interests(target_user_id UUID)
RETURNS SETOF public.user_interests
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if calling user is an admin
    IF NOT EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Access denied. Only administrators can view user interests.';
    END IF;

    RETURN QUERY 
    SELECT * 
    FROM public.user_interests 
    WHERE user_id = target_user_id 
    ORDER BY interest_score DESC;
END;
$$;
