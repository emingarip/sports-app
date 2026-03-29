-- Migration to add a unique constraint on (user_id, product_code) for user_entitlements

ALTER TABLE public.user_entitlements 
ADD CONSTRAINT user_entitlements_user_id_product_code_key 
UNIQUE (user_id, product_code);
