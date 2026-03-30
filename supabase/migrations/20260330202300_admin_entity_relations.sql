-- Migration to add admin_get_user_entity_relations RPC
-- Allows fetching entity relations for entities a user interacts with

CREATE OR REPLACE FUNCTION public.admin_get_user_entity_relations(target_user_id uuid)
RETURNS setof public.entity_relations
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify the caller is an admin
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND is_admin = true) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT er.* FROM public.entity_relations er
  WHERE er.entity_a_id IN (
    SELECT entity_id FROM public.user_interests WHERE user_id = target_user_id
  ) OR er.entity_b_id IN (
    SELECT entity_id FROM public.user_interests WHERE user_id = target_user_id
  );
END;
$$;
