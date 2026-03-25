import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Search, Activity, Users as UsersIcon, Mic, Trophy } from 'lucide-react';

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
        const presences = state[id] as any[];
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
  }, []);

  const fetchData = async () => {
    setLoading(true);
    await Promise.all([fetchMatches(), fetchAudioRooms()]);
    setLoading(false);
  };

  const fetchMatches = async () => {
    const { data, error } = await supabase
      .from('matches')
      .select('*, match_interest_stats(total_interested_users)')
      .order('started_at', { ascending: false })
      .limit(100);

    if (error) {
      console.error('Error fetching matches:', error);
    } else {
      setMatches(data || []);
    }
  };

  const fetchAudioRooms = async () => {
    const { data, error } = await supabase
      .from('audio_rooms')
      .select('*');

    if (error) {
      console.error('Error fetching audio rooms:', error);
    } else {
      setAudioRooms(data || []);
    }
  };

  const filteredMatches = matches.filter(
    (m) =>
      m.home_team.toLowerCase().includes(searchTerm.toLowerCase()) ||
      m.away_team.toLowerCase().includes(searchTerm.toLowerCase()) ||
      m.league_name.toLowerCase().includes(searchTerm.toLowerCase())
  );

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

      {/* Search */}
      <div className="flex gap-4">
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
                  <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                    {match.league_name}
                  </span>
                  {match.status === 'live' ? (
                    <span className="px-2 py-1 bg-red-500/10 text-red-500 text-xs font-bold rounded flex items-center gap-1 animate-pulse">
                      <span className="w-1.5 h-1.5 bg-red-500 rounded-full"></span>
                      {match.minute}'
                    </span>
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
