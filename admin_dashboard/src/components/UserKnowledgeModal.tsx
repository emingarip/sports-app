import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { X, Network, Loader2, Heart, MessageSquare, Target, Eye } from 'lucide-react';

interface KnowledgeModalProps {
  userId: string;
  username: string;
  onClose: () => void;
}

interface UserInterest {
  id: string;
  entity_type: string;
  entity_id: string;
  interest_score: number;
  interaction_count: number;
  last_interaction: string;
}

interface UserEvent {
  id: string;
  event_type: string;
  entity_type: string;
  entity_id: string;
  metadata: any;
  created_at: string;
}

export default function UserKnowledgeModal({ userId, username, onClose }: KnowledgeModalProps) {
  const [activeTab, setActiveTab] = useState<'interests' | 'events'>('interests');
  const [interests, setInterests] = useState<UserInterest[]>([]);
  const [events, setEvents] = useState<UserEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchData();
  }, [userId]);

  const fetchData = async () => {
    setLoading(true);
    setError(null);
    try {
      // Fetch Interests
      const { data: interestsData, error: interestsError } = await supabase.rpc('admin_get_user_interests', {
        target_user_id: userId
      });
      if (interestsError) throw interestsError;

      // Fetch Events
      const { data: eventsData, error: eventsError } = await supabase.rpc('admin_get_user_events', {
        target_user_id: userId
      });
      if (eventsError) throw eventsError;

      setInterests(interestsData || []);
      setEvents(eventsData || []);
    } catch (err: any) {
      console.error('Error fetching knowledge graph data:', err);
      setError(err.message || 'Veri yüklenirken bir hata oluştu.');
    } finally {
      setLoading(false);
    }
  };

  const getEventIcon = (eventType: string) => {
    switch (eventType) {
      case 'match_favorited':
        return <Heart className="w-4 h-4 text-red-500" />;
      case 'prediction_placed':
        return <Target className="w-4 h-4 text-blue-500" />;
      case 'chat_message_sent':
        return <MessageSquare className="w-4 h-4 text-green-500" />;
      case 'match_viewed':
        return <Eye className="w-4 h-4 text-gray-500" />;
      default:
        return <Network className="w-4 h-4 text-primary" />;
    }
  };

  const TranslateEntityType = (type: string) => {
    switch(type) {
      case 'team': return 'Takım';
      case 'league': return 'Lig';
      case 'match': return 'Maç';
      default: return type.charAt(0).toUpperCase() + type.slice(1);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
      <div className="bg-card w-full max-w-4xl max-h-[90vh] rounded-2xl shadow-xl border border-border flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        
        <div className="flex items-center justify-between p-6 border-b border-border bg-muted/30">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-xl">
              <Network className="w-6 h-6 text-primary" />
            </div>
            <div>
              <h2 className="text-xl font-bold">{username} - Knowledge Graph</h2>
              <p className="text-sm text-muted-foreground mt-0.5">Kullanıcının ilgi alanları ve geçmiş etkinlikleri</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 mr-[-8px] text-muted-foreground hover:text-foreground hover:bg-muted rounded-full transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex items-center border-b border-border bg-muted/10">
          <button
            onClick={() => setActiveTab('interests')}
            className={`flex-1 py-4 text-sm font-semibold border-b-2 transition-colors ${
              activeTab === 'interests'
                ? 'border-primary text-primary bg-primary/5'
                : 'border-transparent text-muted-foreground hover:bg-muted/30 hover:text-foreground'
            }`}
          >
            İlgi Skorları (Interests)
          </button>
          <button
            onClick={() => setActiveTab('events')}
            className={`flex-1 py-4 text-sm font-semibold border-b-2 transition-colors ${
              activeTab === 'events'
                ? 'border-primary text-primary bg-primary/5'
                : 'border-transparent text-muted-foreground hover:bg-muted/30 hover:text-foreground'
            }`}
          >
            Son Etkinlikler (Events)
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-6">
          {loading ? (
            <div className="flex flex-col items-center justify-center h-48 text-muted-foreground space-y-3">
              <Loader2 className="w-8 h-8 animate-spin text-primary" />
              <p>Knowledge Base algoritmaları çözümleniyor...</p>
            </div>
          ) : error ? (
            <div className="p-4 bg-destructive/10 text-destructive rounded-xl border border-destructive/20 text-center">
              <p className="font-medium">{error}</p>
            </div>
          ) : activeTab === 'interests' ? (
            // Interests Tab
            interests.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">Kullanıcı için henüz yeterli ilgi skoru oluşmamış.</div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {interests.map((interest) => (
                  <div key={interest.id} className="p-4 rounded-xl border border-border bg-card hover:bg-muted/10 transition-colors">
                    <div className="flex justify-between items-start mb-2">
                       <span className="text-xs font-semibold px-2 py-1 bg-secondary text-secondary-foreground rounded-md">
                          {TranslateEntityType(interest.entity_type)}
                       </span>
                       <span className="text-xl font-bold text-primary">
                          {interest.interest_score.toFixed(1)} <span className="text-xs font-normal text-muted-foreground ml-0.5">skor</span>
                       </span>
                    </div>
                    <h4 className="font-bold text-lg truncate mb-1" title={interest.entity_id}>{interest.entity_id}</h4>
                    <div className="flex justify-between items-center text-xs text-muted-foreground mt-3 pt-3 border-t border-border">
                      <span>{interest.interaction_count} etkileşim</span>
                      <span>Son: {new Date(interest.last_interaction).toLocaleDateString('tr-TR')}</span>
                    </div>
                  </div>
                ))}
              </div>
            )
          ) : (
            // Events Tab
            events.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">Henüz kaydedilmiş etkinlik bulunmuyor.</div>
            ) : (
               <div className="relative border-l-2 border-muted ml-3 space-y-6 pb-4">
                 {events.map((ev) => (
                   <div key={ev.id} className="relative pl-6">
                     <div className="absolute -left-[9px] top-1 w-4 h-4 bg-background border-2 border-muted-foreground rounded-full flex items-center justify-center">
                        <div className="w-1.5 h-1.5 bg-muted-foreground rounded-full" />
                     </div>
                     <div className="bg-card border border-border rounded-xl p-4 shadow-sm relative group hover:border-primary/50 transition-colors">
                       <div className="flex justify-between items-start mb-2">
                         <div className="flex items-center gap-2">
                           {getEventIcon(ev.event_type)}
                           <span className="font-semibold">{ev.event_type.replace('_', ' ')}</span>
                         </div>
                         <span className="text-xs text-muted-foreground">
                           {new Date(ev.created_at).toLocaleString('tr-TR')}
                         </span>
                       </div>
                       <div className="text-sm">
                         <span className="text-muted-foreground mr-2">{TranslateEntityType(ev.entity_type)}:</span>
                         <span className="font-medium bg-muted/50 px-2 py-0.5 rounded">{ev.entity_id}</span>
                       </div>
                       {Object.keys(ev.metadata || {}).length > 0 && (
                          <div className="mt-3 text-xs bg-muted/30 p-2 rounded text-muted-foreground font-mono">
                            {JSON.stringify(ev.metadata)}
                          </div>
                       )}
                     </div>
                   </div>
                 ))}
               </div>
            )
          )}
        </div>
      </div>
    </div>
  );
}
