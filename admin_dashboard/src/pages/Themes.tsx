import { type ReactNode, useEffect, useMemo, useState } from 'react';
import { Archive, Loader2, Pencil, Plus, Sparkles } from 'lucide-react';

import { supabase } from '../lib/supabase';
import {
  THEME_ASSET_FIELDS,
  THEME_STATUSES,
  THEME_TOKEN_FIELDS,
  TYPOGRAPHY_PRESETS,
  compactObject,
  createEmptyThemeAssets,
  createEmptyThemeConfig,
  normalizeThemeAssets,
  normalizeThemeConfig,
  type ThemeAssetsForm,
  type ThemeConfigForm,
  type ThemeStatus,
} from '../lib/themeEditor';

type ThemeRecord = {
  id: string;
  theme_code: string;
  name: string;
  description: string;
  status: ThemeStatus;
  version: number;
  supported_modes: string[];
  light_config: ThemeConfigForm;
  dark_config: ThemeConfigForm;
  assets: ThemeAssetsForm;
  preview_light_url: string | null;
  preview_dark_url: string | null;
  is_active: boolean;
  updated_at: string;
};

const inputClassName =
  'w-full rounded-xl border border-border bg-background px-3 py-2 text-sm outline-none transition focus:border-primary';

const emptyForm = () => ({
  id: null as string | null,
  themeCode: '',
  name: '',
  description: '',
  status: 'draft' as ThemeStatus,
  version: 1,
  supportedModes: ['light', 'dark'],
  previewLightUrl: '',
  previewDarkUrl: '',
  isActive: true,
  lightConfig: createEmptyThemeConfig(),
  darkConfig: createEmptyThemeConfig(),
  assets: createEmptyThemeAssets(),
});

