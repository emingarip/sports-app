-- Admin write policies.
--
-- The admin dashboard authorised itself with a client-side string test
-- (`email.includes('emin')` in Login.tsx), which any visitor could step over
-- from the browser console. That has been replaced with a users.is_admin
-- check - but a client-side check is never the real gate. This migration puts
-- the gate where it belongs: row level security.
--
-- Audited from admin_dashboard/src: the panel writes to nine tables. Only
-- app_settings had an is_admin-conditioned write policy; the rest either had
-- no write policy or no RLS at all.
--
-- Idempotent on purpose: parts of this may already be true in production
-- (migrations were applied out of band at times), so everything is written as
-- DROP-then-CREATE with IF EXISTS guards.

-- ---------------------------------------------------------------------------
-- 1. Shared predicate
-- ---------------------------------------------------------------------------
-- Every policy below repeated the same EXISTS subquery. One SECURITY DEFINER
-- function keeps them consistent and lets Postgres cache the plan. STABLE
-- rather than VOLATILE so it is evaluated once per statement.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT u.is_admin FROM public.users u WHERE u.id = auth.uid()),
    FALSE
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

COMMENT ON FUNCTION public.is_admin() IS
  'True when the calling user has users.is_admin. Single source for every '
  'admin-only RLS policy.';

-- ---------------------------------------------------------------------------
-- 2. Helper: admin-only writes, with the read rule stated per table
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  -- table_name, whether anon may read it
  target RECORD;
BEGIN
  FOR target IN
    SELECT * FROM (VALUES
      -- Read by the Flutter client, so the SELECT policy stays open.
      ('app_themes',             TRUE),
      ('global_announcements',   TRUE),
      ('store_products',         TRUE),
      ('active_mini_games',      TRUE),
      -- Bot content: read by the games frontend and the bot-swarm edge
      -- function (which uses the service role and bypasses RLS anyway).
      ('bot_personas',           TRUE),
      ('bot_follow_suggestions', TRUE),
      ('mackolik_slang_pool',    TRUE)
    ) AS t(table_name, public_read)
  LOOP
    -- Skip tables that do not exist in this environment rather than failing
    -- the whole migration.
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = target.table_name
    ) THEN
      CONTINUE;
    END IF;

    EXECUTE format(
      'ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', target.table_name
    );

    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      target.table_name || '_public_read', target.table_name
    );
    IF target.public_read THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT USING (true)',
        target.table_name || '_public_read', target.table_name
      );
    END IF;

    -- Writes: admins only. Without this the tables were either wide open
    -- (RLS off) or silently unwritable (RLS on, no policy) - both wrong.
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.%I',
      target.table_name || '_admin_write', target.table_name
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
      'USING (public.is_admin()) WITH CHECK (public.is_admin())',
      target.table_name || '_admin_write', target.table_name
    );
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. feedbacks: users write their own, admins read and resolve everything
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'feedbacks'
  ) THEN
    RETURN;
  END IF;

  ALTER TABLE public.feedbacks ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS feedbacks_own_read ON public.feedbacks;
  CREATE POLICY feedbacks_own_read ON public.feedbacks
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

  DROP POLICY IF EXISTS feedbacks_own_insert ON public.feedbacks;
  CREATE POLICY feedbacks_own_insert ON public.feedbacks
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

  -- Only an admin changes status / adds a reply.
  DROP POLICY IF EXISTS feedbacks_admin_update ON public.feedbacks;
  CREATE POLICY feedbacks_admin_update ON public.feedbacks
    FOR UPDATE TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

  DROP POLICY IF EXISTS feedbacks_admin_delete ON public.feedbacks;
  CREATE POLICY feedbacks_admin_delete ON public.feedbacks
    FOR DELETE TO authenticated
    USING (public.is_admin());
END $$;

-- ---------------------------------------------------------------------------
-- 4. users.is_admin must not be self-assignable
-- ---------------------------------------------------------------------------
-- Every policy above rests on this column. If a user can update their own row
-- freely they can promote themselves and the whole scheme collapses.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'is_admin'
  ) THEN
    EXECUTE 'REVOKE UPDATE (is_admin) ON public.users FROM anon, authenticated';
  END IF;
END $$;
