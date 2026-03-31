import { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { Bot, Plus, Search, Edit2, Trash2, Check, X, Users, MessageSquare, Database } from 'lucide-react';

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

interface BotSuggestion {
  id: string;
  bot_id: string;
  target_user_id: string;
  reason: string;
  status: string;
  created_at: string;
  bot?: { username: string; avatar_url: string };
  target?: { username: string; avatar_url: string };
}

export default function Bots() {
  const location = useLocation();
  const [bots, setBots] = useState<BotPersona[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  
  const [activeTab, setActiveTab] = useState<'bots' | 'interactions' | 'slang'>('bots');
  const [suggestions, setSuggestions] = useState<BotSuggestion[]>([]);
  const [loadingSuggestions, setLoadingSuggestions] = useState(false);
  const [slangs, setSlangs] = useState<any[]>([]);
  const [loadingSlangs, setLoadingSlangs] = useState(false);
  const [teams, setTeams] = useState<string[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  
  // Create Modal State
  const [swarmCount, setSwarmCount] = useState(10);
  const [team, setTeam] = useState('');
  const [personaPrompt, setPersonaPrompt] = useState('Sen ateşli bir taraftarsın. Takımına laf söyletmezsin.');
  const [isGenerating, setIsGenerating] = useState(false);
  const [autoMode, setAutoMode] = useState(true);
  const [ollamaModel, setOllamaModel] = useState('orieg/gemma3-tools:12b');

  // Edit State
  const [selectedBot, setSelectedBot] = useState<BotPersona | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (activeTab === 'bots') fetchBots();
    if (activeTab === 'interactions') fetchSuggestions();
    if (activeTab === 'slang') fetchSlangs();
  }, [activeTab]);

  // Handle incoming routing state
  useEffect(() => {
    if (location.state?.preSelectedTeam) {
      setTeam(location.state.preSelectedTeam);
      setShowCreateModal(true);
      setActiveTab('bots');
      // optional: clear state so refresh doesn't keep opening modal
      window.history.replaceState({}, document.title)
    }
  }, [location.state]);

  useEffect(() => {
    async function fetchTeams() {
      try {
        const { data, error } = await supabase
          .from('matches')
          .select('home_team, away_team')
          .order('started_at', { ascending: false })
          .limit(200);
          
        if (data && !error) {
          const teamSet = new Set<string>();
          data.forEach(m => {
            if (m.home_team) teamSet.add(m.home_team);
            if (m.away_team) teamSet.add(m.away_team);
          });
          const uniqueTeams = Array.from(teamSet).sort();
          setTeams(uniqueTeams);
          if (uniqueTeams.length > 0 && !team && !location.state?.preSelectedTeam) {
            setTeam(uniqueTeams[0]);
          }
        }
      } catch (e) {
        console.error('Error fetching teams:', e);
      }
    }
    fetchTeams();
  }, []);

  async function fetchSuggestions() {
    try {
      setLoadingSuggestions(true);
      const { data, error } = await supabase
        .from('bot_follow_suggestions')
        .select(`
          *,
          bot:users!bot_id(username, avatar_url),
          target:users!target_user_id(username, avatar_url)
        `)
        .eq('status', 'pending')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setSuggestions(data as any[]);
    } catch (error) {
      console.error('Error fetching suggestions:', error);
    } finally {
      setLoadingSuggestions(false);
    }
  }

  async function handleSuggestionAction(id: string, newStatus: 'approved' | 'rejected') {
    try {
      const { error } = await supabase
        .from('bot_follow_suggestions')
        .update({ status: newStatus })
        .eq('id', id);
      if (error) throw error;
      setSuggestions(s => s.filter(x => x.id !== id));
    } catch (err: any) {
      alert(`Hata: ${err.message}`);
    }
  }

  async function fetchSlangs() {
    try {
      setLoadingSlangs(true);
      const { data, error } = await supabase
        .from('mackolik_slang_pool')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(600);

      if (error) throw error;
      setSlangs(data as any[]);
    } catch (error) {
      console.error('Error fetching slangs:', error);
    } finally {
      setLoadingSlangs(false);
    }
  }

  async function handleDeleteSlang(id: string) {
    if (!confirm('Bu yorumu havuzdan silmek istediğinize emin misiniz?')) return;
    try {
      const { error } = await supabase
        .from('mackolik_slang_pool')
        .delete()
        .eq('id', id);
      if (error) throw error;
      setSlangs(s => s.filter(x => x.id !== id));
    } catch (err: any) {
      alert(`Hata: ${err.message}`);
    }
  }

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
      if (autoMode) {
        // AI Otomatik Üretim Modu (Local Ollama üzerinden)
        const prompt = `Türkiye Süper Lig veya 1. Lig takımlarından rastgele seçilmiş ${swarmCount} adet farklı futbol taraftarı fiktif "bot" karakteri üret. 
Her birinin farklı yaşı (15 - 65), cinsiyeti, memleketi, mesleği ve favori takımı (Örn: Galatasaray, Fenerbahçe, Beşiktaş, Trabzonspor, Göztepe, vs.) olsun.
"persona_prompt" alanına bu demografik özelliklerini ve karakterini (örn: 22 yaşında İzmirli üniversiteli. Holigan ve bol argolu konuşur vs.) Türkçe olarak detaylandır.
LÜTFEN BANA SADECE GEÇERLİ BİR JSON ARRAY DÖN. Hiçbir açıklama metni veya markdown markdown quote (json) ekleme. Sadece köşeli parantez ile başlayan array: [{"team": "...", "persona_prompt": "..."}]`;

        const response = await fetch("http://localhost:11434/api/generate", {
           method: "POST",
           headers: { "Content-Type": "application/json" },
           body: JSON.stringify({
             model: ollamaModel,
             prompt,
             stream: false
           })
        });
        
        const data = await response.json();
        
        if (data.error) {
           throw new Error(`Ollama Hatası: ${data.error}`);
        }
        
        if (!data.response) {
           throw new Error("Ollama'dan boş (undefined) yanıt döndü.");
        }

        let text = data.response.trim();
        // Temizlik: Markdown bloklarını sil
        text = text.replace(/```json/g, '').replace(/```/g, '').trim();
        let generatedBots = [];
        try {
           generatedBots = JSON.parse(text);
        } catch(err) {
           throw new Error(`Ollama geçersiz bir JSON döndürdü. Lütfen tekrar deneyin. Gelen yanıt: ${text.substring(0,50)}...`);
        }

        let createdCount = 0;
        for (const b of generatedBots) {
          if (!b.team || !b.persona_prompt) continue;
          const { data: resData, error: err } = await supabase.functions.invoke('generate-bot-swarm', {
            body: { count: 1, team: b.team, persona_prompt: b.persona_prompt }
          });
          if (!err && resData?.created_count) {
             createdCount += resData.created_count;
          }
        }
        alert(`${createdCount} benzersiz bot yapay zeka tarafından tasarlandı ve oluşturuldu!`);
      } else {
        // Klasik Manuel Mod
        const { data, error } = await supabase.functions.invoke('generate-bot-swarm', {
          body: { count: swarmCount, team, persona_prompt: personaPrompt }
        });
        if (error) throw error;
        alert(`${data.created_count} bot başarıyla oluşturuldu!`);
      }
      
      setShowCreateModal(false);
      fetchBots();
    } catch (error: any) {
      alert(`Hata: ${error.message} (Yapay zeka üretimi için localhost:11434 Ollama'nın açık olduğuna emin olun)`);
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

  async function handleDeleteBot(_botId: string, _userId: string) {
    if (!confirm('Bu bot simülasyon motorundan ve sistemden (Auth dahil) kalıcı olarak silinecek, onaylıyor musunuz?')) return;
    try {
      // Call the secure RPC to delete the auth.users record (which cascades to users and bot_personas)
      const { error } = await supabase.rpc('delete_bot_user', {
        target_user_id: _userId
      });
      if (error) throw error;
      setBots(bots.filter(b => b.id !== _botId));
    } catch (error: any) {
      alert(`Bot silme işlemi başarısız: ${error.message}`);
    }
  }

  const filteredBots = bots.filter(b => 
    b.team.toLowerCase().includes(searchTerm.toLowerCase()) || 
    (b.users?.username || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
    b.persona_prompt.toLowerCase().includes(searchTerm.toLowerCase())
  );

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
        <div className="flex border-b border-border">
          <button onClick={() => setActiveTab('bots')} className={`px-4 py-3 text-sm font-medium flex items-center gap-2 border-b-2 ${activeTab === 'bots' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
            <Bot className="w-4 h-4" /> Bot Ordusu
          </button>
          <button onClick={() => setActiveTab('interactions')} className={`px-4 py-3 text-sm font-medium flex items-center gap-2 border-b-2 ${activeTab === 'interactions' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
            <Users className="w-4 h-4" /> Bekleyen Etkileşim Onayları
            {suggestions.length > 0 && (
              <span className="ml-1 bg-primary text-primary-foreground text-[10px] px-1.5 py-0.5 rounded-full">{suggestions.length}</span>
            )}
          </button>
          <button onClick={() => setActiveTab('slang')} className={`px-4 py-3 text-sm font-medium flex items-center gap-2 border-b-2 ${activeTab === 'slang' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}>
            <Database className="w-4 h-4" /> Mackolik Havuzu
          </button>
        </div>

        {activeTab === 'bots' && (
          <div className="p-4 border-b border-border flex gap-4">
            <div className="relative flex-1">
              <Search className="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input 
                type="text" 
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Bot adı, takım veya persona ara..." 
                className="w-full pl-10 pr-4 py-2 bg-muted border border-border rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 text-foreground"
              />
            </div>
          </div>
        )}

        <div className="flex-1 overflow-auto">
          {activeTab === 'bots' ? (
            loading ? (
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
                {filteredBots.map((bot) => (
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
          )) : activeTab === 'interactions' ? (
            loadingSuggestions ? (
              <div className="flex items-center justify-center h-full text-muted-foreground">
                Bekleyen etkileşimler yükleniyor...
              </div>
            ) : suggestions.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
                <Check className="w-16 h-16 mb-4 opacity-50 text-green-500" />
                <p>Bekleyen Onay Yok.</p>
                <p className="text-sm">Tüm bot etkileşimleri kontrol edildi.</p>
              </div>
            ) : (
              <div className="p-4 grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
                {suggestions.map(suggestion => (
                  <div key={suggestion.id} className="bg-muted/30 border border-border rounded-lg p-4 flex flex-col gap-3">
                    <div className="flex justify-between items-start">
                      <div className="flex items-center gap-2">
                         <img src={suggestion.bot?.avatar_url || `https://ui-avatars.com/api/?name=B`} className="w-8 h-8 rounded-full border border-border" />
                         <div>
                            <div className="text-xs text-primary font-bold">Bot</div>
                            <div className="text-sm font-medium leading-none">{suggestion.bot?.username || 'Bilinmiyor'}</div>
                         </div>
                      </div>
                      <div className="text-muted-foreground">➡️</div>
                      <div className="flex items-center gap-2 flex-row-reverse">
                         <img src={suggestion.target?.avatar_url || `https://ui-avatars.com/api/?name=U`} className="w-8 h-8 rounded-full border border-border" />
                         <div className="text-right">
                            <div className="text-xs text-muted-foreground font-bold">Hedef (Takip)</div>
                            <div className="text-sm font-medium leading-none">{suggestion.target?.username || 'Bilinmiyor'}</div>
                         </div>
                      </div>
                    </div>
                    <div className="bg-background border border-border rounded p-2 text-sm">
                      <p className="flex items-start gap-2 text-muted-foreground italic">
                        <MessageSquare className="w-4 h-4 mt-0.5 shrink-0" />
                        "{suggestion.reason}"
                      </p>
                    </div>
                    <div className="flex gap-2 mt-auto pt-2">
                       <button 
                         onClick={() => handleSuggestionAction(suggestion.id, 'approved')}
                         className="flex-1 flex items-center justify-center gap-2 bg-green-500/10 text-green-500 hover:bg-green-500/20 py-2 rounded-md font-medium text-sm transition-colors"
                       >
                         <Check className="w-4 h-4" /> Onayla
                       </button>
                       <button 
                         onClick={() => handleSuggestionAction(suggestion.id, 'rejected')}
                         className="flex-1 flex items-center justify-center gap-2 bg-red-500/10 text-red-500 hover:bg-red-500/20 py-2 rounded-md font-medium text-sm transition-colors"
                       >
                         <X className="w-4 h-4" /> Reddet
                       </button>
                    </div>
                  </div>
                ))}
              </div>
            )
          ) : activeTab === 'slang' ? (
            loadingSlangs ? (
              <div className="flex items-center justify-center h-full text-muted-foreground">
                Mackolik yorumları yükleniyor...
              </div>
            ) : slangs.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
                <Database className="w-16 h-16 mb-4 opacity-50 text-blue-500" />
                <p>Havuzda hiç yorum yok.</p>
                <p className="text-sm">Scraper arka planda çalıştıkça burası dolacaktır.</p>
              </div>
            ) : (
             <div className="p-4 overflow-auto h-full"> 
              <table className="w-full text-sm text-left relative">
                <thead className="bg-muted/50 text-muted-foreground sticky top-0 uppercase text-xs z-10">
                  <tr>
                    <th className="px-6 py-3 font-medium">Tarih</th>
                    <th className="px-6 py-3 font-medium w-3/5">Yorum İçeriği</th>
                    <th className="px-6 py-3 font-medium">Kaynak (Maç)</th>
                    <th className="px-6 py-3 text-right font-medium">İşlemler</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {slangs.map((slang) => (
                    <tr key={slang.id} className="hover:bg-muted/30 transition-colors">
                      <td className="px-6 py-4 whitespace-nowrap text-muted-foreground">
                        {new Date(slang.created_at).toLocaleDateString()} {new Date(slang.created_at).toLocaleTimeString().slice(0,5)}
                      </td>
                      <td className="px-6 py-4 font-medium max-w-lg break-words text-foreground">
                        "{slang.content}"
                      </td>
                      <td className="px-6 py-4 text-xs text-muted-foreground max-w-[200px] truncate" title={slang.match_id}>
                        <a href={slang.match_id} target="_blank" rel="noreferrer" className="text-primary hover:underline">
                           Linke Git
                        </a>
                      </td>
                      <td className="px-6 py-4 text-right">
                        <button 
                          onClick={() => handleDeleteSlang(slang.id)}
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
              </div>
            )
          ) : null}
        </div>
      </div>

      {/* CREATE SWARM MODAL */}
      {showCreateModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
          <div className="bg-card w-full max-w-md rounded-xl border border-border shadow-2xl overflow-hidden p-6 animate-in fade-in zoom-in duration-200">
            <h3 className="text-xl font-bold mb-4">Yeni Bot Ordusu Yarat</h3>
            <form onSubmit={handleGenerateSwarm} className="space-y-4">
              
              <div className="flex items-center gap-3 p-3 bg-primary/10 rounded-lg outline outline-1 outline-primary/20 cursor-pointer" onClick={() => setAutoMode(!autoMode)}>
                <div className={`w-5 h-5 rounded-full border flex items-center justify-center transition-colors ${autoMode ? 'bg-primary border-primary' : 'border-muted-foreground'}`}>
                  {autoMode && <Check className="w-3 h-3 text-primary-foreground" />}
                </div>
                <div>
                  <div className="font-semibold text-sm">Ollama AI ile Otomatik Karakter Üret</div>
                  <div className="text-xs text-muted-foreground">Yaş, memleket ve tutulan takımı yapay zeka tasarlar.</div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-muted-foreground mb-1">Kaç Adet Bot?</label>
                <input 
                  type="number" 
                  min="1" max="15"
                  required
                  value={swarmCount}
                  onChange={(e) => setSwarmCount(Number(e.target.value))}
                  className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary"
                />
                <p className="text-xs text-muted-foreground mt-1">Yapay zeka üretiminde max 15 önerilir (Timeout önlemi).</p>
              </div>

              {autoMode && (
                <div>
                  <label className="block text-sm font-medium text-muted-foreground mb-1">Ollama Model Adı</label>
                  <input 
                    type="text" 
                    required
                    value={ollamaModel}
                    onChange={(e) => setOllamaModel(e.target.value)}
                    className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary"
                    placeholder="örn: gemma2:2b, llama3..."
                  />
                  <p className="text-xs text-muted-foreground mt-1">Bilgisayarınıza inik bir Ollama modelini yazın.</p>
                </div>
              )}

              {!autoMode && (
                <>
                  <div>
                    <label className="block text-sm font-medium text-muted-foreground mb-1">Hangi Takım?</label>
                    <input 
                      type="text"
                      list="team-options"
                      value={team}
                      onChange={(e) => setTeam(e.target.value)}
                      placeholder="Takım ara veya listeden seç..."
                      className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary text-foreground"
                      required={!autoMode}
                    />
                    <datalist id="team-options">
                      {teams.map((t) => (
                        <option key={t} value={t} />
                      ))}
                    </datalist>
                    {teams.length === 0 && <p className="text-xs text-muted-foreground mt-1 text-orange-500">Takımlar yükleniyor...</p>}
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-muted-foreground mb-1">Persona Yönergesi</label>
                    <textarea 
                      required={!autoMode}
                      rows={4}
                      value={personaPrompt}
                      onChange={(e) => setPersonaPrompt(e.target.value)}
                      className="w-full px-3 py-2 bg-background border border-border rounded-md focus:ring-2 focus:ring-primary text-sm"
                      placeholder="Botların davranış şeklini anlatın..."
                    />
                  </div>
                </>
              )}
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
