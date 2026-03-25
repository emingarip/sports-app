import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Users, Coins, Activity, TrendingUp } from 'lucide-react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { format, subDays, startOfDay, parseISO } from 'date-fns';
import { tr } from 'date-fns/locale';

interface DashboardStats {
  totalUsers: number;
  totalKCoins: number;
  totalBets: number;
}

interface BetData {
  id: string;
  created_at: string;
  user_id: string;
  amount: number;
  users: { email: string; username: string };
  matches: { home_team: { name: string }; away_team: { name: string } };
}

export default function Dashboard({ _session }: { _session?: any }) {
  const [stats, setStats] = useState<DashboardStats>({ totalUsers: 0, totalKCoins: 0, totalBets: 0 });
  const [recentBets, setRecentBets] = useState<BetData[]>([]);
  const [loading, setLoading] = useState(true);
  const [chartData, setChartData] = useState<{name: string, dateString: string, BahisSayisi: number}[]>([]);
  const [liveUsersCount, setLiveUsersCount] = useState<number>(0);

  useEffect(() => {
    fetchDashboardData();

    // Setup Realtime subscription for entire public schema
    const channel = supabase
      .channel('dashboard_metrics')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public' },
        (payload) => {
           console.log('📡 Realtime tetiklendi! Gelen veri:', payload);
           fetchDashboardData();
        }
      )
      .subscribe((status) => {
        console.log('Realtime Bağlantı Durumu:', status);
      });

    // Setup Presence for global online users
    const presenceChannel = supabase.channel('online_users');
    presenceChannel
      .on('presence', { event: 'sync' }, () => {
        const state = presenceChannel.presenceState();
        let count = 0;
        for (const id in state) {
           count += state[id].length;
        }
        setLiveUsersCount(count);
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
      supabase.removeChannel(presenceChannel);
    };
  }, []);

  const fetchDashboardData = async () => {
    try {
      // 1. Total Users
      const { count: userCount } = await supabase
        .from('users')
        .select('*', { count: 'exact', head: true });

      // 2. Circulating K-Coins
      // Since fetching all balances could be heavy, ideally this would be an RPC function.
      // But for the MVP, we will fetch and sum locally.
      const { data: userData } = await supabase.from('users').select('k_coin_balance');
      const totalCoins = userData?.reduce((acc, user) => acc + (user.k_coin_balance || 0), 0) || 0;

      // 3. Total Bets
      const { count: betCount } = await supabase
        .from('user_bets')
        .select('*', { count: 'exact', head: true });

      setStats({
        totalUsers: userCount || 0,
        totalKCoins: totalCoins,
        totalBets: betCount || 0,
      });

      // 4. Recent Bets (with relationships)
      const { data: betsData } = await supabase
        .from('user_bets')
        .select('id, created_at, amount, user_id, users(email, username), matches(home_team, away_team)')
        .order('created_at', { ascending: false })
        .limit(10);
      setRecentBets((betsData as unknown as BetData[]) || []);

      // 5. Build Chart Data (Last 7 Days)
      const sevenDaysAgo = startOfDay(subDays(new Date(), 6)).toISOString();
      
      const { data: last7DaysBets } = await supabase
        .from('user_bets')
        .select('created_at')
        .gte('created_at', sevenDaysAgo);

      if (last7DaysBets) {
          // Group by Date
          const groupedStats = Array.from({ length: 7 }).map((_, i) => {
            const date = startOfDay(subDays(new Date(), 6 - i));
            return {
                name: format(date, 'd MMM', { locale: tr }),
                dateString: date.toISOString().split('T')[0],
                BahisSayisi: 0,
            }
          });

          last7DaysBets.forEach(bet => {
            const betDate = bet.created_at.split('T')[0];
            const targetGroup = groupedStats.find(g => g.dateString === betDate);
            if(targetGroup) targetGroup.BahisSayisi++;
          });

          setChartData(groupedStats);
      }

    } catch (error) {
      console.error('Error fetching dashboard data', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <div className="text-muted-foreground">Veriler yükleniyor...</div>;
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Genel Bakış</h1>
        <p className="text-muted-foreground mt-1">
          SportsApp ekonomisi ve canlı kullanıcı hareketleri.
        </p>
      </div>

      {/* Primary Metrics Layer */}
      <div className="grid gap-4 md:grid-cols-3">
        <div className="px-6 py-5 rounded-xl border border-border bg-card shadow-sm flex items-center justify-between">
            <div>
                <div className="flex items-center gap-3">
                    <p className="text-sm font-medium text-muted-foreground">Toplam Kullanıcı</p>
                    <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-500 text-[10px] font-bold uppercase tracking-wider border border-emerald-500/20">
                      <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.8)]"></span>
                      Şu An: {liveUsersCount}
                    </span>
                </div>
                <h3 className="text-3xl font-bold mt-2 text-card-foreground">{stats.totalUsers}</h3>
            </div>
            <div className="p-3 bg-primary/10 rounded-full text-primary">
                <Users className="w-6 h-6" />
            </div>
        </div>
        <div className="px-6 py-5 rounded-xl border border-border bg-card shadow-sm flex items-center justify-between">
            <div>
                <p className="text-sm font-medium text-muted-foreground">Dolaşımdaki K-Coin</p>
                <h3 className="text-3xl font-bold mt-1 text-card-foreground">
                    {stats.totalKCoins.toLocaleString('tr-TR')}
                </h3>
            </div>
            <div className="p-3 bg-yellow-500/10 rounded-full text-yellow-500">
                <Coins className="w-6 h-6" />
            </div>
        </div>
        <div className="px-6 py-5 rounded-xl border border-border bg-card shadow-sm flex items-center justify-between">
            <div>
                <p className="text-sm font-medium text-muted-foreground">Toplam Bahis Hacmi</p>
                <h3 className="text-3xl font-bold mt-1 text-card-foreground">{stats.totalBets}</h3>
            </div>
            <div className="p-3 bg-emerald-500/10 rounded-full text-emerald-500">
                <Activity className="w-6 h-6" />
            </div>
        </div>
      </div>

      <div className="grid gap-6 grid-cols-1 lg:grid-cols-7">
         {/* Live Chart Section */}
         <div className="col-span-4 border border-border bg-card rounded-xl shadow-sm p-6 flex flex-col">
            <div className="flex items-center gap-2 mb-6">
                <TrendingUp className="w-5 h-5 text-muted-foreground" />
                <h3 className="text-lg font-semibold text-card-foreground">Günlük Bahis Eğilimi (Son 7 Gün)</h3>
            </div>
            <div className="flex-1 w-full min-h-[300px]">
                <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={chartData}>
                        <CartesianGrid strokeDasharray="3 3" stroke="#333" vertical={false} />
                        <XAxis dataKey="name" stroke="#666" fontSize={12} tickLine={false} axisLine={false} />
                        <YAxis stroke="#666" fontSize={12} tickLine={false} axisLine={false} />
                        <Tooltip 
                            contentStyle={{ backgroundColor: '#111', border: '1px solid #333', borderRadius: '8px' }}
                            itemStyle={{ color: '#fff' }}
                        />
                        <Line 
                            type="monotone" 
                            dataKey="BahisSayisi" 
                            stroke="#3b82f6" 
                            strokeWidth={3}
                            dot={{ fill: '#3b82f6', r: 4 }} 
                            activeDot={{ r: 6 }}
                        />
                    </LineChart>
                </ResponsiveContainer>
            </div>
         </div>

         {/* Live Activity Feed */}
         <div className="col-span-3 border border-border bg-card rounded-xl shadow-sm overflow-hidden flex flex-col">
             <div className="p-6 border-b border-border">
                <h3 className="text-lg font-semibold text-card-foreground">Son Oynanan Bahisler</h3>
             </div>
             <div className="flex-1 overflow-y-auto max-h-[400px]">
                {recentBets.length === 0 ? (
                    <div className="p-6 text-center text-muted-foreground">Henüz bahis bulunamadı.</div>
                ) : (
                    <div className="divide-y divide-border">
                        {recentBets.map(bet => {
                            const homeTeam = (bet.matches?.home_team as unknown as {name: string})?.name || 'Ev Sahibi';
                            const awayTeam = (bet.matches?.away_team as unknown as {name: string})?.name || 'Deplasman';
                            const username = bet.users?.username || bet.users?.email?.split('@')[0] || 'Anonim';
                            
                            return (
                                <div key={bet.id} className="p-4 flex items-center justify-between hover:bg-muted/10 transition-colors">
                                    <div>
                                        <p className="text-sm font-medium text-card-foreground">
                                            {username}
                                        </p>
                                        <p className="text-xs text-muted-foreground truncate max-w-[200px]">
                                            {homeTeam} vs {awayTeam}
                                        </p>
                                    </div>
                                    <div className="text-right">
                                        <p className="text-sm font-bold text-yellow-500">
                                            {bet.amount} K-Coin
                                        </p>
                                        <p className="text-xs text-muted-foreground">
                                            {format(parseISO(bet.created_at), 'HH:mm', { locale: tr })}
                                        </p>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                )}
             </div>
         </div>
      </div>
    </div>
  );
}
