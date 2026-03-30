import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { X, Network, Loader2 } from 'lucide-react';
import { ReactFlow, Controls, Background, MarkerType } from '@xyflow/react';
import type { Node, Edge } from '@xyflow/react';
import '@xyflow/react/dist/style.css';

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

const TranslateEntityType = (type: string) => {
  switch(type) {
    case 'team': return 'Takım';
    case 'league': return 'Lig';
    case 'match': return 'Maç';
    default: return type.charAt(0).toUpperCase() + type.slice(1);
  }
}

const getEventLabel = (type: string) => {
  switch(type) {
    case 'match_favorited': return 'Favoriye Aldı';
    case 'prediction_placed': return 'Tahmin Yaptı';
    case 'chat_message_sent': return 'Mesaj Attı';
    case 'match_viewed': return 'Görüntüledi';
    default: return type;
  }
}

export default function UserKnowledgeModal({ userId, username, onClose }: KnowledgeModalProps) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [nodes, setNodes] = useState<Node[]>([]);
  const [edges, setEdges] = useState<Edge[]>([]);
  const [maxNodes, setMaxNodes] = useState<number>(40);

  // Keep original data to rebuild graph when filter changes
  const [rawInterests, setRawInterests] = useState<UserInterest[]>([]);
  const [rawEvents, setRawEvents] = useState<UserEvent[]>([]);

  useEffect(() => {
    fetchData();
  }, [userId]);

  useEffect(() => {
    if (!loading && (rawInterests.length > 0 || rawEvents.length > 0)) {
      buildGraph(rawInterests, rawEvents, maxNodes);
    }
  }, [maxNodes, loading]); // Rebuild layout if Top N dropdown changes

  const fetchData = async () => {
    setLoading(true);
    setError(null);
    try {
      const { data: interestsData, error: interestsError } = await supabase.rpc('admin_get_user_interests', {
        target_user_id: userId
      });
      if (interestsError) throw interestsError;

      const { data: eventsData, error: eventsError } = await supabase.rpc('admin_get_user_events', {
        target_user_id: userId
      });
      if (eventsError) throw eventsError;

      const interests = interestsData || [] as UserInterest[];
      const events = eventsData || [] as UserEvent[];

      setRawInterests(interests);
      setRawEvents(events);

      buildGraph(interests, events, maxNodes);
    } catch (err: any) {
      console.error('Error fetching knowledge graph data:', err);
      setError(err.message || 'Veri yüklenirken bir hata oluştu.');
    } finally {
      setLoading(false);
    }
  };

  const buildGraph = (interests: UserInterest[], events: UserEvent[], nodeLimit: number) => {
    const initialNodes: Node[] = [];
    const initialEdges: Edge[] = [];

    // Center User Node
    initialNodes.push({
      id: 'center_user',
      position: { x: 0, y: 0 },
      data: { 
        label: (
          <div className="flex flex-col items-center justify-center font-bold text-white bg-blue-600 rounded-full w-24 h-24 shadow-lg border-4 border-blue-400 z-50 relative">
            <span className="text-2xl mb-1">👑</span>
            <span className="text-xs truncate max-w-[80px] px-1">{username}</span>
          </div>
        )
      },
      style: { background: 'transparent', border: 'none', padding: 0, width: 96, height: 96 },
      type: 'default',
    });

    const entityMap = new Map<string, { type: string, score: number }>();

    interests.forEach(i => {
      entityMap.set(i.entity_id, { type: i.entity_type, score: i.interest_score });
    });
    events.forEach(e => {
      if (!entityMap.has(e.entity_id)) {
        entityMap.set(e.entity_id, { type: e.entity_type, score: 0 }); 
      }
    });

    // Make an array and sort by score descending
    let entitiesList = Array.from(entityMap.entries());
    entitiesList.sort((a, b) => b[1].score - a[1].score);

    // Apply Node Limit
    if (nodeLimit !== -1) {
      entitiesList = entitiesList.slice(0, nodeLimit);
    }

    const eventsPerEntity = new Map<string, string[]>();
    events.forEach(e => {
      const list = eventsPerEntity.get(e.entity_id) || [];
      if (!list.includes(e.event_type)) {
        list.push(e.event_type);
      }
      eventsPerEntity.set(e.entity_id, list);
    });

    // Spiral Layout Settings
    let currentAngle = 0;
    const a = 180; // Starting radius (distance from center node)
    const b = 40;  // Radius growth per radian
    const targetArcLength = 220; // Pixels distance between consecutive nodes

    entitiesList.forEach(([entity_id, data]) => {
      // Calculate position on the spiral
      const radius = a + b * currentAngle;
      const x = Math.cos(currentAngle) * radius;
      const y = Math.sin(currentAngle) * radius;
      
      // Calculate angle increment for the next node based on desired arc length
      currentAngle += targetArcLength / radius;

      const recentEvents = eventsPerEntity.get(entity_id) || [];
      const hasEvents = recentEvents.length > 0;

      initialNodes.push({
        id: `entity_${entity_id}`,
        position: { x, y },
        data: { 
          label: (
            <div className="flex flex-col items-center">
              <span className="text-[10px] uppercase font-bold text-muted-foreground tracking-wider mb-1">{TranslateEntityType(data.type)}</span>
              <span className="font-bold text-sm text-foreground">{entity_id}</span>
              {data.score > 0 && <span className="text-xs text-blue-500 font-semibold mt-1">Skor: {data.score.toFixed(1)}</span>}
            </div>
          )
        },
        style: { 
          background: 'hsl(var(--card))', 
          border: data.score > 5 ? '2px solid #3b82f6' : '1px solid hsl(var(--border))', 
          borderRadius: '12px', 
          padding: '12px 16px',
          boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)',
          minWidth: 140
        }
      });

      // Edge setup
      if (data.score > 0) {
        initialEdges.push({
          id: `edge_interest_${entity_id}`,
          source: 'center_user',
          target: `entity_${entity_id}`,
          label: `İlgi: ${data.score.toFixed(1)}`,
          style: { strokeWidth: Math.max(1, Math.min(6, data.score / 3)), stroke: '#3b82f6' },
          markerEnd: { type: MarkerType.ArrowClosed, color: '#3b82f6' },
          animated: hasEvents,
        });
      } else if (hasEvents) {
        initialEdges.push({
          id: `edge_event_${entity_id}`,
          source: 'center_user',
          target: `entity_${entity_id}`,
          label: recentEvents.map(t => getEventLabel(t)).join(', '),
          animated: true,
          style: { stroke: '#10b981', strokeWidth: 2, strokeDasharray: '5,5' },
          markerEnd: { type: MarkerType.ArrowClosed, color: '#10b981' },
          type: 'smoothstep'
        });
      }
    });

    setNodes(initialNodes);
    setEdges(initialEdges);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
      <div className="bg-card w-full max-w-6xl h-[85vh] rounded-2xl shadow-xl border border-border flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        
        <div className="flex items-center justify-between p-6 border-b border-border bg-muted/30 z-10 relative">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-xl">
              <Network className="w-6 h-6 text-primary" />
            </div>
            <div>
              <h2 className="text-xl font-bold">{username} - Knowledge Graph</h2>
              <p className="text-sm text-muted-foreground mt-0.5">Kullanıcının ilgi alanları ve etkileşim ağı</p>
            </div>
          </div>
          
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <label className="text-sm font-medium text-muted-foreground">Gösterilecek Düğüm Limit:</label>
              <select 
                value={maxNodes} 
                onChange={(e) => setMaxNodes(parseInt(e.target.value))}
                className="px-3 py-1.5 border border-border rounded-md bg-background text-sm font-medium focus:ring-2 focus:ring-primary focus:outline-none"
              >
                <option value={20}>En Önemli 20</option>
                <option value={40}>En Önemli 40</option>
                <option value={100}>En Önemli 100</option>
                <option value={-1}>Tümü (Karmaşık Olabilir)</option>
              </select>
            </div>
            <button
              onClick={onClose}
              className="p-2 text-muted-foreground hover:text-foreground hover:bg-muted rounded-full transition-colors ml-2"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        <div className="flex-1 relative bg-muted/5">
          {loading ? (
            <div className="absolute inset-0 flex flex-col items-center justify-center text-muted-foreground space-y-3 z-20">
              <Loader2 className="w-8 h-8 animate-spin text-primary" />
              <p>Bağlantılar çözümleniyor...</p>
            </div>
          ) : error ? (
            <div className="absolute inset-0 flex items-center justify-center p-6 z-20">
              <div className="p-4 bg-destructive/10 text-destructive rounded-xl border border-destructive/20 text-center">
                <p className="font-medium">{error}</p>
              </div>
            </div>
          ) : (
            <div className="w-full h-full">
              <ReactFlow 
                nodes={nodes} 
                edges={edges} 
                fitView 
                fitViewOptions={{ padding: 0.1 }}
                minZoom={0.05}
                maxZoom={2}
                nodesDraggable={true}
                nodesConnectable={false}
              >
                <Background gap={16} size={1} color="rgba(150,150,150,0.2)" />
                <Controls className="bg-background border-border fill-foreground" />
              </ReactFlow>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
