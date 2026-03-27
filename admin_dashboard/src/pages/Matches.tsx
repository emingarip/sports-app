import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Search, Activity, Users as UsersIcon, Mic, Trophy, Clock, Play, StopCircle } from 'lucide-react';

interface Match {
  id: string;
  home_team: string;
  away_team: string;
  home_logo_url: string;
  away_logo_url: string;
  status: string;
  home_score: number;
  away_score: number;
  minute: string;
  league_name: string;
  started_at: string;
  match_interest_stats: {
    total_interested_users: number;
  }[];
}

interface AudioRoom {
  id: string;
  match_id: string;
  room_name: string;
  listener_count: number;
  host_id: string;
  is_private: boolean;
}

export default function Matches() {
  const [matches, setMatches] = useState<Match[]>([]);
  const [audioRooms, setAudioRooms] = useState<AudioRoom[]>([]);
  const [liveViewers, setLiveViewers] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'live' | 'finished'>('all');
  const [selectedDate, setSelectedDate] = useState<string>(new Date().toISOString().split('T')[0]);
  const [activeMiniGames, setActiveMiniGames] = useState<Record<string, string>>({}); // match_id -> gameId
  const [isProcessing, setIsProcessing] = useState<Record<string, boolean>>({});

  useEffect(() => {
    fetchData();

    // Subscribe to global match presence
    const channel = supabase.channel('global_match_presence', {
      config: {
        presence: {
          key: 'admin_dashboard',
        },
      },
    });

    channel.on('presence', { event: 'sync' }, () => {
      const state = channel.presenceState();
      const counts: Record<string, number> = {};
      
      for (const id in state) {
        const presences = state[id] as { match_id?: string }[];
        for (const p of presences) {
          if (p.match_id) {
            counts[p.match_id] = (counts[p.match_id] || 0) + 1;
          }
        }
      }
      setLiveViewers(counts);
    });

    channel.subscribe();

    // Subscribe to audio rooms changes
    const roomsSubscription = supabase
      .channel('public:audio_rooms')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'audio_rooms' }, () => {
        fetchAudioRooms();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
      supabase.removeChannel(roomsSubscription);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedDate]); // Refetch when selectedDate changes

  async function fetchData() {
    setLoading(true);
    await Promise.all([fetchMatches(), fetchAudioRooms()]);
    setLoading(false);
  };


  async function fetchMatches() {
    const startOfDay = new Date(selectedDate);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(selectedDate);
    endOfDay.setHours(23, 59, 59, 999);

    const { data: matchesData, error: matchesError } = await supabase
      .from('matches')
      .select('*')
      .or(`status.eq.live,and(started_at.gte.${startOfDay.toISOString()},started_at.lte.${endOfDay.toISOString()})`)
      .order('started_at', { ascending: false })
      .limit(1000);

    if (matchesError) {
      console.error('Error fetching matches:', matchesError);
      return;
    }

    if (!matchesData || matchesData.length === 0) {
      setMatches([]);
      return;
    }

    const matchIds = matchesData.map((m: { id: string }) => m.id);

    const { data: statsData, error: statsError } = await supabase
      .from('match_interest_stats')
      .select('match_id, total_interested_users')
      .in('match_id', matchIds);

    if (statsError) {
      console.error('Error fetching match stats:', statsError);
    }

    const matchesWithStats = matchesData.map((match: Match) => {
      const stats = statsData?.filter((s: { match_id: string, total_interested_users: number }) => s.match_id === match.id) || [];
      return {
        ...match,
        match_interest_stats: stats.map((s: { total_interested_users: number }) => ({ total_interested_users: s.total_interested_users })),
      } as Match;
    });

    setMatches(matchesWithStats);
  };

  async function fetchAudioRooms() {

    const { data, error } = await supabase
      .from('audio_rooms')
      .select('*');

    if (error) {
      console.error('Error fetching audio rooms:', error);
    } else {
      setAudioRooms(data || []);
    }
  };

  const startMiniGame = async (matchId: string) => {
    setIsProcessing(prev => ({ ...prev, [matchId]: true }));
    try {
      // 1. Generate a unique game ID
      const gameId = `keepy_uppy_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
      
      // 2. Broadcast START_MINI_GAME to the specific match room
      await new Promise<void>((resolve, reject) => {
        const channel = supabase.channel(`match_${matchId}`);
        channel.subscribe(async (status) => {
          if (status === 'SUBSCRIBED') {
            await channel.send({
              type: 'broadcast',
              event: 'mini_game',
              payload: {
                action: 'START_MINI_GAME',
                gameId: gameId,
              }
            });
            // Delay removing the channel to ensure message is flushed to the network
            setTimeout(() => {
              supabase.removeChannel(channel);
            }, 1000);
            resolve();
          }
          if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
            supabase.removeChannel(channel);
            reject(new Error("Failed to subscribe to channel"));
          }
        });
      });
      
      // 3. Update local state
      setActiveMiniGames(prev => ({ ...prev, [matchId]: gameId }));
      alert(`Top Sektirme oyunu başlatıldı! Oda: ${matchId}`);
    } catch (err) {
      console.error("Failed to start mini game:", err);
      alert("Oyun başlatılırken hata oluştu.");
    } finally {
      setIsProcessing(prev => ({ ...prev, [matchId]: false }));
    }
  };

  const endMiniGame = async (matchId: string) => {
    const gameId = activeMiniGames[matchId];
    if (!gameId) return;

    setIsProcessing(prev => ({ ...prev, [matchId]: true }));
    try {
      // Call the Edge Function to finalize and distribute rewards
      const { data, error } = await supabase.functions.invoke('finalize-mini-game', {
        body: { gameId: gameId, roomId: matchId }
      });

      if (error) throw error;
      
      setActiveMiniGames(prev => {
        const next = { ...prev };
        delete next[matchId];
        return next;
      });
      
      alert(`Oyun başarıyla bitirildi ve ödüller dağıtıldı! Kazananlar:\n` + (data?.winners?.map((w: any) => `#${w.rank} ${w.username} - Skor: ${w.score}`).join('\n') || 'Yok'));
    } catch (err: any) {
      console.error("Failed to finalize mini game:", err);
      alert(`Oyun bitirilirken hata oluştu: ${err.message || 'Bilinmeyen hata'}`);
    } finally {
      setIsProcessing(prev => ({ ...prev, [matchId]: false }));
    }
  };

  const filteredMatches = matches
    .filter((m) => {
      // 1. Text Search Filter
      const matchesSearch =
        m.home_team.toLowerCase().includes(searchTerm.toLowerCase()) ||
        m.away_team.toLowerCase().includes(searchTerm.toLowerCase()) ||
        m.league_name.toLowerCase().includes(searchTerm.toLowerCase());
      
      // 2. Status Filter
      const matchesStatus =
        statusFilter === 'all' ? true : statusFilter === 'live' ? m.status === 'live' : m.status !== 'live';

      return matchesSearch && matchesStatus;
    })
    .sort((a, b) => {
      // 1. Live status priority
      const aIsLive = a.status === 'live' ? 1 : 0;
      const bIsLive = b.status === 'live' ? 1 : 0;
      if (aIsLive !== bIsLive) return bIsLive - aIsLive;

      // 2. Live viewers priority
      const aLiveViews = liveViewers[a.id] || 0;
      const bLiveViews = liveViewers[b.id] || 0;
      if (aLiveViews !== bLiveViews) return bLiveViews - aLiveViews;

      // 3. Historical views priority
      const aTotal = a.match_interest_stats?.[0]?.total_interested_users || 0;
      const bTotal = b.match_interest_stats?.[0]?.total_interested_users || 0;
      return bTotal - aTotal;
    });


  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-foreground">Canlı Maçlar & İzleyici Radarı</h1>
          <p className="text-muted-foreground mt-1">Sistemdeki maçları, o anlık canlı bakan ve tarihsel ilgilenen kullanıcı sayısını görün.</p>
        </div>
        <button 
          onClick={fetchData} 
          className="bg-primary text-primary-foreground px-4 py-2 rounded-md hover:bg-primary/90 transition-colors"
        >
          Verileri Yenile
        </button>
      </div>


      {/* Filters (Search, Date & Status) */}
      <div className="flex flex-col lg:flex-row gap-4 mb-6">

        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground w-5 h-5" />
          <input
            type="text"
            placeholder="Takım veya lig ara..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-card border border-border rounded-md text-foreground focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
        </div>

        
        <div className="flex items-center gap-4 flex-wrap">
          <input 
            type="date" 
            value={selectedDate}
            onChange={(e) => {
              if (e.target.value) setSelectedDate(e.target.value);
            }}
            className="px-4 py-1.5 bg-card border border-border rounded-md text-foreground focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
          
          <div className="flex bg-secondary/30 border border-border rounded-md p-1">
            <button 
              onClick={() => setStatusFilter('all')}
              className={`px-4 py-1.5 text-sm font-medium rounded-sm transition-colors ${statusFilter === 'all' ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}
            >
              Tümü
            </button>
            <button 
              onClick={() => setStatusFilter('live')}
              className={`px-4 py-1.5 text-sm font-medium rounded-sm transition-colors ${statusFilter === 'live' ? 'bg-red-500 text-white shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}
            >
              Canlı
            </button>
            <button 
              onClick={() => setStatusFilter('finished')}
              className={`px-4 py-1.5 text-sm font-medium rounded-sm transition-colors ${statusFilter === 'finished' ? 'bg-card border-border shadow-sm text-foreground' : 'text-muted-foreground hover:text-foreground'}`}
            >
              Bitenler
            </button>
          </div>
        </div>

      </div>

      {/* Matches Grid */}
      {loading ? (
        <div className="flex h-64 items-center justify-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredMatches.map((match) => {
            const historicalViews = match.match_interest_stats?.[0]?.total_interested_users || 0;
            const liveViews = liveViewers[match.id] || 0;
            const matchAudioRooms = audioRooms.filter((r) => r.match_id === match.id);

            return (
              <div key={match.id} className="bg-card border border-border rounded-xl p-5 shadow-sm hover:shadow-md transition-shadow">
                
                {/* League & Status */}
                <div className="flex justify-between items-center mb-4">

                  <div className="flex flex-col gap-1">
                    <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider truncate max-w-[150px]" title={match.league_name}>
                      {match.league_name}
                    </span>
                    <span className="text-xs text-muted-foreground/70 flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {match.started_at ? new Date(match.started_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) : 'Saat Yok'}
                    </span>
                  </div>
                  {match.status === 'live' ? (
                    <div className="flex flex-col items-end gap-1">
                      <span className="px-2 py-0.5 bg-red-500/10 text-red-500 text-xs font-bold rounded flex items-center gap-1.5 animate-pulse">
                        <span className="w-1.5 h-1.5 bg-red-500 rounded-full"></span>
                        CANLI
                      </span>
                      <span className="text-xs font-medium text-red-500/80">{match.minute}' dk geçti</span>
                    </div>

                  ) : (
                    <span className="px-2 py-1 bg-secondary text-secondary-foreground text-xs font-semibold rounded">
                      {match.status.toUpperCase()}
                    </span>
                  )}
                </div>

                {/* Teams & Score */}
                <div className="flex justify-between items-center mb-6">
                  <div className="flex flex-col items-center flex-1">
                    <img src={match.home_logo_url} alt={match.home_team} className="w-12 h-12 object-contain mb-2" />
                    <span className="text-sm font-semibold text-center leading-tight">{match.home_team}</span>
                  </div>
                  
                  <div className="px-4 flex flex-col items-center justify-center">
                    <span className="text-2xl font-black">{match.home_score} - {match.away_score}</span>
                  </div>

                  <div className="flex flex-col items-center flex-1">
                    <img src={match.away_logo_url} alt={match.away_team} className="w-12 h-12 object-contain mb-2" />
                    <span className="text-sm font-semibold text-center leading-tight">{match.away_team}</span>
                  </div>
                </div>

                {/* Admin Quick Actions */}
                {match.status === 'live' && (
                  <div className="flex gap-2 mb-4">
                    {!activeMiniGames[match.id] ? (
                       <button 
                         onClick={() => startMiniGame(match.id)}
                         disabled={isProcessing[match.id]}
                         className="flex-1 bg-indigo-500/10 hover:bg-indigo-500/20 text-indigo-500 border border-indigo-500/20 py-2 rounded flex items-center justify-center gap-2 text-sm font-medium transition-colors disabled:opacity-50"
                       >
                         <Play className="w-4 h-4" />
                         {isProcessing[match.id] ? 'Başlatılıyor...' : 'Top Sektirme Başlat'}
                       </button>
                    ) : (
                       <button 
                         onClick={() => endMiniGame(match.id)}
                         disabled={isProcessing[match.id]}
                         className="flex-1 bg-red-500/10 hover:bg-red-500/20 text-red-500 border border-red-500/20 py-2 rounded flex items-center justify-center gap-2 text-sm font-medium transition-colors disabled:opacity-50"
                       >
                         <StopCircle className="w-4 h-4" />
                         {isProcessing[match.id] ? 'Bitiriliyor...' : 'Yarışmayı Bitir (Ödül Dağıt)'}
                       </button>
                    )}
                  </div>
                )}

                {/* Viewership Stats */}
                <div className="grid grid-cols-2 gap-3 mb-4">
                  <div className="bg-secondary/50 rounded-lg p-3 flex flex-col items-center justify-center">
                     <div className="flex items-center gap-1.5 text-muted-foreground mb-1">
                       <Trophy className="w-4 h-4" />
                       <span className="text-xs font-medium uppercase tracking-wider">Toplam İlgi</span>
                     </div>
                     <span className="text-xl font-bold text-foreground">{historicalViews}</span>
                  </div>
                  
                  <div className={`rounded-lg p-3 flex flex-col items-center justify-center ${liveViews > 0 ? 'bg-primary/10 border border-primary/20' : 'bg-secondary/50'}`}>
                     <div className={`flex items-center gap-1.5 mb-1 ${liveViews > 0 ? 'text-primary' : 'text-muted-foreground'}`}>
                       <Activity className="w-4 h-4" />
                       <span className="text-xs font-medium uppercase tracking-wider">Canlı İzleyici</span>
                     </div>
                     <span className={`text-xl font-bold ${liveViews > 0 ? 'text-primary' : 'text-foreground'}`}>{liveViews}</span>
                  </div>
                </div>

                {/* Audio Rooms */}
                {matchAudioRooms.length > 0 && (
                  <div className="mt-4 pt-4 border-t border-border space-y-2">
                    <h4 className="text-xs font-semibold text-muted-foreground uppercase flex items-center gap-1.5">
                      <Mic className="w-3.5 h-3.5" />
                      Aktif Sesli Odalar ({matchAudioRooms.length})
                    </h4>
                    {matchAudioRooms.map(room => (
                      <div key={room.id} className="flex justify-between items-center bg-background rounded-md p-2 border border-border">
                        <div className="flex items-center gap-2 truncate">
                          {room.is_private ? <div className="w-2 h-2 rounded-full bg-yellow-500" /> : <div className="w-2 h-2 rounded-full bg-green-500" />}
                          <span className="text-sm font-medium truncate">{room.room_name}</span>
                        </div>
                        <div className="flex items-center gap-1 text-muted-foreground shrink-0 ml-2">
                          <UsersIcon className="w-3 h-3" />
                          <span className="text-xs">{room.listener_count}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
          
          {filteredMatches.length === 0 && (
            <div className="col-span-full py-12 text-center text-muted-foreground bg-card border border-border rounded-xl">
              Aramanızla eşleşen maç bulunamadı.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
