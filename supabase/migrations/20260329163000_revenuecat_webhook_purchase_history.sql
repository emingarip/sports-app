-- Table for recording Apple/Google IAP history via RevenueCat
CREATE TABLE IF NOT EXISTS public.k_coin_purchasing_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id VARCHAR(255) NOT NULL,
    coins_granted INTEGER NOT NULL,
    rc_transaction_id VARCHAR(255) UNIQUE,
    environment VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Users can view their own purchasing history
ALTER TABLE public.k_coin_purchasing_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own purchasing history"
ON public.k_coin_purchasing_history 
FOR SELECT 
USING (auth.uid() = user_id);

-- Admins can view all histories
CREATE POLICY "Admins can view purchasing history"
ON public.k_coin_purchasing_history 
FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM users 
    WHERE users.id = auth.uid() 
    AND users.is_admin = true
  )
);
