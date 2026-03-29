CREATE OR REPLACE FUNCTION delete_bot_user(target_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only allow deletion if the user is a bot (security check)
  IF EXISTS (SELECT 1 FROM public.users WHERE id = target_user_id AND is_bot = true) THEN
    DELETE FROM auth.users WHERE id = target_user_id;
  ELSE
    RAISE EXCEPTION 'This user is either not a bot or does not exist, deletion rejected.';
  END IF;
END;
$$;
