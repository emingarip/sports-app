import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Settings as SettingsIcon, Link as LinkIcon, Save, Loader2 } from 'lucide-react';

export default function Settings() {
  const [adLink, setAdLink] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [successMessage, setSuccessMessage] = useState('');

  useEffect(() => {
    fetchSettings();
  }, []);

  const fetchSettings = async () => {
    try {
      const { data, error } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'adsterra_direct_link')
        .single();

      if (error && error.code !== 'PGRST116') { // Ignore "Rows not found" if empty
        throw error;
      }
      
      if (data) {
        setAdLink(data.value);
      }
    } catch (error) {
      console.error('Ayarlar yüklenirken hata oluştu:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setSuccessMessage('');

    try {
      const { error } = await supabase
        .from('app_settings')
        .upsert({
          key: 'adsterra_direct_link',
          value: adLink,
        }, { onConflict: 'key' });

      if (error) throw error;
      setSuccessMessage('Reklam bağlantısı başarıyla güncellendi!');
      setTimeout(() => setSuccessMessage(''), 3000);
    } catch (error: any) {
      console.error('Ayarlar kaydedilirken hata oluştu:', error);
      alert('Kaydedilemedi: ' + (error.message || 'Bilinmeyen hata'));
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64 text-muted-foreground">
        <Loader2 className="w-8 h-8 animate-spin" />
        <span className="ml-2">Ayarlar yükleniyor...</span>
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-4xl">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Sistem Ayarları</h1>
        <p className="text-muted-foreground mt-1">
          Uygulama içi dinamik yapılandırmaları ve reklam bağlantılarını yönetin.
        </p>
      </div>

      <div className="grid gap-6">
        {/* Dynamic Ads Settings Card */}
        <div className="border border-border bg-card rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-border bg-muted/30">
            <h2 className="text-xl font-semibold flex items-center gap-2">
              <SettingsIcon className="w-5 h-5 text-primary" />
              Sponsor / Reklam Yönlendirmesi
            </h2>
            <p className="text-sm text-muted-foreground mt-1">
              "K-Coin Kazan" butonuna basıldığında açılacak hedef bağlantı. (Adsterra, Monetag vb. Direct Link)
            </p>
          </div>
          
          <div className="p-6">
            <form onSubmit={handleSave} className="space-y-4">
              <div className="space-y-2">
                <label htmlFor="adLink" className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
                  Direct Link / Kampanya URL
                </label>
                <div className="relative">
                  <LinkIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                  <input
                    id="adLink"
                    type="url"
                    required
                    placeholder="https://..."
                    value={adLink}
                    onChange={(e) => setAdLink(e.target.value)}
                    className="flex h-10 w-full rounded-md border border-input bg-background px-9 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                  />
                </div>
                <p className="text-[0.8rem] text-muted-foreground">
                  Bu URL, mobil ve web kullanıcılarında "Reklam İzle" butonuna tıklandığında gösterilecek sponsor sayfasını belirler.
                </p>
              </div>

              <div className="flex items-center gap-4 pt-2">
                <button
                  type="submit"
                  disabled={saving}
                  className="inline-flex items-center justify-center rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-6 py-2"
                >
                  {saving ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Kaydediliyor...
                    </>
                  ) : (
                    <>
                      <Save className="mr-2 h-4 w-4" />
                      Değişiklikleri Kaydet
                    </>
                  )}
                </button>
                {successMessage && (
                  <span className="text-sm font-medium text-green-500 flex items-center animate-in fade-in duration-300">
                    {successMessage}
                  </span>
                )}
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
