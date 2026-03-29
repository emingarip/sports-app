-- Migration to add profile frames support
-- Adds 'active_frame' column to 'users'
-- Seeds initial frame products
-- Adds rpc 'equip_user_frame'

-- 1. Add active_frame column to users
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS active_frame VARCHAR(100);

-- 2. Seed initial frame products
INSERT INTO public.store_products (product_code, title, description, price, product_type) VALUES
('frame_gold_champion', 'Altın Şampiyon Çerçevesi', 'Profilinizin etrafında parlayan altın bir şampiyonluk tasarımı.', 500, 'lifetime'),
('frame_neon_fire', 'Neon Alev Çerçevesi', 'Kızıl ve mor neon ateş efektiyle profilinizi öne çıkarın.', 1000, 'lifetime'),
('frame_diamond_frozen', 'Buzul Elmas Çerçevesi', 'Buz gibi parlayan elmas kalitesinde premium bir profil eşyası.', 1500, 'lifetime')
ON CONFLICT (product_code) DO NOTHING;

-- 3. Procedure to equip a purchased frame
CREATE OR REPLACE FUNCTION public.equip_user_frame(p_user_id UUID, p_frame_code VARCHAR)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_has_entitlement BOOLEAN;
BEGIN
    -- Allow un-equipping by setting NULL
    IF p_frame_code IS NOT NULL THEN
        -- Verify ownership
        SELECT EXISTS (
            SELECT 1 FROM public.user_entitlements
            WHERE user_id = p_user_id
              AND product_code = p_frame_code
              AND is_active = true
              AND (expires_at IS NULL OR expires_at > NOW())
        ) INTO v_has_entitlement;

        IF NOT v_has_entitlement THEN
            RAISE EXCEPTION 'Bu çembere (frame) sahip değilsiniz. Lütfen mağazadan satın alın.';
        END IF;
    END IF;

    -- Equip or unequip
    UPDATE public.users
    SET active_frame = p_frame_code
    WHERE id = p_user_id;
END;
$$;
