-- Fix the buy_store_item RPC to utilize the actual active k_coin_balance column instead of virtual_currency_balance.

DROP FUNCTION IF EXISTS public.buy_store_item(UUID, VARCHAR);

CREATE OR REPLACE FUNCTION public.buy_store_item(
    p_user_id UUID,
    p_product_code VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product RECORD;
    v_current_balance INTEGER;
    v_new_balance INTEGER;
    v_expires_at TIMESTAMPTZ;
    v_transaction_id UUID;
    v_entitlement_id UUID;
BEGIN
    -- 1. Ürünü bul ve kilitle
    SELECT * INTO v_product
    FROM public.store_products
    WHERE product_code = p_product_code AND is_active = true
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % not found or inactive', p_product_code;
    END IF;

    -- 2. Kullanıcının K-Coin bakiyesini kontrol et ve kilitle
    SELECT k_coin_balance INTO v_current_balance
    FROM public.users
    WHERE id = p_user_id
    FOR UPDATE;

    IF v_current_balance < v_product.price THEN
        RAISE EXCEPTION 'Insufficient K-Coin balance % for %', v_current_balance, v_product.price;
    END IF;

    -- 3. Parayı kes (k_coin_balance güncellenir)
    v_new_balance := v_current_balance - v_product.price;
    
    UPDATE public.users
    SET k_coin_balance = v_new_balance
    WHERE id = p_user_id;

    -- 4. İşlemi (Transaction Ledger) kaydet
    INSERT INTO public.k_coin_transactions (
        user_id,
        amount,
        transaction_type,
        reference_id,
        description
    ) VALUES (
        p_user_id,
        -v_product.price,
        'purchase',
        p_product_code,
        'Purchased store item: ' || v_product.title
    ) RETURNING id INTO v_transaction_id;

    -- 5. Eğer consumable değilse ürünü (Entitlement) kullanıcının hesabına tanımla
    IF v_product.product_type != 'consumable' THEN
        
        IF v_product.product_type = 'subscription' THEN
            v_expires_at := NOW() + (v_product.duration_days * INTERVAL '1 day');
        ELSE
            v_expires_at := NULL; -- Lifetime (sınırsız)
        END IF;

        -- Zaten varsa expire süresini uzat veya update et.
        INSERT INTO public.user_entitlements (
            user_id,
            product_code,
            expires_at,
            is_active
        )
        VALUES (
            p_user_id,
            p_product_code,
            v_expires_at,
            true
        )
        ON CONFLICT (user_id, product_code) 
        DO UPDATE SET 
            expires_at = CASE 
                WHEN user_entitlements.expires_at > NOW() THEN user_entitlements.expires_at + (EXCLUDED.expires_at - NOW())
                ELSE EXCLUDED.expires_at
            END,
            is_active = true
        RETURNING id INTO v_entitlement_id;

    END IF;

    -- 6. Başarılı Sonuç Döndür
    RETURN jsonb_build_object(
        'success', true,
        'new_balance', v_new_balance,
        'transaction_id', v_transaction_id,
        'entitlement_id', v_entitlement_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE; -- Transaction otomatik rollback olur
END;
$$;
