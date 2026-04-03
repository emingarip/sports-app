import { useEffect, useState, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { Search, Send, User, Loader2, MessageSquare, Check, CheckCheck, X } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';

interface Conversation {
  room_id: string;
  last_message: string;
  last_message_at: string;
  unread_count: number;
  other_user_id: string;
  other_username: string;
  other_avatar_url: string;
}

interface Message {
  id: string;
  content: string;
  sender_id: string;
  is_read: boolean;
  created_at: string;
  sender_username: string;
}

interface Feedback {
  id: string;
  user_id: string;
  feedback_type: string;
  message: string;
  status: string;
  created_at: string;
  profiles?: {
    full_name: string;
    avatar_url: string;
  };
}

const SUPPORT_ID = '00000000-0000-0000-0000-000000000999';

export default function SupportChat() {
  const [searchParams, setSearchParams] = useSearchParams();
  const initialRoomId = searchParams.get('room_id');
  const targetUserId = searchParams.get('user_id');

  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [feedbacks, setFeedbacks] = useState<Feedback[]>([]);
  const [selectedRoom, setSelectedRoom] = useState<string | null>(initialRoomId);
  const [messages, setMessages] = useState<Message[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchConversations();
    fetchFeedbacks();

    // Subscribe to new messages globally to update conversation list
    const channel = supabase
      .channel('support_chat_global')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'private_messages' },
        () => {
          fetchConversations();
        }
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'feedbacks' },
        () => {
          fetchFeedbacks();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  useEffect(() => {
    if (selectedRoom) {
      fetchMessages(selectedRoom);
      
      // Subscribe to room-specific messages
      const roomChannel = supabase
        .channel(`room_${selectedRoom}`)
        .on(
          'postgres_changes',
          { 
            event: 'INSERT', 
            schema: 'public', 
            table: 'private_messages',
            filter: `room_id=eq.${selectedRoom}`
          },
          () => {
             fetchMessages(selectedRoom);
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(roomChannel);
      };
    }
  }, [selectedRoom]);

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const fetchConversations = async () => {
    try {
      const { data, error } = await supabase.rpc('admin_get_support_conversations');
      if (error) throw error;
      setConversations(data || []);
      
      // If we have a targetUserId (from Feedbacks page), check if a room exists or we need to highlight it
      if (targetUserId && !selectedRoom) {
        const existing = (data as Conversation[])?.find(c => c.other_user_id === targetUserId);
        if (existing) {
          setSelectedRoom(existing.room_id);
        }
      }
    } catch (error) {
      console.error('Error fetching conversations:', error);
    } finally {
      if (!feedbacks.length) setLoading(false);
    }
  };

  const fetchFeedbacks = async () => {
    try {
      const { data, error } = await supabase
        .from('feedbacks')
        .select(`
          *,
          profiles:user_id (
            full_name,
            avatar_url
          )
        `)
        .in('status', ['new', 'in_progress'])
        .order('created_at', { ascending: false });

      if (error) throw error;
      setFeedbacks(data || []);
    } catch (error) {
      console.error('Error fetching feedbacks:', error);
    } finally {
      setLoading(false);
    }
  };

  const fetchMessages = async (roomId: string) => {
    setMessagesLoading(true);
    try {
      const { data, error } = await supabase.rpc('admin_get_support_messages', { p_room_id: roomId });
      if (error) throw error;
      setMessages(data || []);
      
      // Mark as read in local list too
      setConversations(prev => prev.map(c => 
        c.room_id === roomId ? { ...c, unread_count: 0 } : c
      ));
    } catch (error) {
      console.error('Error fetching messages:', error);
    } finally {
      setMessagesLoading(false);
    }
  };

  const handleSend = async (e?: React.SyntheticEvent) => {
    e?.preventDefault();
    if (!newMessage.trim()) return;

    let roomId = selectedRoom;
    const content = newMessage.trim();
    setNewMessage('');

    try {
      const { data: roomIdResult, error } = await supabase.rpc('admin_send_support_message', {
        p_content: content,
        p_room_id: roomId || null,
        p_target_user_id: roomId ? null : targetUserId
      });

      if (error) throw error;
      
      if (!roomId && roomIdResult) {
        setSelectedRoom(roomIdResult);
        fetchConversations();
      } else if (roomId) {
        // fetchMessages will trigger via subscription or manually
        fetchMessages(roomId);
        fetchConversations();
      }
    } catch (error) {
      console.error('Error sending message:', error);
      alert('Mesaj gönderilemedi.');
    }
  };

  const getFeedbackTypeColor = (type: string) => {
    switch (type) {
      case 'bug': return 'bg-red-500/10 text-red-500';
      case 'feature': return 'bg-blue-500/10 text-blue-500';
      default: return 'bg-green-500/10 text-green-500';
    }
  };

  const getStatusColor = (status: string) => {
    return status === 'new' ? 'bg-yellow-500/10 text-yellow-500' : 'bg-blue-500/10 text-blue-500';
  };

  const filteredConversations = conversations.filter(c => 
    c.other_username.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.last_message?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const selectedConv = conversations.find(c => c.room_id === selectedRoom || c.other_user_id === targetUserId);
  const targetUserFromFeedback = feedbacks.find(f => f.user_id === targetUserId);

  if (loading && conversations.length === 0 && feedbacks.length === 0) {
    return (
      <div className="flex justify-center items-center h-full">
        <Loader2 className="w-10 h-10 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="h-[calc(100vh-140px)] flex border border-border bg-card rounded-2xl overflow-hidden shadow-sm">
      {/* Sidebar */}
      <div className="w-80 border-r border-border flex flex-col bg-muted/20">
        <div className="p-4 border-b border-border space-y-4">
          <h2 className="text-xl font-bold flex items-center gap-2">
            <MessageSquare className="w-5 h-5 text-primary" />
            Destek Sohbetleri
          </h2>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <input
              type="text"
              placeholder="Sohbet ara..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-9 pr-4 py-2 border border-border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary text-sm"
            />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {filteredConversations.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground text-sm">
              Sohbet bulunamadı.
            </div>
          ) : (
            filteredConversations.map((c) => (
              <button
                key={c.room_id}
                type="button"
                onClick={() => setSelectedRoom(c.room_id)}
                className={`w-full p-4 flex items-center gap-3 text-left border-b border-border/50 transition-colors ${
                  selectedRoom === c.room_id ? 'bg-primary/5 border-l-4 border-l-primary' : 'hover:bg-muted/50'
                }`}
              >
                <div className="relative flex-shrink-0">
                  {c.other_avatar_url ? (
                    <img src={c.other_avatar_url} alt={c.other_username} className="w-12 h-12 rounded-full object-cover border border-border" />
                  ) : (
                    <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                      <User className="w-6 h-6 text-primary" />
                    </div>
                  )}
                  {c.unread_count > 0 && (
                    <span className="absolute -top-1 -right-1 w-5 h-5 bg-primary text-primary-foreground text-[10px] font-bold rounded-full flex items-center justify-center ring-2 ring-background">
                      {c.unread_count}
                    </span>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex justify-between items-baseline mb-1">
                    <h3 className="font-semibold text-sm truncate pr-2">{c.other_username}</h3>
                    <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                      {new Date(c.last_message_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground truncate italic">
                    {c.last_message || 'Henüz mesaj yok'}
                  </p>
                </div>
              </button>
            ))
          )}
        </div>
      </div>

      {/* Chat Area */}
      <div className="flex-1 flex flex-col bg-background">
        {selectedRoom || targetUserId ? (
          <>
            {/* Header */}
            <div className="p-4 border-b border-border flex items-center justify-between bg-card">
              <div className="flex items-center gap-3">
                {selectedConv?.other_avatar_url ? (
                  <img src={selectedConv.other_avatar_url} alt={selectedConv.other_username} className="w-10 h-10 rounded-full object-cover" />
                ) : (
                  <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                    <User className="w-5 h-5 text-primary" />
                  </div>
                )}
                <div>
                  <h3 className="font-bold">
                    {selectedConv?.other_username || 
                     targetUserFromFeedback?.profiles?.full_name || 
                     'Yeni Sohbet'}
                  </h3>
                  <div className="flex items-center gap-1.5">
                    <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                    <span className="text-[11px] text-muted-foreground font-medium uppercase tracking-wider">Çevrimiçi</span>
                  </div>
                </div>
              </div>

              <button
                onClick={() => {
                  setSelectedRoom(null);
                  setSearchParams({});
                }}
                className="p-2 hover:bg-muted rounded-full transition-colors text-muted-foreground hover:text-foreground"
                title="Sohbeti Kapat"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto p-6 space-y-4 bg-muted/5 scrollbar-hide">
              {messagesLoading && messages.length === 0 ? (
                <div className="flex justify-center p-4">
                  <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
                </div>
              ) : (
                messages.map((m) => {
                  const isMe = m.sender_id === SUPPORT_ID;
                  return (
                    <div key={m.id} className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}>
                      <div className={`max-w-[70%] group`}>
                        <div className={`p-3 rounded-2xl text-sm shadow-sm relative ${
                          isMe 
                            ? 'bg-primary text-primary-foreground rounded-tr-none' 
                            : 'bg-card border border-border rounded-tl-none'
                        }`}>
                          {m.content}
                          <div className={`flex items-center gap-1 mt-1 justify-end ${isMe ? 'text-primary-foreground/70' : 'text-muted-foreground'} text-[10px]`}>
                            {new Date(m.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}
                            {isMe && (
                              m.is_read ? <CheckCheck className="w-3 h-3" /> : <Check className="w-3 h-3" />
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                })
              )}
              <div ref={messagesEndRef} />
            </div>

            {/* Input */}
            <div className="p-4 border-t border-border bg-card">
              <form onSubmit={handleSend} className="flex gap-3">
                <input
                  type="text"
                  placeholder="Mesajınızı yazın..."
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  className="flex-1 px-4 py-2 bg-muted/30 border border-border rounded-full focus:outline-none focus:ring-2 focus:ring-primary focus:bg-background transition-all text-sm"
                />
                <button
                  type="submit"
                  disabled={!newMessage.trim()}
                  className="w-10 h-10 bg-primary text-primary-foreground rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition-transform disabled:opacity-50 shadow-lg shadow-primary/20"
                >
                  <Send className="w-5 h-5 ml-0.5" />
                </button>
              </form>
            </div>
          </>
        ) : (
          <div className="flex-1 flex flex-col p-6 overflow-hidden">
            <div className="flex items-center justify-between mb-6">
              <div>
                <h2 className="text-2xl font-bold">Aktif Destek Talepleri</h2>
                <p className="text-muted-foreground text-sm">Yanıt bekleyen veya incelenen tüm bildirimler</p>
              </div>
              <div className="flex items-center gap-2 px-3 py-1 bg-primary/10 text-primary rounded-full text-xs font-bold ring-1 ring-primary/20">
                <Loader2 className={`w-3 h-3 animate-spin ${loading ? 'opacity-100' : 'opacity-0'}`} />
                {feedbacks.length} Aktif Talep
              </div>
            </div>

            <div className="flex-1 border border-border rounded-xl bg-card overflow-hidden shadow-sm">
              <div className="overflow-x-auto h-full">
                <table className="w-full text-sm text-left border-collapse">
                  <thead className="bg-muted/50 sticky top-0 z-10">
                    <tr>
                      <th className="p-4 font-semibold text-muted-foreground border-b border-border">Kullanıcı</th>
                      <th className="p-4 font-semibold text-muted-foreground border-b border-border">Mesaj</th>
                      <th className="p-4 font-semibold text-muted-foreground border-b border-border">Tür</th>
                      <th className="p-4 font-semibold text-muted-foreground border-b border-border">Durum</th>
                      <th className="p-4 font-semibold text-muted-foreground border-b border-border">Tarih</th>
                      <th className="p-4 font-semibold text-muted-foreground border-b border-border text-center">İşlem</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {feedbacks.length === 0 ? (
                      <tr>
                        <td colSpan={6} className="p-12 text-center text-muted-foreground italic">
                           Şu an için aktif bir destek talebi bulunmuyor.
                        </td>
                      </tr>
                    ) : (
                      feedbacks.map((f) => (
                        <tr key={f.id} className="hover:bg-muted/30 transition-colors group">
                          <td className="p-4">
                            <div className="flex items-center gap-3">
                              {f.profiles?.avatar_url ? (
                                <img src={f.profiles.avatar_url} alt={f.profiles.full_name} className="w-8 h-8 rounded-full object-cover" />
                              ) : (
                                <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                                  <User className="w-4 h-4 text-primary" />
                                </div>
                              )}
                              <span className="font-medium">{f.profiles?.full_name || 'Bilinmeyen'}</span>
                            </div>
                          </td>
                          <td className="p-4">
                            <p className="max-w-xs truncate text-muted-foreground" title={f.message}>
                              {f.message}
                            </p>
                          </td>
                          <td className="p-4">
                            <span className={`px-2 py-1 rounded text-[10px] font-bold uppercase ${getFeedbackTypeColor(f.feedback_type)}`}>
                              {f.feedback_type}
                            </span>
                          </td>
                          <td className="p-4">
                            <span className={`px-2 py-1 rounded text-[10px] font-bold uppercase ${getStatusColor(f.status)}`}>
                              {f.status === 'new' ? 'YENİ' : 'İNCELENİYOR'}
                            </span>
                          </td>
                          <td className="p-4 text-xs text-muted-foreground">
                            {new Date(f.created_at).toLocaleDateString('tr-TR')}
                          </td>
                          <td className="p-4 text-center">
                            <button
                              onClick={() => {
                                setSearchParams({ user_id: f.user_id });
                              }}
                              className="px-4 py-1.5 bg-primary text-primary-foreground rounded-lg text-xs font-bold hover:scale-105 active:scale-95 transition-transform shadow-sm"
                            >
                              Yanıtla
                            </button>
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
