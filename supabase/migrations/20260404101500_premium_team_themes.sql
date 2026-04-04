ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS active_theme_code TEXT NOT NULL DEFAULT 'classic';

UPDATE public.users
SET active_theme_code = 'classic'
WHERE active_theme_code IS NULL;

ALTER TABLE public.store_products
ADD COLUMN IF NOT EXISTS product_category TEXT NOT NULL DEFAULT 'general';

ALTER TABLE public.store_products
ADD COLUMN IF NOT EXISTS theme_code TEXT;

UPDATE public.store_products
SET product_category = 'general'
WHERE product_category IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'store_products_product_category_check'
  ) THEN
    ALTER TABLE public.store_products
    ADD CONSTRAINT store_products_product_category_check
    CHECK (product_category IN ('general', 'app_theme'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.app_themes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  theme_code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  version INT NOT NULL DEFAULT 1 CHECK (version > 0),
  supported_modes TEXT[] NOT NULL DEFAULT ARRAY['light', 'dark'],
  light_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  dark_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  assets JSONB NOT NULL DEFAULT '{}'::jsonb,
  preview_light_url TEXT,
  preview_dark_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT app_themes_light_config_object CHECK (jsonb_typeof(light_config) = 'object'),
  CONSTRAINT app_themes_dark_config_object CHECK (jsonb_typeof(dark_config) = 'object'),
  CONSTRAINT app_themes_assets_object CHECK (jsonb_typeof(assets) = 'object'),
  CONSTRAINT app_themes_supported_modes_valid CHECK (
    cardinality(supported_modes) > 0
    AND supported_modes <@ ARRAY['light', 'dark']::TEXT[]
  )
);

CREATE INDEX IF NOT EXISTS idx_app_themes_status_active
ON public.app_themes (status, is_active);

CREATE INDEX IF NOT EXISTS idx_store_products_category_active
ON public.store_products (product_category, is_active);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'store_products_theme_code_fkey'
  ) THEN
    ALTER TABLE public.store_products
    ADD CONSTRAINT store_products_theme_code_fkey
    FOREIGN KEY (theme_code)
    REFERENCES public.app_themes(theme_code)
    ON DELETE RESTRICT;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'store_products_theme_category_requires_theme_code'
  ) THEN
    ALTER TABLE public.store_products
    ADD CONSTRAINT store_products_theme_category_requires_theme_code
    CHECK (
      (product_category = 'app_theme' AND theme_code IS NOT NULL AND product_type = 'lifetime')
      OR (product_category <> 'app_theme' AND theme_code IS NULL)
    );
  END IF;
END $$;

ALTER TABLE public.app_themes ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.app_themes TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.app_themes TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'store_products'
      AND policyname = 'Store products admin full access'
  ) THEN
    CREATE POLICY "Store products admin full access"
    ON public.store_products
    FOR ALL
    TO authenticated
    USING (
      EXISTS (
        SELECT 1
        FROM public.users
        WHERE id = auth.uid() AND is_admin = true
      )
    )
    WITH CHECK (
      EXISTS (
        SELECT 1
        FROM public.users
        WHERE id = auth.uid() AND is_admin = true
      )
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'app_themes'
      AND policyname = 'Public can view published app themes'
  ) THEN
    CREATE POLICY "Public can view published app themes"
    ON public.app_themes
    FOR SELECT
    TO public
    USING (is_active = true AND status = 'published');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'app_themes'
      AND policyname = 'App themes admin full access'
  ) THEN
    CREATE POLICY "App themes admin full access"
    ON public.app_themes
    FOR ALL
    TO authenticated
    USING (
      EXISTS (
        SELECT 1
        FROM public.users
        WHERE id = auth.uid() AND is_admin = true
      )
    )
    WITH CHECK (
      EXISTS (
        SELECT 1
        FROM public.users
        WHERE id = auth.uid() AND is_admin = true
      )
    );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_set_updated_at_app_themes ON public.app_themes;
