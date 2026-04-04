export type ThemeStatus = 'draft' | 'published' | 'archived';
export type ProductCategory = 'general' | 'app_theme';

export type ThemeConfigForm = Record<string, string>;

export type ThemeAssetsForm = {
  background_texture_url: string;
  emblem_url: string;
  badge_logo_url: string;
  support_fab_texture_url: string;
};

export const THEME_STATUSES: ThemeStatus[] = ['draft', 'published', 'archived'];
export const TYPOGRAPHY_PRESETS = ['system', 'sports', 'display'] as const;

export const THEME_TOKEN_FIELDS = [
  { key: 'background', label: 'Background', placeholder: '#F3F7FB' },
  { key: 'surface_container_low', label: 'Surface Low', placeholder: '#ECF1F6' },
  { key: 'surface_container', label: 'Surface', placeholder: '#E3E9EE' },
  { key: 'surface_container_high', label: 'Surface High', placeholder: '#DDE3E8' },
  { key: 'surface_container_highest', label: 'Surface Highest', placeholder: '#D7DEE3' },
  { key: 'surface_container_lowest', label: 'Surface Lowest', placeholder: '#FFFFFF' },
  { key: 'primary_container', label: 'Primary Container', placeholder: '#FFD709' },
  { key: 'on_primary_container', label: 'On Primary Container', placeholder: '#5B4B00' },
  { key: 'primary', label: 'Primary', placeholder: '#6C5A00' },
  { key: 'outline', label: 'Outline', placeholder: '#7E775F' },
  { key: 'secondary_container', label: 'Secondary Container', placeholder: '#E5E2E1' },
  { key: 'secondary', label: 'Secondary', placeholder: '#5C5B5B' },
  { key: 'error', label: 'Error', placeholder: '#B02500' },
  { key: 'error_container', label: 'Error Container', placeholder: '#FFDAD6' },
  { key: 'on_error_container', label: 'On Error Container', placeholder: '#93000A' },
  { key: 'text_high', label: 'Text High', placeholder: '#2A2F32' },
  { key: 'text_medium', label: 'Text Medium', placeholder: '#575C60' },
  { key: 'text_low', label: 'Text Low', placeholder: '#73777B' },
  { key: 'accent', label: 'Accent', placeholder: '#FACC15' },
  { key: 'success', label: 'Success', placeholder: '#16A34A' },
  { key: 'surface', label: 'Surface Base', placeholder: '#FFFFFF' },
  { key: 'surface_variant', label: 'Surface Variant', placeholder: '#E3E9EE' },
  { key: 'nav_background', label: 'Nav Background', placeholder: '#1E1E1E' },
  { key: 'nav_background_overlay', label: 'Nav Overlay', placeholder: '#1E1E1E' },
  { key: 'nav_selected', label: 'Nav Selected', placeholder: '#FACC15' },
  { key: 'nav_inactive', label: 'Nav Inactive', placeholder: '#F8FAFC' },
  { key: 'nav_accent', label: 'Nav Accent', placeholder: '#FACC15' },
  { key: 'nav_glow', label: 'Nav Glow', placeholder: '#FACC15' },
  { key: 'chip_background', label: 'Chip Background', placeholder: '#ECF1F6' },
  { key: 'chip_selected_background', label: 'Chip Selected BG', placeholder: '#FFD709' },
  { key: 'chip_selected_foreground', label: 'Chip Selected FG', placeholder: '#5B4B00' },
  { key: 'hero_gradient_start', label: 'Hero Gradient Start', placeholder: '#E11D48' },
  { key: 'hero_gradient_end', label: 'Hero Gradient End', placeholder: '#9333EA' },
  { key: 'hero_glow', label: 'Hero Glow', placeholder: '#E11D48' },
  { key: 'support_fab_start', label: 'Support FAB Start', placeholder: '#FFD700' },
  { key: 'support_fab_end', label: 'Support FAB End', placeholder: '#FACC15' },
  { key: 'support_fab_icon', label: 'Support FAB Icon', placeholder: '#5B4B00' },
  { key: 'live_accent', label: 'Live Accent', placeholder: '#DC2626' },
  { key: 'live_accent_muted', label: 'Live Accent Muted', placeholder: '#FCA5A5' },
  { key: 'badge_owned_background', label: 'Owned Badge BG', placeholder: '#DCFCE7' },
  { key: 'badge_owned_foreground', label: 'Owned Badge FG', placeholder: '#166534' },
  { key: 'overlay_scrim', label: 'Overlay Scrim', placeholder: '#20252B' },
  { key: 'card_shadow', label: 'Card Shadow', placeholder: '#111827' },
] as const;

export const THEME_ASSET_FIELDS = [
  { key: 'background_texture_url', label: 'Background Texture URL', placeholder: 'https://...' },
  { key: 'emblem_url', label: 'Emblem URL', placeholder: 'https://...' },
  { key: 'badge_logo_url', label: 'Badge Logo URL', placeholder: 'https://...' },
  { key: 'support_fab_texture_url', label: 'Support FAB Texture URL', placeholder: 'https://...' },
] as const;

export const createEmptyThemeConfig = (): ThemeConfigForm => ({
  background: '',
  surface_container_low: '',
  surface_container: '',
  surface_container_high: '',
  surface_container_highest: '',
  surface_container_lowest: '',
  primary_container: '',
  on_primary_container: '',
  primary: '',
  outline: '',
  secondary_container: '',
  secondary: '',
  error: '',
  error_container: '',
  on_error_container: '',
  text_high: '',
  text_medium: '',
  text_low: '',
  accent: '',
  success: '',
  surface: '',
  surface_variant: '',
  nav_background: '',
  nav_background_overlay: '',
  nav_selected: '',
  nav_inactive: '',
  nav_accent: '',
  nav_glow: '',
  chip_background: '',
  chip_selected_background: '',
  chip_selected_foreground: '',
  hero_gradient_start: '',
  hero_gradient_end: '',
  hero_glow: '',
  support_fab_start: '',
  support_fab_end: '',
  support_fab_icon: '',
  live_accent: '',
  live_accent_muted: '',
  badge_owned_background: '',
  badge_owned_foreground: '',
  overlay_scrim: '',
  card_shadow: '',
  typography_preset: 'system',
});

export const createEmptyThemeAssets = (): ThemeAssetsForm => ({
  background_texture_url: '',
  emblem_url: '',
  badge_logo_url: '',
  support_fab_texture_url: '',
});

export const normalizeThemeConfig = (config: Record<string, unknown> | null | undefined): ThemeConfigForm => {
  const base = createEmptyThemeConfig();
  if (!config) {
    return base;
  }

  for (const key of Object.keys(base)) {
    base[key] = typeof config[key] === 'string' ? (config[key] as string) : base[key];
  }

  return base;
};

export const normalizeThemeAssets = (assets: Record<string, unknown> | null | undefined): ThemeAssetsForm => {
  const base = createEmptyThemeAssets();
  if (!assets) {
    return base;
  }

  for (const key of Object.keys(base) as Array<keyof ThemeAssetsForm>) {
    base[key] = typeof assets[key] === 'string' ? (assets[key] as string) : '';
  }

  return base;
};

export const compactObject = (source: Record<string, string>) =>
  Object.fromEntries(
    Object.entries(source).filter(([, value]) => value.trim() !== '')
  );
