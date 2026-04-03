import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Search, Loader2, Fullscreen, X, User, MessageSquare } from 'lucide-react';
import SupportChatWindow from '../components/SupportChatWindow';

interface FeedbackData {
  id: string;
  user_id: string | null;
  feedback_type: string;
  message: string;
  screenshot_url: string | null;
  device_info: Record<string, unknown>;
  app_version: string | null;
  os_version: string | null;
  status: string;
  created_at: string;
  users?: {
    username: string;
    email: string;
  } | null;
}

export default function Feedbacks() {
  const [feedbacks, setFeedbacks] = useState<FeedbackData[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterStatus, setFilterStatus] = useState<string>('active');
  const [filterKind, setFilterKind] = useState<string>('all');
  
  // Modal states
  const [viewingImage, setViewingImage] = useState<string | null>(null);
  const [selectedChatUser, setSelectedChatUser] = useState<{id: string, name: string} | null>(null);

  useEffect(() => {
    fetchFeedbacks();

    const channel = supabase
      .channel('feedbacks_page_metrics')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'feedbacks' },
        () => {
           fetchFeedbacks();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const fetchFeedbacks = async () => {
    try {
      const { data, error } = await supabase
        .from('feedbacks')
        .select(`
          *,
          users (
            username,
            email
          )
        `)
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Error fetching feedbacks:', error);
        const { data: fallbackData, error: fallbackError } = await supabase
          .from('feedbacks')
          .select('*')
          .order('created_at', { ascending: false });
          
        if (fallbackError) throw fallbackError;
        setFeedbacks(fallbackData || []);
        return;
      }
      
      setFeedbacks(data || []);
    } catch (error) {
      console.error('Error fetching feedbacks:', error);
    } finally {
      setLoading(false);
    }
  };

  const updateStatus = async (id: string, newStatus: string) => {
    try {
      const { error } = await supabase
        .from('feedbacks')
        .update({ status: newStatus })
        .eq('id', id);

      if (error) throw error;
      setFeedbacks(feedbacks.map(f => f.id === id ? { ...f, status: newStatus } : f));
    } catch (error) {
      console.error('Error updating status:', error);
      alert('Status güncellenemedi.');
    }
  };

  const filteredFeedbacks = feedbacks
    .filter((feedback) => {
      const matchesSearch = 
        (feedback.message?.toLowerCase() || '').includes(searchTerm.toLowerCase()) ||
        (feedback.users?.username?.toLowerCase() || '').includes(searchTerm.toLowerCase());
        
      if (!matchesSearch) return false;
      
      let matchesStatus = true;
      if (filterStatus === 'active') {
        matchesStatus = feedback.status !== 'resolved';
      } else if (filterStatus !== 'all') {
        matchesStatus = feedback.status === filterStatus;
      }

      const matchesKind = filterKind === 'all' || feedback.feedback_type === filterKind;
      
      return matchesStatus && matchesKind;
    })
    .sort((a, b) => {
      // Sorting Logic:
      // 1. Open items (new, in_progress) come first.
      // 2. Open items are sorted by created_at ASC (oldest first).
      // 3. Resolved items are sorted by created_at DESC (newest first).
      
      const isOpen = (s: string) => s === 'new' || s === 'in_progress';
      const aOpen = isOpen(a.status);
      const bOpen = isOpen(b.status);

      if (aOpen && !bOpen) return -1;
      if (!aOpen && bOpen) return 1;

      const aTime = new Date(a.created_at).getTime();
      const bTime = new Date(b.created_at).getTime();

      if (aOpen && bOpen) {
        return aTime - bTime; // Oldest first
      }

      return bTime - aTime; // Newest resolved first
    });

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64 text-muted-foreground">
        <Loader2 className="w-8 h-8 animate-spin" />
        <span className="ml-2">Hata bildirimleri yükleniyor...</span>
      </div>
    );
  }

  const getStatusStyle = (status: string) => {
    switch(status) {
      case 'new': return 'bg-blue-500/10 text-blue-500';
      case 'in_progress': return 'bg-yellow-500/10 text-yellow-500';
      case 'resolved': return 'bg-green-500/10 text-green-500';
      default: return 'bg-muted text-muted-foreground';
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Hata ve Geri Bildirimler</h1>
          <p className="text-muted-foreground mt-1">
            Kullanıcılardan gelen sorunları görüntüleyin ve yanıtlayın.
          </p>
        </div>
        
        <div className="flex flex-col sm:flex-row gap-3 w-full sm:w-auto">
          <div className="flex gap-2">
            <select
              value={filterStatus}
              onChange={(e) => setFilterStatus(e.target.value)}
              className="px-3 py-2 border border-border rounded-md bg-background focus:outline-none focus:ring-2 focus:ring-primary text-sm font-medium min-w-[120px]"
            >
              <option value="active">Açık Talepler</option>
              <option value="all">Tümü</option>
              <option value="new">Yeni</option>
              <option value="in_progress">İnceleniyor</option>
              <option value="resolved">Çözüldü</option>
            </select>
            <select
              value={filterKind}
              onChange={(e) => setFilterKind(e.target.value)}
              className="px-3 py-2 border border-border rounded-md bg-background focus:outline-none focus:ring-2 focus:ring-primary text-sm font-medium min-w-[120px]"
            >
              <option value="all">Tüm Türler</option>
              <option value="bug">Bug</option>
              <option value="feature_request">Talep</option>
              <option value="other">Diğer</option>
            </select>
          </div>
          <div className="relative w-full sm:w-64">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <input
              type="text"
              placeholder="Ara..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-9 pr-4 py-2 border border-border rounded-md bg-background focus:outline-none focus:ring-2 focus:ring-primary text-sm"
            />
          </div>
        </div>
      </div>

      <div className="border border-border bg-card rounded-xl shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="text-xs text-muted-foreground uppercase bg-muted/50 border-b border-border">
              <tr>
                <th className="px-6 py-4 font-medium">Gönderen</th>
                <th className="px-6 py-4 font-medium">Mesaj</th>
                <th className="px-6 py-4 font-medium">Cihaz / OS</th>
                <th className="px-6 py-4 font-medium">Ekran Grnt.</th>
                <th className="px-6 py-4 font-medium">Sistem/Tarih</th>
                <th className="px-6 py-4 font-medium">Durum</th>
                <th className="px-6 py-4 font-medium">İşlem</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filteredFeedbacks.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-6 py-8 text-center text-muted-foreground">
                    Sorun bildirimi bulunamadı.
                  </td>
                </tr>
              ) : (
                filteredFeedbacks.map((f) => (
                  <tr key={f.id} className="hover:bg-muted/10 transition-colors">
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                          <User className="w-5 h-5 text-primary" />
                        </div>
                        <div>
                          <div className="font-semibold text-card-foreground">
                            {f.users?.username || (f.user_id ? 'Gizli Üye' : 'Anonim')}
                          </div>
                          <div className="text-xs text-muted-foreground">
                            {f.users?.email || f.user_id?.slice(0, 8) || ''}
                          </div>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                       <div className="max-w-[300px]">
                         <div className="font-semibold text-xs text-primary mb-1 uppercase tracking-wider">{f.feedback_type}</div>
                         <p className="text-sm truncate" title={f.message}>{f.message}</p>
                       </div>
                    </td>
                    <td className="px-6 py-4">
                       <div className="text-xs text-muted-foreground flex flex-col gap-1">
                          <span>App: <span className="text-foreground">{f.app_version || '?'}</span></span>
                          <span>OS: <span className="text-foreground">{f.os_version || '?'}</span></span>
                       </div>
                    </td>
                    <td className="px-6 py-4">
                       {f.screenshot_url ? (
                         <button 
                           type="button"
                           aria-label="Resmi büyüt"
                           className="w-16 h-10 bg-muted rounded border border-border cursor-pointer relative overflow-hidden group focus:outline-none focus:ring-2 focus:ring-primary"
                           onClick={() => setViewingImage(f.screenshot_url)}
                         >
                           <img src={f.screenshot_url} alt="screenshot" className="w-full h-full object-cover" />
                           <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                             <Fullscreen className="w-4 h-4 text-white" />
                           </div>
                         </button>
                       ) : (
                         <span className="text-xs text-muted-foreground">Yok</span>
                       )}
                    </td>
                    <td className="px-6 py-4 text-muted-foreground text-xs">
                      {new Date(f.created_at).toLocaleDateString('tr-TR', {
                        day: 'numeric',
                        month: 'short',
                        hour: '2-digit',
                        minute: '2-digit'
                      })}
                    </td>
                    <td className="px-6 py-4">
                      <select 
                        value={f.status}
                        onChange={(e) => updateStatus(f.id, e.target.value)}
                        className={`text-xs px-2.5 py-1.5 rounded-full font-medium border-0 focus:ring-2 focus:ring-primary/20 cursor-pointer ${getStatusStyle(f.status)}`}
                      >
                        <option value="new" className="bg-background text-foreground">Yeni</option>
                        <option value="in_progress" className="bg-background text-foreground">İnceleniyor</option>
                        <option value="resolved" className="bg-background text-foreground">Çözüldü</option>
                      </select>
                    </td>
                    <td className="px-6 py-4">
                       {f.user_id && (
                         <button 
                           onClick={() => setSelectedChatUser({ id: f.user_id!, name: f.users?.username || 'Kullanıcı' })}
                           className="flex items-center gap-1.5 text-primary hover:text-primary/80 transition-colors font-medium text-xs bg-primary/10 px-3 py-1.5 rounded-lg inline-flex"
                         >
                           <MessageSquare className="w-3.5 h-3.5" />
                           Yanıtla
                         </button>
                       )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Image Modal */}
      {viewingImage && (
        <div 
          className="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 p-4" 
          onClick={() => setViewingImage(null)}
          onKeyDown={(e) => e.key === 'Escape' && setViewingImage(null)}
          role="presentation"
        >
          <div className="relative max-w-4xl w-full max-h-[90vh] flex flex-col items-center">
            <button 
              type="button"
              className="absolute -top-12 right-0 bg-card p-2 rounded-full text-foreground hover:bg-muted transition-colors shadow-lg"
              onClick={() => setViewingImage(null)}
            >
              <X className="w-6 h-6" />
            </button>
            <div 
              className="relative" 
              onClick={(e) => e.stopPropagation()} 
              onKeyDown={(e) => e.stopPropagation()}
              role="presentation"
            >
              <img 
                src={viewingImage} 
                alt="Screenshot" 
                className="max-w-full max-h-[85vh] object-contain rounded-lg border border-border shadow-2xl bg-card"
              />
            </div>
          </div>
        </div>
      )}

      {/* Chat Modal */}
      {selectedChatUser && (
        <div 
          className="fixed inset-0 z-[110] flex items-center justify-center bg-black/60 p-4 backdrop-blur-[2px]" 
          onClick={() => setSelectedChatUser(null)}
          onKeyDown={(e) => e.key === 'Escape' && setSelectedChatUser(null)}
          role="presentation"
        >
          <div 
            className="w-full max-w-2xl" 
            onClick={e => e.stopPropagation()}
            onKeyDown={e => e.stopPropagation()}
            role="presentation"
          >
            <SupportChatWindow 
              targetUserId={selectedChatUser.id} 
              targetUserName={selectedChatUser.name}
              onClose={() => setSelectedChatUser(null)}
            />
          </div>
        </div>
      )}
    </div>
  );
}