CREATE TRIGGER tr_set_updated_at_app_themes
BEFORE UPDATE ON public.app_themes
FOR EACH ROW
EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE FUNCTION public.set_active_theme(p_theme_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_theme public.app_themes%ROWTYPE;
  v_has_access BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_theme_code IS NULL OR btrim(p_theme_code) = '' THEN
    RAISE EXCEPTION 'Theme code is required';
  END IF;

  IF p_theme_code = 'classic' THEN
    UPDATE public.users
    SET active_theme_code = 'classic'
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
      'success', true,
      'active_theme_code', 'classic',
      'theme_version', 1
    );
  END IF;

  SELECT *
  INTO v_theme
  FROM public.app_themes
  WHERE theme_code = p_theme_code
    AND is_active = true
    AND status = 'published';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Theme is unavailable';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_entitlements ue
    JOIN public.store_products sp
      ON sp.product_code = ue.product_code
    WHERE ue.user_id = v_user_id
      AND ue.is_active = true
      AND (ue.expires_at IS NULL OR ue.expires_at >= NOW())
      AND sp.product_category = 'app_theme'
      AND sp.theme_code = p_theme_code
      AND sp.is_active = true
  )
  INTO v_has_access;

  IF NOT v_has_access THEN
    RAISE EXCEPTION 'Theme not owned';
  END IF;

  UPDATE public.users
  SET active_theme_code = p_theme_code
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'active_theme_code', p_theme_code,
    'theme_version', v_theme.version
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_active_theme(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_active_theme(TEXT) TO authenticated;

INSERT INTO public.app_themes (
  theme_code,
  name,
  description,
  status,
  version,
  supported_modes,
  light_config,
  dark_config,
  assets,
  preview_light_url,
  preview_dark_url,
  is_active
)
VALUES (
  'galatasaray',
  'Galatasaray Legacy',
  'Premium red and gold team skin inspired by Galatasaray.',
  'published',
  1,
  ARRAY['light', 'dark'],
  '{
    "background": "#FFF7EE",
    "surface_container_low": "#FFF0D9",
    "surface_container": "#FFF6E6",
    "surface_container_high": "#FFE9B8",
    "surface_container_highest": "#FFDFA0",
    "surface_container_lowest": "#FFFFFF",
    "primary_container": "#C8102E",
    "on_primary_container": "#FFF9EF",
    "primary": "#8F1026",
    "outline": "#8E6C33",
    "secondary_container": "#FFE7A8",
    "secondary": "#7E1731",
    "error": "#B42318",
    "error_container": "#FEE4E2",
    "on_error_container": "#7A271A",
    "text_high": "#2F160C",
    "text_medium": "#61462A",
    "text_low": "#8A725C",
    "accent": "#FDB913",
    "success": "#15803D",
    "surface": "#FFFFFF",
    "surface_variant": "#FFF1D0",
    "nav_background": "#711122",
    "nav_background_overlay": "#8C1630",
    "nav_selected": "#FDB913",
    "nav_inactive": "#FFF2D2",
    "nav_accent": "#FDB913",
    "nav_glow": "#FDB913",
    "chip_background": "#FFECC3",
    "chip_selected_background": "#C8102E",
    "chip_selected_foreground": "#FFF9EF",
    "hero_gradient_start": "#A60F25",
    "hero_gradient_end": "#FDB913",
    "hero_glow": "#C8102E",
    "support_fab_start": "#FDB913",
    "support_fab_end": "#C8102E",
    "support_fab_icon": "#FFF8E7",
    "live_accent": "#C8102E",
    "live_accent_muted": "#FDB913",
    "badge_owned_background": "#FDE7B8",
    "badge_owned_foreground": "#6B2A00",
    "overlay_scrim": "#2D120F",
    "card_shadow": "#6B1122",
    "typography_preset": "sports"
  }'::jsonb,
  '{
    "background": "#14070A",
    "surface_container_low": "#1F0B10",
    "surface_container": "#291014",
    "surface_container_high": "#34161B",
    "surface_container_highest": "#401C23",
    "surface_container_lowest": "#0D0406",
    "primary_container": "#D31736",
    "on_primary_container": "#FFF9EF",
    "primary": "#FFD8A8",
    "outline": "#C89D4E",
    "secondary_container": "#44210A",
    "secondary": "#FDB913",
    "error": "#FFB4AB",
    "error_container": "#93000A",
    "on_error_container": "#FFDAD6",
    "text_high": "#FFF3E3",
    "text_medium": "#E9D7BA",
    "text_low": "#C4A98B",
    "accent": "#FDB913",
    "success": "#4ADE80",
    "surface": "#16080B",
    "surface_variant": "#34161B",
    "nav_background": "#0F0507",
    "nav_background_overlay": "#19080D",
    "nav_selected": "#FDB913",
    "nav_inactive": "#FDEDD0",
    "nav_accent": "#FDB913",
    "nav_glow": "#FDB913",
    "chip_background": "#34161B",
    "chip_selected_background": "#FDB913",
    "chip_selected_foreground": "#3A1800",
    "hero_gradient_start": "#D31736",
    "hero_gradient_end": "#FDB913",
    "hero_glow": "#D31736",
    "support_fab_start": "#FDB913",
    "support_fab_end": "#A60F25",
    "support_fab_icon": "#FFF8E7",
    "live_accent": "#FB7185",
    "live_accent_muted": "#FCD34D",
    "badge_owned_background": "#5B0E1E",
    "badge_owned_foreground": "#FFF3C2",
    "overlay_scrim": "#050203",
    "card_shadow": "#000000",
    "typography_preset": "sports"
  }'::jsonb,
  '{
    "emblem_url": null,
    "background_texture_url": null,
    "badge_logo_url": null,
    "support_fab_texture_url": null
  }'::jsonb,
  null,
  null,
  true
)
ON CONFLICT (theme_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  status = EXCLUDED.status,
  version = EXCLUDED.version,
  supported_modes = EXCLUDED.supported_modes,
  light_config = EXCLUDED.light_config,
  dark_config = EXCLUDED.dark_config,
  assets = EXCLUDED.assets,
  preview_light_url = EXCLUDED.preview_light_url,
  preview_dark_url = EXCLUDED.preview_dark_url,
  is_active = EXCLUDED.is_active;

INSERT INTO public.store_products (
  product_code,
  title,
  description,
  price,
  product_type,
  duration_days,
  is_active,
  product_category,
  theme_code
)
VALUES (
  'theme_galatasaray',
  'Galatasaray Theme Pack',
  'Unlock the premium Galatasaray red-and-gold app skin.',
  750,
  'lifetime',
  null,
  true,
  'app_theme',
  'galatasaray'
)
ON CONFLICT (product_code) DO UPDATE
SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  price = EXCLUDED.price,
  product_type = EXCLUDED.product_type,
  duration_days = EXCLUDED.duration_days,
  is_active = EXCLUDED.is_active,
  product_category = EXCLUDED.product_category,
  theme_code = EXCLUDED.theme_code;

NOTIFY pgrst, 'reload schema';
