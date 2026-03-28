import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Bot, Plus, Search, Edit2, Play, Pause, Trash2 } from 'lucide-react';

interface BotPersona {
  id: string;
  user_id: string;
  team: string;
  persona_prompt: string;
  activity_level: string;
  created_at: string;
  users?: {
    username: string;
    avatar_url: string;
  };
}

export default function Bots() {
  const [bots, setBots] = useState<BotPersona[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  
  // Create Modal State
  const [swarmCount, setSwarmCount] = useState(10);
  const [team, setTeam] = useState('Galatasaray');
  const [personaPrompt, setPersonaPrompt] = useState('Sen ateşli bir taraftarsın. Takımına laf söyletmezsin.');
  const [isGenerating, setIsGenerating] = useState(false);

  // Edit State
  const [selectedBot, setSelectedBot] = useState<BotPersona | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    fetchBots();
  }, []);

  async function fetchBots() {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('bot_personas')
        .select(`
          *,
          users (
            username,
            avatar_url
          )
        `)
        .order('created_at', { ascending: false });

      if (error) throw error;
      setBots(data as BotPersona[]);
    } catch (error) {
      console.error('Error fetching bots:', error);
    } finally {
      setLoading(false);
    }
  }

  async function handleGenerateSwarm(e: React.FormEvent) {
    e.preventDefault();
    setIsGenerating(true);
    try {
      const { data, error } = await supabase.functions.invoke('generate-bot-swarm', {
        body: { count: swarmCount, team, persona_prompt: personaPrompt }
      });

      if (error) throw error;
      
      alert(`${data.created_count} bot başarıyla oluşturuldu!`);
      setShowCreateModal(false);
      fetchBots();
    } catch (error: any) {
      alert(`Hata: ${error.message}`);
    } finally {
      setIsGenerating(false);
    }
  }

  async function handleUpdatePersona(e: React.FormEvent) {
    e.preventDefault();
    if (!selectedBot) return;

    setIsSaving(true);
    try {
      const { error } = await supabase
        .from('bot_personas')
        .update({ persona_prompt: selectedBot.persona_prompt })
        .eq('id', selectedBot.id);

      if (error) throw error;
      
      setShowEditModal(false);
      setBots(bots.map(b => b.id === selectedBot.id ? selectedBot : b));
    } catch (error: any) {
      alert(`Güncelleme hatası: ${error.message}`);
    } finally {
      setIsSaving(false);
    }
  }

  async function handleDeleteBot(botId: string, userId: string) {
    if (!confirm('Bu botu ve içindeki kullanıcı hesabını silmek istediğinize emin misiniz?')) return;
    try {
      // Because bot_personas references users with ON DELETE CASCADE
      // However, we theoretically need to delete auth.users which we can't do globally from client
      // Instead, we just delete public.users if RLS allows, but RLS on users is id=auth.uid()
      // Simplest: Admin can't delete auth users directly easily without edge function.
      alert('Bot silme işlemi güvenlik gereği (Auth Users) şimdilik kısıtlanmıştır.');
    } catch (error) {
      console.error(error);
    }
  }

  return (
    <div className="space-y-6 text-foreground">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Simülasyon Botları (AI Swarm)</h1>
          <p className="text-muted-foreground mt-1">Platformdaki hayalet taraftar ordusunu yönetin.</p>
        </div>
        <button
          onClick={() => setShowCreateModal(true)}
          className="flex items-center gap-2 bg-primary text-primary-foreground hover:bg-primary/90 px-4 py-2 rounded-md font-medium transition-colors"
        >
          <Plus className="w-5 h-5" />
          Bot Ordusu Yarat
        </button>
      </div>

      <div className="bg-card text-card-foreground border border-border rounded-lg overflow-hidden flex flex-col h-[calc(100vh-12rem)]">
        <div className="p-4 border-b border-border flex gap-4">
          <div className="relative flex-1">
            <Search className="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input 
              type="text" 
              placeholder="Bot adı veya takım ara..." 
              className="w-full pl-10 pr-4 py-2 bg-muted border border-border rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 text-foreground"
            />
          </div>
        </div>

        <div className="flex-1 overflow-auto">
          {loading ? (
            <div className="flex items-center justify-center h-full text-muted-foreground">
              Botlar yükleniyor...
            </div>
          ) : bots.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
              <Bot className="w-16 h-16 mb-4 opacity-50" />
              <p>Henüz sistemde bot yok.</p>
            </div>
          ) : (
            <table className="w-full text-sm text-left">
              <thead className="bg-muted/50 text-muted-foreground sticky top-0 uppercase text-xs">
                <tr>
                  <th className="px-6 py-3 font-medium">Kullanıcı (Bot)</th>
                  <th className="px-6 py-3 font-medium">Takım</th>
                  <th className="px-6 py-3 font-medium max-w-xs">Karakter Yönergesi (Persona)</th>
                  <th className="px-6 py-3 font-medium">Aktivite</th>
                  <th className="px-6 py-3 text-right font-medium">İşlemler</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {bots.map((bot) => (
                  <tr key={bot.id} className="hover:bg-muted/30 transition-colors">
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <img 
                          src={bot.users?.avatar_url || `https://ui-avatars.com/api/?name=${bot.team}`} 
                          alt="Avatar" 
                          className="w-8 h-8 rounded-full border border-border" 
                        />
                        <div className="font-medium">{bot.users?.username || 'Bilinmiyor'}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-primary/10 text-primary">
                        {bot.team}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-muted-foreground max-w-xs truncate" title={bot.persona_prompt}>
                      {bot.persona_prompt}
                    </td>
                    <td className="px-6 py-4">
                       <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                         bot.activity_level === 'high' ? 'bg-green-500/10 text-green-500' : 'bg-yellow-500/10 text-yellow-500'
                       }`}>
                         {bot.activity_level.toUpperCase()}
                       </span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <button 
                        onClick={() => { setSelectedBot(bot); setShowEditModal(true); }}
                        className="text-muted-foreground hover:text-primary p-2 transition-colors mr-1"
                        title="Personayı Düzenle"
                      >
                        <Edit2 className="w-4 h-4" />
                      </button>
                      <button 
                        onClick={() => handleDeleteBot(bot.id, bot.user_id)}
                        className="text-muted-foreground hover:text-destructive p-2 transition-colors"
                        title="Sil"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* CREATE SWARM MODAL */}
      {showCreateModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <div className="bg-card w-full max-w-md rounded-xl border border-border shadow-2xl overflow-hidden p-6 animate-in fade-in zoom-in duration-200">
            <h3 className="text-xl font-bold mb-4">Yeni Bot Ordusu Yarat</h3>
            <form onSubmit={handleGenerateSwarm} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-muted-foreground mb-1">Kaç Adet Bot?</label>
                <input 
                  type="number" 
                  min="1" max="50"
                  required
                  value={swarmCount}
                  onChange={(e) => setSwarmCount(Number(e.target.value))}
                  className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary"
                />
                <p className="text-xs text-muted-foreground mt-1">Tek seferde en fazla 50 adet yaratılabilir.</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-muted-foreground mb-1">Hangi Takım?</label>
                <select 
                  value={team}
                  onChange={(e) => setTeam(e.target.value)}
                  className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary text-foreground"
                >
                  <option value="Galatasaray">Galatasaray</option>
                  <option value="Fenerbahçe">Fenerbahçe</option>
                  <option value="Beşiktaş">Beşiktaş</option>
                  <option value="Trabzonspor">Trabzonspor</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-muted-foreground mb-1">Persona Yönergesi</label>
                <textarea 
                  required
                  rows={4}
                  value={personaPrompt}
                  onChange={(e) => setPersonaPrompt(e.target.value)}
                  className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary text-sm"
                  placeholder="Botların davranış şeklini anlatın..."
                />
              </div>
              <div className="flex justify-end gap-3 pt-4">
                <button 
                  type="button" 
                  onClick={() => setShowCreateModal(false)}
                  className="px-4 py-2 hover:bg-muted text-foreground rounded-md transition-colors"
                >
                  İptal
                </button>
                <button 
                  type="submit" 
                  disabled={isGenerating}
                  className="px-4 py-2 bg-primary text-primary-foreground hover:bg-primary/90 rounded-md font-medium transition-colors disabled:opacity-50"
                >
                  {isGenerating ? 'Yaratılıyor...' : 'Yarat (Spawn)'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* EDIT MODAL */}
      {showEditModal && selectedBot && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <div className="bg-card w-full max-w-md rounded-xl border border-border shadow-2xl overflow-hidden p-6 animate-in fade-in zoom-in duration-200">
            <h3 className="text-xl font-bold mb-4">Personayı Düzenle</h3>
            <p className="text-sm text-muted-foreground mb-4">Bot: {selectedBot.users?.username}</p>
            <form onSubmit={handleUpdatePersona} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-muted-foreground mb-1">Güncel Persona Yönergesi</label>
                <textarea 
                  required
                  rows={4}
                  value={selectedBot.persona_prompt}
                  onChange={(e) => setSelectedBot({...selectedBot, persona_prompt: e.target.value})}
                  className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary text-sm"
                />
              </div>
              <div className="flex justify-end gap-3 pt-4">
                <button 
                  type="button" 
                  onClick={() => setShowEditModal(false)}
                  className="px-4 py-2 hover:bg-muted text-foreground rounded-md transition-colors"
                >
                  İptal
                </button>
                <button 
                  type="submit" 
                  disabled={isSaving}
                  className="px-4 py-2 bg-primary text-primary-foreground hover:bg-primary/90 rounded-md font-medium transition-colors disabled:opacity-50"
                >
                  {isSaving ? 'Kaydediliyor...' : 'Kaydet'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

    </div>
  );
}
