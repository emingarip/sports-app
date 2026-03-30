import { useEffect, useState, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { X, Network, Loader2, Clock, Activity, Target, Info } from 'lucide-react';
import { ReactFlow, Controls, Background, MarkerType, Position } from '@xyflow/react';
import type { Node, Edge } from '@xyflow/react';
import dagre from 'dagre';
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

interface EntityRelation {
  id: string;
  entity_a_type: string;
  entity_a_id: string;
  entity_b_type: string;
  entity_b_id: string;
  relation_type: string;
  strength: number;
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

const getLayoutedElements = (nodes: Node[], edges: Edge[], direction = 'LR') => {
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));
  
  const isHorizontal = direction === 'LR';
  dagreGraph.setGraph({ rankdir: direction, ranksep: 180, nodesep: 100 });

  nodes.forEach((node) => {
    // Estimate node size
    let width = 160;
    let height = 80;
    if (node.id === 'center_user') {
      width = 96; height = 96;
    }
    dagreGraph.setNode(node.id, { width, height });
  });

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  dagre.layout(dagreGraph);

  const layoutedNodes = nodes.map((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);
    // Render target and source handles dynamically if needed, or rely on defaults
    return {
      ...node,
      targetPosition: isHorizontal ? Position.Left : Position.Top,
      sourcePosition: isHorizontal ? Position.Right : Position.Bottom,
      position: {
        x: nodeWithPosition.x - (nodeWithPosition.width || 0) / 2,
        y: nodeWithPosition.y - (nodeWithPosition.height || 0) / 2,
      },
    };
  });

  return { layoutedNodes, layoutedEdges: edges };
};

