-- Migration: Create K-Coin Store Infrastructure
-- Description: Adds tables for store products, user entitlements, and k-coin transactions with atomic purchase RPC.

-- 1. Create Product Type Enum
CREATE TYPE public.store_product_type AS ENUM ('subscription', 'lifetime', 'consumable');

-- 2. Create Store Products Table
CREATE TABLE public.store_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code VARCHAR(100) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    price INT NOT NULL DEFAULT 0 CHECK (price >= 0),
    product_type public.store_product_type NOT NULL,
    duration_days INT, -- Nullable, used only for subscription
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Create User Entitlements Table
CREATE TABLE public.user_entitlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_code VARCHAR(100) NOT NULL REFERENCES public.store_products(product_code) ON DELETE CASCADE,
    purchased_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ, -- Nullable, used only for subscription
    is_active BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT fk_entitlements_user FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

-- 4. Alter existing K-Coin Transactions Ledger Table (Wait, we can't CREATE if it exists)
-- Let's just add the description column if it doesn't exist, to support older schema.
ALTER TABLE public.k_coin_transactions ADD COLUMN IF NOT EXISTS description TEXT;

-- 5. Enable RLS
ALTER TABLE public.store_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.k_coin_transactions ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies
-- Store Products: Everyone can read active products.
CREATE POLICY "Store products are viewable by everyone" 
  ON public.store_products FOR SELECT USING (true);

-- User Entitlements: Users can only see their own active entitlements.
CREATE POLICY "Users can view own entitlements" 
  ON public.user_entitlements FOR SELECT USING (auth.uid() = user_id);

-- K-Coin Transactions: Users can view their own transaction history.
CREATE POLICY "Users can view own transactions" 
  ON public.k_coin_transactions FOR SELECT USING (auth.uid() = user_id);

-- 7. Atomic Purchase RPC Function
CREATE OR REPLACE FUNCTION public.buy_store_item(p_user_id UUID, p_product_code VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_price INT;
    v_product_type public.store_product_type;
    v_duration_days INT;
    v_current_balance INT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- 1. Get product details
    SELECT price, product_type, duration_days 
    INTO v_price, v_product_type, v_duration_days
    FROM public.store_products
    WHERE product_code = p_product_code AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found or not active';
    END IF;

    -- 2. Lock the user's row to prevent race conditions during balance check
    SELECT virtual_currency_balance INTO v_current_balance
    FROM public.users
    WHERE id = p_user_id
    FOR UPDATE;

    IF v_current_balance < v_price THEN
        RAISE EXCEPTION 'Insufficient K-Coin balance % for %', v_current_balance, v_price;
    END IF;

    -- 3. Deduct the price from the user's balance
    UPDATE public.users
    SET virtual_currency_balance = virtual_currency_balance - v_price
    WHERE id = p_user_id;

    -- 4. Record the transaction
    INSERT INTO public.k_coin_transactions (user_id, amount, transaction_type, reference_id, description)
    VALUES (p_user_id, -v_price, 'store_purchase', p_product_code, 'Purchased store item: ' || p_product_code);

    -- 5. Grant the entitlement (if not consumable)
    IF v_product_type != 'consumable' THEN
        IF v_product_type = 'subscription' AND v_duration_days IS NOT NULL THEN
            v_expires_at := now() + (v_duration_days || ' days')::INTERVAL;
        ELSE
            v_expires_at := NULL;
        END IF;

        -- Check if user already has an active subscription, if so extent it or just insert. 
        -- For simplicity, we just insert a new entitlement row. App will check MAX(expires_at).
        INSERT INTO public.user_entitlements (user_id, product_code, expires_at)
        VALUES (p_user_id, p_product_code, v_expires_at);
    END IF;

    RETURN TRUE;
END;
$$;

-- 8. Seed sample exact packages requested by user
INSERT INTO public.store_products (product_code, title, description, price, product_type, duration_days)
VALUES 
('ai_premium_monthly', 'Aylık Premium AI Paketi', 'Gelişmiş Maç Motoru Tahminlerini 30 gün boyunca sınırsız görüntüle.', 500, 'subscription', 30),
('ai_match_insight_single', 'Tek Maçlık Kâhin', 'Sadece bir maçın saklı analizini öğren.', 50, 'consumable', NULL);
