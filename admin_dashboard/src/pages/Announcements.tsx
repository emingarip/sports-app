import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Megaphone, Plus, Edit2, Trash2, Loader2, CheckCircle2, AlertCircle, Info, ExternalLink } from 'lucide-react';

interface Announcement {
  id: string;
  title: string;
  message: string;
  type: 'info' | 'warning' | 'success' | 'event';
  action_url: string | null;
  is_active: boolean;
  created_at: string;
}

export default function Announcements() {
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  // Form State
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [type, setType] = useState<'info' | 'warning' | 'success' | 'event'>('info');
  const [actionUrl, setActionUrl] = useState('');
  const [isActive, setIsActive] = useState(true);

  useEffect(() => {
    fetchAnnouncements();

    const channel = supabase
      .channel('announcements_changes')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'global_announcements' },
        () => {
          fetchAnnouncements();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const fetchAnnouncements = async () => {
    try {
      const { data, error } = await supabase
        .from('global_announcements')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setAnnouncements(data || []);
    } catch (error) {
      console.error('Error fetching announcements:', error);
    } finally {
      setLoading(false);
    }
  };

  const resetForm = () => {
    setTitle('');
    setMessage('');
    setType('info');
    setActionUrl('');
    setIsActive(true);
    setEditingId(null);
  };

  const openNewModal = () => {
    resetForm();
    setIsModalOpen(true);
  };

  const openEditModal = (announcement: Announcement) => {
    setTitle(announcement.title);
    setMessage(announcement.message);
    setType(announcement.type);
    setActionUrl(announcement.action_url || '');
    setIsActive(announcement.is_active);
    setEditingId(announcement.id);
    setIsModalOpen(true);
  };

  const handleSave = async () => {
    if (!title.trim() || !message.trim()) {
      alert('Başlık ve mesaj alanları zorunludur.');
      return;
    }

    setSaving(true);
    try {
      const payload = {
        title,
        message,
        type,
        action_url: actionUrl.trim() || null,
        is_active: isActive
      };

      if (editingId) {
        const { error } = await supabase
          .from('global_announcements')
          .update(payload)
          .eq('id', editingId);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('global_announcements')
          .insert([payload]);
        if (error) throw error;
      }
      
      setIsModalOpen(false);
      resetForm();
    } catch (error: any) {
      console.error('Error saving announcement:', error);
      alert('Kaydedilirken hata oluştu: ' + error.message);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!window.confirm('Bu duyuruyu silmek istediğinize emin misiniz?')) return;
    
    try {
      const { error } = await supabase
        .from('global_announcements')
        .delete()
        .eq('id', id);
        
      if (error) throw error;
    } catch (error: any) {
      console.error('Error deleting announcement:', error);
      alert('Silinirken hata oluştu: ' + error.message);
    }
  };

  const toggleActiveStatus = async (id: string, currentStatus: boolean) => {
    try {
      const { error } = await supabase
        .from('global_announcements')
        .update({ is_active: !currentStatus })
        .eq('id', id);
        
      if (error) throw error;
    } catch (error: any) {
      console.error('Error toggling status:', error);
      alert('Durum güncellenirken hata oluştu: ' + error.message);
    }
  };

  const getTypeIcon = (type: string) => {
    switch(type) {
      case 'info': return <Info className="w-5 h-5 text-blue-500" />;
      case 'warning': return <AlertCircle className="w-5 h-5 text-yellow-500" />;
      case 'success': return <CheckCircle2 className="w-5 h-5 text-emerald-500" />;
      case 'event': return <Megaphone className="w-5 h-5 text-purple-500" />;
      default: return <Info className="w-5 h-5 text-blue-500" />;
    }
  };

  const getTypeLabel = (type: string) => {
    switch(type) {
      case 'info': return 'Bilgi';
      case 'warning': return 'Uyarı';
      case 'success': return 'Başarı';
      case 'event': return 'Etkinlik';
      default: return type;
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64 text-muted-foreground">
        <Loader2 className="w-8 h-8 animate-spin" />
        <span className="ml-2">Duyurular yükleniyor...</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Global Duyurular</h1>
          <p className="text-muted-foreground mt-1">
            Tüm kullanıcılara gösterilecek duyuruları, etkinlikleri ve uyarıları yönetin.
          </p>
        </div>
        
        <button
          onClick={openNewModal}
          className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 transition-colors font-medium shadow-sm"
        >
          <Plus className="w-4 h-4" />
          Yeni Duyuru
        </button>
      </div>

      <div className="grid gap-4 mt-6">
        {announcements.length === 0 ? (
          <div className="text-center py-12 border border-border rounded-xl bg-card">
            <Megaphone className="w-12 h-12 text-muted-foreground/50 mx-auto mb-3" />
            <h3 className="text-lg font-medium text-card-foreground">Henüz duyuru yok</h3>
            <p className="text-muted-foreground mt-1 text-sm">Sağ üstteki butonu kullanarak ilk duyurunuzu oluşturun.</p>
          </div>
        ) : (
          announcements.map((announcement) => (
            <div 
              key={announcement.id} 
              className={`p-5 rounded-xl border transition-all ${
                announcement.is_active ? 'border-primary/20 bg-card shadow-sm' : 'border-border bg-muted/30 opacity-75'
              }`}
            >
              <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
                <div className="flex items-start gap-4 flex-1">
                  <div className={`p-3 rounded-xl flex-shrink-0 ${
                    announcement.type === 'info' ? 'bg-blue-500/10' :
                    announcement.type === 'warning' ? 'bg-yellow-500/10' :
                    announcement.type === 'success' ? 'bg-emerald-500/10' :
                    'bg-purple-500/10'
                  }`}>
                    {getTypeIcon(announcement.type)}
                  </div>
                  <div>
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-semibold text-lg text-card-foreground line-clamp-1">{announcement.title}</h3>
                      <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-secondary text-secondary-foreground border border-border/50">
                        {getTypeLabel(announcement.type)}
                      </span>
                      {announcement.is_active ? (
                        <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-500 border border-emerald-500/20">
                          YAYINDA
                        </span>
                      ) : (
                        <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-muted text-muted-foreground border border-border">
                          PASİF
                        </span>
                      )}
                    </div>
                    <p className="text-sm text-muted-foreground/90 whitespace-pre-wrap">{announcement.message}</p>
                    
                    <div className="flex items-center gap-4 mt-3 text-xs text-muted-foreground font-medium">
                      <span>{new Date(announcement.created_at).toLocaleString('tr-TR')}</span>
                      {announcement.action_url && (
                        <a href={announcement.action_url} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-primary hover:underline">
                          <ExternalLink className="w-3 h-3" /> Eylem Linki Mevcut
                        </a>
                      )}
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-2 sm:ml-4 w-full sm:w-auto mt-4 sm:mt-0 pt-4 sm:pt-0 border-t sm:border-none border-border">
                  <button
                    onClick={() => toggleActiveStatus(announcement.id, announcement.is_active)}
                    className={`flex-1 sm:flex-none px-3 py-1.5 rounded-md text-sm font-medium transition-colors border ${
                      announcement.is_active 
                        ? 'border-yellow-500/20 bg-yellow-500/10 text-yellow-600 hover:bg-yellow-500/20' 
                        : 'border-emerald-500/20 bg-emerald-500/10 text-emerald-600 hover:bg-emerald-500/20'
                    }`}
                  >
                    {announcement.is_active ? 'Yayından Kaldır' : 'Yayınla'}
                  </button>
                  <button
                    onClick={() => openEditModal(announcement)}
                    className="p-2 border border-border rounded-md hover:bg-muted text-muted-foreground transition-colors"
                    title="Düzenle"
                  >
                    <Edit2 className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(announcement.id)}
                    className="p-2 border border-destructive/20 rounded-md hover:bg-destructive/10 text-destructive transition-colors"
                    title="Sil"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Create/Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-card w-full max-w-lg rounded-xl shadow-lg border border-border overflow-hidden">
            <div className="px-6 py-4 border-b border-border bg-muted/30">
              <h3 className="text-lg font-bold text-card-foreground">
                {editingId ? 'Duyuruyu Düzenle' : 'Yeni Duyuru Oluştur'}
              </h3>
            </div>
            <div className="p-6 space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1.5 text-card-foreground">Başlık <span className="text-destructive">*</span></label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Örn: Hafta Sonu Turnuvası Başlıyor!"
                  className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-1.5 text-card-foreground">Mesaj İçeriği <span className="text-destructive">*</span></label>
                <textarea
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder="Kullanıcılara iletilmek istenen duyuru metnini buraya yazın..."
                  rows={4}
                  className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary resize-y"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-1.5 text-card-foreground">Duyuru Tipi</label>
                  <select
                    value={type}
                    onChange={(e) => setType(e.target.value as any)}
                    className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                  >
                    <option value="info">Bilgi (Mavi)</option>
                    <option value="success">Başarı (Yeşil)</option>
                    <option value="warning">Uyarı (Sarı)</option>
                    <option value="event">Etkinlik (Açık Mor)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium mb-1.5 text-card-foreground">Durum</label>
                  <div className="flex items-center h-[38px]">
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input 
                        type="checkbox" 
                        className="sr-only peer" 
                        checked={isActive}
                        onChange={(e) => setIsActive(e.target.checked)}
                      />
                      <div className="w-11 h-6 bg-muted peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-primary rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
                      <span className="ml-3 text-sm font-medium text-muted-foreground">
                        {isActive ? 'Aktif (Yayında)' : 'Pasif (Taslak)'}
                      </span>
                    </label>
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium mb-1.5 text-card-foreground">Yönlendirme Linki (Opsiyonel)</label>
                <input
                  type="url"
                  value={actionUrl}
                  onChange={(e) => setActionUrl(e.target.value)}
                  placeholder="https://..."
                  className="w-full border border-border bg-background rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                />
                <p className="text-xs text-muted-foreground mt-1">
                  Kullanıcı duyuruya tıkladığında açılmasını istediğiniz bir link varsa buraya ekleyin.
                </p>
              </div>
            </div>
            <div className="px-6 py-4 border-t border-border bg-muted/30 flex items-center justify-end gap-3">
              <button
                onClick={() => setIsModalOpen(false)}
                className="px-4 py-2 text-sm rounded-md hover:bg-muted font-medium transition-colors"
                disabled={saving}
              >
                İptal
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="px-4 py-2 text-sm rounded-md bg-primary text-primary-foreground font-medium hover:bg-primary/90 transition-colors flex items-center gap-2"
              >
                {saving && <Loader2 className="w-4 h-4 animate-spin" />}
                {saving ? 'Kaydediliyor...' : 'Kaydet'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
