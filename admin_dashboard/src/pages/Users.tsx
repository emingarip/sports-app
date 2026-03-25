import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Users as UsersIcon, Search, ShieldAlert, Edit2, Loader2, Coins } from 'lucide-react';

interface UserData {
  id: string;
  username: string;
  email: string;
  avatar_url: string | null;
  k_coin_balance: number;
  reputation_score: number;
  created_at: string;
}

export default function Users() {
  const [users, setUsers] = useState<UserData[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  
  // Edit Modal State
  const [editingUser, setEditingUser] = useState<UserData | null>(null);
  const [newBalance, setNewBalance] = useState<number>(0);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchUsers();

    // Supabase Realtime for Users
    const channel = supabase
      .channel('users_page_metrics')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'users' },
        () => {
           fetchUsers();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const fetchUsers = async () => {
    try {
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setUsers(data || []);
    } catch (error) {
      console.error('Error fetching users:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredUsers = users.filter(
    (user) =>
      (user.username?.toLowerCase() || '').includes(searchTerm.toLowerCase()) ||
      (user.email?.toLowerCase() || '').includes(searchTerm.toLowerCase())
  );

  const handleEditBalance = async () => {
    if (!editingUser) return;
    setSaving(true);
    try {
      // Call the secure RPC function created by the architect
      const { error } = await supabase.rpc('admin_update_user_balance', {
        target_user_id: editingUser.id,
        new_balance: newBalance,
      });

      if (error) throw error;
      
      // Close modal and refresh will happen automatically via Realtime
      setEditingUser(null);
    } catch (error: any) {
      console.error('Error updating balance:', error);
      alert('Bakiye güncellenemedi: ' + error.message);
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64 text-muted-foreground">
        <Loader2 className="w-8 h-8 animate-spin" />
        <span className="ml-2">Kullanıcılar yükleniyor...</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Kullanıcı Yönetimi</h1>
          <p className="text-muted-foreground mt-1">
            Kayıtlı kullanıcıları görüntüleyin ve K-Coin bakiyelerini yönetin.
          </p>
        </div>
        
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <input
            type="text"
            placeholder="Kullanıcı adı veya E-posta..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-9 pr-4 py-2 border border-border rounded-md bg-background focus:outline-none focus:ring-2 focus:ring-primary"
          />
        </div>
      </div>

      <div className="border border-border bg-card rounded-xl shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="text-xs text-muted-foreground uppercase bg-muted/50 border-b border-border">
              <tr>
                <th className="px-6 py-4 font-medium">Kullanıcı</th>
                <th className="px-6 py-4 font-medium">İtibar Puanı</th>
                <th className="px-6 py-4 font-medium">K-Coin Bakiyesi</th>
                <th className="px-6 py-4 font-medium">Kayıt Tarihi</th>
                <th className="px-6 py-4 font-medium text-right">İşlemler</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filteredUsers.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-6 py-8 text-center text-muted-foreground">
                    Arama kriterlerine uygun kullanıcı bulunamadı.
                  </td>
                </tr>
              ) : (
                filteredUsers.map((user) => (
                  <tr key={user.id} className="hover:bg-muted/10 transition-colors">
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
                          {user.avatar_url ? (
                            <img src={user.avatar_url} alt="avatar" className="w-full h-full object-cover" />
                          ) : (
                            <UsersIcon className="w-5 h-5 text-primary" />
                          )}
                        </div>
                        <div>
                          <div className="font-semibold text-card-foreground">
                            {user.username || 'İsimsiz Oyuncu'}
                          </div>
                          <div className="text-xs text-muted-foreground">{user.email}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-secondary text-secondary-foreground">
                        <ShieldAlert className="w-3.5 h-3.5" />
                        {user.reputation_score || 0}
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="font-bold text-yellow-500 flex items-center gap-1.5">
                        <Coins className="w-4 h-4" />
                        {user.k_coin_balance?.toLocaleString('tr-TR') || 0}
                      </div>
                    </td>
                    <td className="px-6 py-4 text-muted-foreground">
                      {new Date(user.created_at).toLocaleDateString('tr-TR', {
                        day: 'numeric',
                        month: 'short',
                        year: 'numeric'
                      })}
                    </td>
                    <td className="px-6 py-4 text-right">
                      <button
                        onClick={() => {
                          setEditingUser(user);
                          setNewBalance(user.k_coin_balance || 0);
                        }}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-md hover:bg-muted text-muted-foreground transition-colors"
                        title="Bakiyeyi Düzenle"
                      >
                        <Edit2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Edit Balance Modal */}
      {editingUser && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-card w-full max-w-sm rounded-xl shadow-lg border border-border p-6 relative">
            <h3 className="text-lg font-bold text-card-foreground mb-4">
              Bakiye Düzenle: {editingUser.username}
            </h3>
            <div className="mb-5">
              <label className="block text-sm font-medium mb-1">Yeni K-Coin Bakiyesi</label>
              <input
                type="number"
                value={newBalance}
                onChange={(e) => setNewBalance(parseInt(e.target.value) || 0)}
                className="w-full border border-border bg-background rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary"
              />
            </div>
            <div className="flex items-center justify-end gap-3">
              <button
                onClick={() => setEditingUser(null)}
                className="px-4 py-2 rounded-md hover:bg-muted font-medium transition-colors"
                disabled={saving}
              >
                İptal
              </button>
              <button
                onClick={handleEditBalance}
                disabled={saving}
                className="px-4 py-2 rounded-md bg-primary text-primary-foreground font-medium hover:bg-primary/90 transition-colors flex items-center gap-2"
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
