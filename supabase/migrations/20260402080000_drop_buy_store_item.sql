-- Drop the legacy buy_store_item RPC
-- Purchase logic has been moved to the `buy-store-item` Edge Function
-- to ensure architectural consistency with the Gamification System API.
DROP FUNCTION IF EXISTS public.buy_store_item(UUID, VARCHAR);