export default function UserKnowledgeModal({ userId, username, onClose }: KnowledgeModalProps) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [nodes, setNodes] = useState<Node[]>([]);
  const [edges, setEdges] = useState<Edge[]>([]);
  const [maxNodes, setMaxNodes] = useState<number>(30);
  
  const [selectedEntityId, setSelectedEntityId] = useState<string | null>(null);

  const [rawInterests, setRawInterests] = useState<UserInterest[]>([]);
  const [rawEvents, setRawEvents] = useState<UserEvent[]>([]);
  const [rawRelations, setRawRelations] = useState<EntityRelation[]>([]);

  useEffect(() => {
    fetchData();
  }, [userId]);

  useEffect(() => {
    if (!loading && (rawInterests.length > 0 || rawEvents.length > 0)) {
      buildGraph(rawInterests, rawEvents, rawRelations, maxNodes);
    }
  }, [maxNodes, loading, rawInterests, rawEvents, rawRelations]);

  const fetchData = async () => {
    setLoading(true);
    setError(null);
    try {
      const [interestsRes, eventsRes, relationsRes] = await Promise.all([
        supabase.rpc('admin_get_user_interests', { target_user_id: userId }),
        supabase.rpc('admin_get_user_events', { target_user_id: userId }),
        supabase.rpc('admin_get_user_entity_relations', { target_user_id: userId })
      ]);

      if (interestsRes.error) throw interestsRes.error;
      if (eventsRes.error) throw eventsRes.error;
      if (relationsRes.error) throw relationsRes.error;

      setRawInterests(interestsRes.data || []);
      setRawEvents(eventsRes.data || []);
      setRawRelations(relationsRes.data || []);
    } catch (err: any) {
      console.error('Error fetching knowledge graph data:', err);
      setError(err.message || 'Veri yüklenirken bir hata oluştu.');
    } finally {
      setLoading(false);
    }
  };

  const buildGraph = (interests: UserInterest[], events: UserEvent[], relations: EntityRelation[], nodeLimit: number) => {
    let initialNodes: Node[] = [];
    let initialEdges: Edge[] = [];

    initialNodes.push({
      id: 'center_user',
      position: { x: 0, y: 0 },
      data: { 
        label: (
          <div className="flex flex-col items-center justify-center font-bold text-white bg-blue-600 rounded-full w-24 h-24 shadow-lg border-4 border-blue-400">
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

    let entitiesList = Array.from(entityMap.entries());
    entitiesList.sort((a, b) => b[1].score - a[1].score);

    if (nodeLimit !== -1) {
      entitiesList = entitiesList.slice(0, nodeLimit);
    }
    
    // Keep a set of IDs that will actually be displayed
    const displayedIds = new Set(entitiesList.map(e => e[0]));

    const eventsPerEntity = new Map<string, string[]>();
    events.forEach(e => {
      const list = eventsPerEntity.get(e.entity_id) || [];
      if (!list.includes(e.event_type)) {
        list.push(e.event_type);
      }
      eventsPerEntity.set(e.entity_id, list);
    });

    // Add nodes
    entitiesList.forEach(([entity_id, data]) => {
      const isSelected = selectedEntityId === entity_id;
      initialNodes.push({
        id: `entity_${entity_id}`,
        position: { x: 0, y: 0 }, // Handled by dagre
        data: { 
          label: (
            <div className="flex flex-col items-center cursor-pointer">
              <span className="text-[10px] uppercase font-bold text-muted-foreground tracking-wider mb-1">
                {TranslateEntityType(data.type)}
              </span>
              <span className="font-bold text-sm text-foreground truncate max-w-full text-center px-2">{entity_id}</span>
              {data.score > 0 && <span className="text-xs text-blue-500 font-semibold mt-1">Skor: {data.score.toFixed(1)}</span>}
            </div>
          )
        },
        style: { 
          background: isSelected ? 'hsl(var(--primary)/0.1)' : 'hsl(var(--card))', 
          border: isSelected ? '2px solid hsl(var(--primary))' : (data.score > 5 ? '2px solid #3b82f6' : '1px solid hsl(var(--border))'), 
          borderRadius: '12px', 
          padding: '12px 10px',
          boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)',
          minWidth: 160,
          maxWidth: 180
        }
      });
    });

    // Create Edges
    const addedEdges = new Set<string>();

    // 1. Edges from Entity to Entity (from relations array)
    relations.forEach(rel => {
      if (displayedIds.has(rel.entity_a_id) && displayedIds.has(rel.entity_b_id)) {
        // e.g. Match -> Team or Team -> League
        // Dagre draws Left to Right. We want User -> Match -> Team -> League typically.
        const edgeId = `rel_${rel.id}`;
        addedEdges.add(edgeId);
        
        initialEdges.push({
          id: edgeId,
          source: `entity_${rel.entity_a_id}`,
          target: `entity_${rel.entity_b_id}`,
          label: rel.relation_type,
          style: { stroke: 'hsl(var(--muted-foreground))', strokeWidth: 1.5, strokeDasharray: '3,3' },
          markerEnd: { type: MarkerType.ArrowClosed, color: 'hsl(var(--muted-foreground))' },
        });
      }
    });

    // 2. Edges from User to Entity
    entitiesList.forEach(([entity_id, data]) => {
      const recentEvents = eventsPerEntity.get(entity_id) || [];
      const hasEvents = recentEvents.length > 0;
      
      // If the entity is a "League" and is already connected to from a "Team", maybe skip drawing direct line from user?
      // Actually, let's connect User to EVERYTHING they are interested in, to show their direct score.
      if (data.score > 0 || hasEvents) {
        initialEdges.push({
          id: `edge_user_${entity_id}`,
          source: 'center_user',
          target: `entity_${entity_id}`,
          label: hasEvents ? recentEvents.map(t => getEventLabel(t)).join(', ') : `İlgi: ${data.score.toFixed(1)}`,
          style: { 
            strokeWidth: Math.max(1, Math.min(4, data.score / 4)), 
            stroke: hasEvents ? '#10b981' : '#3b82f6' 
          },
          markerEnd: { type: MarkerType.ArrowClosed, color: hasEvents ? '#10b981' : '#3b82f6' },
          animated: hasEvents,
          type: 'smoothstep'
        });
      }
    });

    // Apply Dagre Layout
    const { layoutedNodes, layoutedEdges } = getLayoutedElements(initialNodes, initialEdges, 'LR');
    setNodes(layoutedNodes);
    setEdges(layoutedEdges);
  };

  const selectedEntityEvents = useMemo(() => {
    if (!selectedEntityId) return [];
    return rawEvents
      .filter(e => e.entity_id === selectedEntityId)
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  }, [selectedEntityId, rawEvents]);

  const selectedEntityInterest = useMemo(() => {
    if (!selectedEntityId) return null;
    return rawInterests.find(i => i.entity_id === selectedEntityId);
  }, [selectedEntityId, rawInterests]);

  const onNodeClick = (_: React.MouseEvent, node: Node) => {
    if (node.id.startsWith('entity_')) {
      const entId = node.id.replace('entity_', '');
      setSelectedEntityId(entId);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
      <div className="bg-card w-full max-w-[90vw] h-[90vh] rounded-2xl shadow-xl border border-border flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        
        <div className="flex items-center justify-between p-6 border-b border-border bg-muted/30 z-10 shrink-0">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-xl">
              <Network className="w-6 h-6 text-primary" />
            </div>
            <div>
              <h2 className="text-xl font-bold">{username} - Knowledge Graph</h2>
              <p className="text-sm text-muted-foreground mt-0.5">Analitik bilgi ağı ve nedensellik şeması</p>
            </div>
          </div>
          
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <label className="text-sm font-medium text-muted-foreground">Limit:</label>
              <select 
                value={maxNodes} 
                onChange={(e) => {
                  setSelectedEntityId(null);
                  setMaxNodes(parseInt(e.target.value));
                }}
                className="px-3 py-1.5 border border-border rounded-md bg-background text-sm font-medium focus:ring-2 focus:ring-primary focus:outline-none"
              >
                <option value={15}>En Önemli 15</option>
                <option value={30}>En Önemli 30</option>
                <option value={50}>En Önemli 50</option>
                <option value={100}>En Önemli 100</option>
                <option value={-1}>Tümü (Ağır)</option>
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

        <div className="flex-1 flex overflow-hidden">
          {/* Main Canvas */}
          <div className={`relative bg-muted/5 transition-all duration-300 ${selectedEntityId ? 'w-2/3 border-r border-border' : 'w-full'}`}>
            {loading ? (
              <div className="absolute inset-0 flex flex-col items-center justify-center text-muted-foreground space-y-3 z-20">
                <Loader2 className="w-8 h-8 animate-spin text-primary" />
                <p>Knowledge Graph Çözümleniyor...</p>
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
                  onNodeClick={onNodeClick}
                  fitView 
                  fitViewOptions={{ padding: 0.1 }}
                  minZoom={0.05}
                  maxZoom={2}
                  nodesDraggable={true}
                  nodesConnectable={false}
                >
                  <Background gap={16} size={1} color="rgba(150,150,150,0.15)" />
                  <Controls className="bg-background border-border fill-foreground" />
                </ReactFlow>
              </div>
            )}
          </div>

          {/* Details Panel Sidebar */}
          {selectedEntityId && (
            <div className="w-1/3 bg-background flex flex-col h-full overflow-hidden animate-in slide-in-from-right-10 duration-300">
              <div className="p-5 border-b border-border bg-muted/10 shrink-0 flex justify-between items-start">
                <div>
                  <h3 className="text-lg font-bold text-foreground break-words max-w-[250px]">{selectedEntityId}</h3>
                  <div className="flex items-center gap-2 mt-2">
                    <span className="px-2.5 py-1 uppercase tracking-wider text-[10px] font-bold bg-primary/10 text-primary rounded-full">
                      {selectedEntityInterest ? TranslateEntityType(selectedEntityInterest.entity_type) : 'Varlık'}
                    </span>
                    {selectedEntityInterest?.interest_score && (
                      <span className="text-sm font-semibold flex items-center gap-1 text-blue-500">
                        <Target className="w-3.5 h-3.5" />
                        {selectedEntityInterest.interest_score.toFixed(1)} Puan
                      </span>
                    )}
                  </div>
                </div>
                <button 
                  onClick={() => setSelectedEntityId(null)}
                  className="p-1.5 text-muted-foreground hover:bg-muted rounded-md"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              <div className="p-5 flex-1 overflow-y-auto space-y-6">
                <div>
                   <h4 className="text-sm font-medium text-foreground flex items-center gap-1.5 mb-3">
                     <Activity className="w-4 h-4 text-emerald-500" />
                     Neden İlişkili? (Etkileşim Geçmişi)
                   </h4>
                   
                   {selectedEntityEvents.length === 0 ? (
                     <div className="p-4 bg-muted/30 rounded-lg text-center border border-border border-dashed">
                       <Info className="w-5 h-5 text-muted-foreground mx-auto mb-2" />
                       <p className="text-xs text-muted-foreground">Son 30 güne ait direkt etkileşim bulunamadı. Bağlantı, dolaylı ilişkilerden kaynaklanıyor olabilir.</p>
                     </div>
                   ) : (
                     <div className="space-y-3">
                       {selectedEntityEvents.map(ev => (
                         <div key={ev.id} className="p-3 bg-card border border-border rounded-lg shadow-sm">
                           <div className="flex justify-between items-start mb-1">
                             <span className="text-sm font-semibold">{getEventLabel(ev.event_type)}</span>
                             <span className="text-[10px] text-muted-foreground flex items-center gap-1">
                               <Clock className="w-3 h-3" />
                               {new Date(ev.created_at).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
                             </span>
                           </div>
                           {ev.metadata && Object.keys(ev.metadata).length > 0 && (
                             <pre className="mt-2 text-[10px] bg-muted/50 p-2 rounded-md overflow-x-auto text-muted-foreground">
                               {JSON.stringify(ev.metadata, null, 2)}
                             </pre>
                           )}
                         </div>
                       ))}
                     </div>
                   )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
