-- ==========================================================================
-- simulation_engine v2 — hafiza arama fonksiyonu (esik 0.35)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.match_bot_memories_v2(
  query_embedding vector(1024),
  p_bot_id uuid,
  match_threshold double precision DEFAULT 0.35,
  match_count integer DEFAULT 3,
  p_match_id uuid DEFAULT NULL
) RETURNS TABLE (id uuid, content text, similarity double precision)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $memsearch$
  SELECT m.id,
         m.content,
         1 - (m.embedding <=> query_embedding) AS similarity
  FROM public.bot_memories_v2 m
  WHERE m.bot_id = p_bot_id
    AND m.embedding IS NOT NULL
    AND (p_match_id IS NULL OR m.match_id = p_match_id OR m.kind = 'dm')
    AND 1 - (m.embedding <=> query_embedding) > match_threshold
  ORDER BY m.embedding <=> query_embedding
  LIMIT match_count;
$memsearch$;
