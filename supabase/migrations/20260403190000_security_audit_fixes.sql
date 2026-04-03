-- ============================================================
-- SECURITY AUDIT FIXES — Phase 1 (Critical Security)
-- ============================================================

-- ============================================================
-- FIX 1: Avatar Bucket — Restrict INSERT/UPDATE/DELETE to 
-- authenticated users writing to their own folder.
-- SELECT remains public (avatar viewing is expected).
-- ============================================================

-- Drop the overly permissive policies
DROP POLICY IF EXISTS "Public Insert" ON storage.objects;
DROP POLICY IF EXISTS "Public Update" ON storage.objects;
DROP POLICY IF EXISTS "Public Delete" ON storage.objects;

-- Authenticated users can upload to their own folder only
CREATE POLICY "Authenticated users can upload their own avatars"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Authenticated users can update their own avatars only
CREATE POLICY "Users can update their own avatars"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Authenticated users can delete their own avatars only
CREATE POLICY "Users can delete their own avatars"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);


-- ============================================================
-- FIX 2: audio_rooms DELETE policy — Hosts can delete their rooms
-- ============================================================

CREATE POLICY "Hosts can delete their rooms"
ON public.audio_rooms FOR DELETE
USING (auth.uid() = host_id);


-- ============================================================
-- FIX 3: Private rooms — Don't expose pin_code and filter
-- private rooms from public listing
-- ============================================================

-- Drop the old SELECT policy that shows everything
DROP POLICY IF EXISTS "Anyone can view active rooms" ON public.audio_rooms;

-- Public rooms: visible to everyone when active
CREATE POLICY "Anyone can view active public rooms"
ON public.audio_rooms FOR SELECT
USING (
  status = 'active'
  AND (is_private = false OR is_private IS NULL)
);

-- Private rooms: visible only to host
CREATE POLICY "Hosts can view their own private rooms"
ON public.audio_rooms FOR SELECT
USING (
  status = 'active'
  AND is_private = true
  AND auth.uid() = host_id
);

-- Allow admin to see all rooms
CREATE POLICY "Admins can view all rooms"
ON public.audio_rooms FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.is_admin = true)
);


-- ============================================================
-- FIX 4: Feedback screenshot bucket — private with open INSERT
-- Allows unauthenticated users to upload, but nobody can
-- browse/download without admin access via signed URLs.
-- ============================================================

-- Make the bucket private (no public CDN access)
UPDATE storage.buckets
SET public = false
WHERE id = 'feedback-screenshots';

-- Drop old policies
DROP POLICY IF EXISTS "Users can upload their own screenshots" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view screenshots" ON storage.objects;

-- Anyone can upload feedback screenshots (supports pre-login bug reports)
CREATE POLICY "Anyone can upload feedback screenshots"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'feedback-screenshots');

-- Only admins can view feedback screenshots (via signed URL)
CREATE POLICY "Admins can view feedback screenshots"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'feedback-screenshots'
  AND EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.is_admin = true)
);