export default function Themes() {
  const [themes, setThemes] = useState<ThemeRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [form, setForm] = useState(emptyForm());

  useEffect(() => {
    void fetchThemes();

    const channel = supabase
      .channel('app_themes_changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'app_themes' }, () => {
        void fetchThemes();
      })
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, []);

  const activeCount = useMemo(
    () => themes.filter((theme) => theme.is_active && theme.status === 'published').length,
    [themes]
  );

  const fetchThemes = async () => {
    try {
      const { data, error } = await supabase
        .from('app_themes')
        .select('*')
        .order('updated_at', { ascending: false });

      if (error) throw error;

      const normalized = (data ?? []).map((theme): ThemeRecord => ({
        ...theme,
        description: theme.description ?? '',
        light_config: normalizeThemeConfig(theme.light_config),
        dark_config: normalizeThemeConfig(theme.dark_config),
        assets: normalizeThemeAssets(theme.assets),
      }));

      setThemes(normalized);
    } catch (error) {
      console.error('Error fetching themes:', error);
    } finally {
      setLoading(false);
    }
  };

  const resetForm = () => setForm(emptyForm());

  const openCreateModal = () => {
    resetForm();
    setIsModalOpen(true);
  };

  const openEditModal = (theme: ThemeRecord) => {
    setForm({
      id: theme.id,
      themeCode: theme.theme_code,
      name: theme.name,
      description: theme.description,
      status: theme.status,
      version: theme.version,
      supportedModes: theme.supported_modes,
      previewLightUrl: theme.preview_light_url ?? '',
      previewDarkUrl: theme.preview_dark_url ?? '',
      isActive: theme.is_active,
      lightConfig: normalizeThemeConfig(theme.light_config),
      darkConfig: normalizeThemeConfig(theme.dark_config),
      assets: normalizeThemeAssets(theme.assets),
    });
    setIsModalOpen(true);
  };

  const updateConfig = (mode: 'lightConfig' | 'darkConfig', key: string, value: string) => {
    setForm((current) => ({
      ...current,
      [mode]: {
        ...current[mode],
        [key]: value,
      },
    }));
  };

  const validateForm = () => {
    if (!form.themeCode.trim() || !form.name.trim()) {
      return 'Theme code and name are required.';
    }
    if (form.supportedModes.length === 0) {
      return 'Select at least one supported mode.';
    }
    if (form.status === 'published') {
      if (!form.lightConfig.primary_container || !form.darkConfig.primary_container) {
        return 'Published themes must define at least primary container colors for light and dark.';
      }
    }
    return null;
  };

  const handleSave = async () => {
    const validation = validateForm();
    if (validation) {
      alert(validation);
      return;
    }

    setSaving(true);
    try {
      const payload = {
        theme_code: form.themeCode.trim().toLowerCase().replace(/\s+/g, '_'),
        name: form.name.trim(),
        description: form.description.trim(),
        status: form.status,
        version: Number(form.version) || 1,
        supported_modes: form.supportedModes,
        preview_light_url: form.previewLightUrl.trim() || null,
        preview_dark_url: form.previewDarkUrl.trim() || null,
        is_active: form.isActive,
        light_config: compactObject(form.lightConfig),
        dark_config: compactObject(form.darkConfig),
        assets: compactObject(form.assets),
      };

      if (form.id) {
        const { error } = await supabase.from('app_themes').update(payload).eq('id', form.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('app_themes').insert(payload);
        if (error) throw error;
      }

      setIsModalOpen(false);
      resetForm();
    } catch (error) {
      console.error('Error saving theme:', error);
      alert(`Theme save failed: ${(error as Error).message}`);
    } finally {
      setSaving(false);
    }
  };

  const updateStatus = async (theme: ThemeRecord, status: ThemeStatus) => {
    const { error } = await supabase.from('app_themes').update({ status }).eq('id', theme.id);
    if (error) {
      alert(`Status update failed: ${error.message}`);
    }
  };

  if (loading) {
    return (
      <div className="flex h-64 items-center justify-center text-muted-foreground">
        <Loader2 className="mr-2 h-8 w-8 animate-spin" />
        Theme catalog is loading...
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Premium Themes</h1>
          <p className="mt-1 text-muted-foreground">
            Manage branded app themes, token palettes, typography presets, and publish state.
          </p>
        </div>
        <button
          onClick={openCreateModal}
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 font-medium text-primary-foreground transition-colors hover:bg-primary/90"
        >
          <Plus className="h-4 w-4" />
          New Theme
        </button>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl border border-border bg-card p-5">
          <p className="text-sm text-muted-foreground">Published + Active</p>
          <p className="mt-2 text-3xl font-bold">{activeCount}</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-5">
          <p className="text-sm text-muted-foreground">Draft Themes</p>
          <p className="mt-2 text-3xl font-bold">{themes.filter((theme) => theme.status === 'draft').length}</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-5">
          <p className="text-sm text-muted-foreground">Archived</p>
          <p className="mt-2 text-3xl font-bold">{themes.filter((theme) => theme.status === 'archived').length}</p>
        </div>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        {themes.map((theme) => {
          const heroStart = theme.light_config.hero_gradient_start || theme.light_config.primary_container || '#111827';
          const heroEnd = theme.light_config.hero_gradient_end || theme.light_config.accent || '#334155';
          return (
            <div key={theme.id} className="overflow-hidden rounded-3xl border border-border bg-card shadow-sm">
              <div
                className="relative h-40 border-b border-border"
                style={{ background: `linear-gradient(135deg, ${heroStart}, ${heroEnd})` }}
              >
                <div className="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent" />
                <div className="absolute inset-x-0 bottom-0 flex items-end justify-between p-5 text-white">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-[0.24em] opacity-80">{theme.theme_code}</p>
                    <h2 className="mt-1 text-2xl font-bold">{theme.name}</h2>
                  </div>
                  <div className="rounded-full bg-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-wider backdrop-blur">
                    {theme.status}
                  </div>
                </div>
              </div>
              <div className="space-y-4 p-5">
                <p className="text-sm text-muted-foreground">{theme.description || 'No description yet.'}</p>
                <div className="flex flex-wrap gap-2 text-xs">
                  <span className="rounded-full bg-secondary px-3 py-1 text-secondary-foreground">
                    v{theme.version}
                  </span>
                  <span className="rounded-full bg-secondary px-3 py-1 text-secondary-foreground">
                    {theme.supported_modes.join(' / ')}
                  </span>
                  <span className="rounded-full bg-secondary px-3 py-1 text-secondary-foreground">
                    {theme.is_active ? 'active' : 'inactive'}
                  </span>
                </div>
                <div className="grid grid-cols-4 gap-2">
                  {['primary_container', 'accent', 'nav_background', 'hero_gradient_start'].map((key) => (
                    <div key={key} className="space-y-2 rounded-2xl border border-border p-3">
                      <div
                        className="h-10 rounded-xl border border-black/10"
                        style={{ backgroundColor: theme.light_config[key] || '#E5E7EB' }}
                      />
                      <p className="text-[11px] text-muted-foreground">{key}</p>
                    </div>
                  ))}
                </div>
                <div className="flex flex-wrap gap-2">
                  <button
                    onClick={() => openEditModal(theme)}
                    className="inline-flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-sm font-medium hover:bg-muted"
                  >
                    <Pencil className="h-4 w-4" />
                    Edit
                  </button>
                  {theme.status !== 'published' && (
                    <button
                      onClick={() => void updateStatus(theme, 'published')}
                      className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
                    >
                      <Sparkles className="h-4 w-4" />
                      Publish
                    </button>
                  )}
                  {theme.status !== 'archived' && (
                    <button
                      onClick={() => void updateStatus(theme, 'archived')}
                      className="inline-flex items-center gap-2 rounded-lg border border-border px-3 py-2 text-sm font-medium hover:bg-muted"
                    >
                      <Archive className="h-4 w-4" />
                      Archive
                    </button>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
          <div className="max-h-[92vh] w-full max-w-7xl overflow-hidden rounded-3xl border border-border bg-card shadow-2xl">
            <div className="flex items-center justify-between border-b border-border px-6 py-4">
              <div>
                <h2 className="text-xl font-bold">{form.id ? 'Edit Theme' : 'Create Theme'}</h2>
                <p className="text-sm text-muted-foreground">Controlled theme editor for mobile team skins.</p>
              </div>
              <button onClick={() => setIsModalOpen(false)} className="rounded-lg border border-border px-3 py-2 text-sm hover:bg-muted">
                Close
              </button>
            </div>
            <div className="grid max-h-[calc(92vh-80px)] gap-0 overflow-y-auto xl:grid-cols-[1.2fr_1fr_1fr]">
              <div className="space-y-5 border-r border-border p-6">
                <div className="grid gap-4 md:grid-cols-2">
                  <Field label="Theme Code">
                    <input value={form.themeCode} onChange={(e) => setForm((current) => ({ ...current, themeCode: e.target.value }))} className={inputClassName} />
                  </Field>
                  <Field label="Theme Name">
                    <input value={form.name} onChange={(e) => setForm((current) => ({ ...current, name: e.target.value }))} className={inputClassName} />
                  </Field>
                </div>
                <Field label="Description">
                  <textarea value={form.description} onChange={(e) => setForm((current) => ({ ...current, description: e.target.value }))} rows={4} className={`${inputClassName} min-h-28 resize-y`} />
                </Field>
                <div className="grid gap-4 md:grid-cols-2">
                  <Field label="Status">
                    <select value={form.status} onChange={(e) => setForm((current) => ({ ...current, status: e.target.value as ThemeStatus }))} className={inputClassName}>
                      {THEME_STATUSES.map((status) => <option key={status} value={status}>{status}</option>)}
                    </select>
                  </Field>
                  <Field label="Version">
                    <input type="number" min={1} value={form.version} onChange={(e) => setForm((current) => ({ ...current, version: Number(e.target.value) || 1 }))} className={inputClassName} />
                  </Field>
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  <Field label="Preview Light URL">
                    <input value={form.previewLightUrl} onChange={(e) => setForm((current) => ({ ...current, previewLightUrl: e.target.value }))} className={inputClassName} />
                  </Field>
                  <Field label="Preview Dark URL">
                    <input value={form.previewDarkUrl} onChange={(e) => setForm((current) => ({ ...current, previewDarkUrl: e.target.value }))} className={inputClassName} />
                  </Field>
                </div>
                <div className="rounded-2xl border border-border p-4">
                  <p className="mb-3 text-sm font-medium">Supported Modes</p>
                  <div className="flex gap-3">
                    {['light', 'dark'].map((mode) => (
                      <label key={mode} className="inline-flex items-center gap-2 text-sm">
                        <input
                          type="checkbox"
                          checked={form.supportedModes.includes(mode)}
                          onChange={(e) =>
                            setForm((current) => ({
                              ...current,
                              supportedModes: e.target.checked
                                ? [...current.supportedModes, mode]
                                : current.supportedModes.filter((item) => item !== mode),
                            }))
                          }
                        />
                        {mode}
                      </label>
                    ))}
                  </div>
                  <label className="mt-4 inline-flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={form.isActive} onChange={(e) => setForm((current) => ({ ...current, isActive: e.target.checked }))} />
                    Theme is active
                  </label>
                </div>
                <div className="rounded-2xl border border-border p-4">
                  <h3 className="mb-4 text-sm font-semibold">Assets</h3>
                  <div className="space-y-3">
                    {THEME_ASSET_FIELDS.map((field) => (
                      <Field key={field.key} label={field.label}>
                        <input
                          value={form.assets[field.key as keyof ThemeAssetsForm]}
                          onChange={(e) =>
                            setForm((current) => ({
                              ...current,
                              assets: { ...current.assets, [field.key]: e.target.value },
                            }))
                          }
                          placeholder={field.placeholder}
                          className={inputClassName}
                        />
                      </Field>
                    ))}
                  </div>
                </div>
              </div>
              {(['lightConfig', 'darkConfig'] as const).map((mode) => (
                <div key={mode} className="space-y-4 border-r border-border p-6 last:border-r-0">
                  <div className="flex items-center justify-between">
                    <h3 className="text-lg font-semibold">{mode === 'lightConfig' ? 'Light Config' : 'Dark Config'}</h3>
                    <select
                      value={form[mode].typography_preset}
                      onChange={(e) => updateConfig(mode, 'typography_preset', e.target.value)}
                      className={`${inputClassName} w-40`}
                    >
                      {TYPOGRAPHY_PRESETS.map((preset) => <option key={preset} value={preset}>{preset}</option>)}
                    </select>
                  </div>
                  <div className="grid gap-3 md:grid-cols-2">
                    {THEME_TOKEN_FIELDS.map((field) => (
                      <Field key={`${mode}-${field.key}`} label={field.label}>
                        <input
                          value={form[mode][field.key]}
                          onChange={(e) => updateConfig(mode, field.key, e.target.value)}
                          placeholder={field.placeholder}
                          className={inputClassName}
                        />
                      </Field>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            <div className="flex items-center justify-end gap-3 border-t border-border px-6 py-4">
              <button onClick={() => setIsModalOpen(false)} className="rounded-lg border border-border px-4 py-2 text-sm font-medium hover:bg-muted">
                Cancel
              </button>
              <button onClick={() => void handleSave()} disabled={saving} className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-60">
                {saving && <Loader2 className="h-4 w-4 animate-spin" />}
                {saving ? 'Saving...' : 'Save Theme'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block space-y-1.5 text-sm">
      <span className="font-medium text-card-foreground">{label}</span>
      {children}
    </label>
  );
}
