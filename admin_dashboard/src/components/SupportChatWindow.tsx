import { useEffect, useState, useRef, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { Send, User, Loader2, Check, CheckCheck, X } from 'lucide-react';

interface Message {
  id: string;
  content: string;
  sender_id: string;
  is_read: boolean;
  created_at: string;
  sender_username: string;
}

interface Conversation {
  room_id: string;
  other_user_id: string;
}

const SUPPORT_ID = '00000000-0000-0000-0000-000000000999';

interface SupportChatWindowProps {
  readonly targetUserId: string;
  readonly targetUserName?: string;
  readonly onClose: () => void;
}

export default function SupportChatWindow({ targetUserId, targetUserName, onClose }: SupportChatWindowProps) {
  const [roomId, setRoomId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const fetchMessages = useCallback(async (id: string) => {
    try {
      const { data, error } = await supabase.rpc('admin_get_support_messages', { p_room_id: id });
      if (error) throw error;
      setMessages(data || []);
    } catch (error) {
      console.error('Error fetching messages:', error);
    }
  }, []);

  const initChat = useCallback(async () => {
    setLoading(true);
    try {
      const { data: convs, error } = await supabase.rpc('admin_get_support_conversations');
      if (error) throw error;
      
      const existing = (convs as Conversation[])?.find(c => c.other_user_id === targetUserId);
      if (existing) {
        setRoomId(existing.room_id);
        await fetchMessages(existing.room_id);
      } else {
        setRoomId(null);
        setMessages([]);
      }
    } catch (error) {
      console.error('Error initializing chat:', error);
    } finally {
      setLoading(false);
    }
  }, [targetUserId, fetchMessages]);

  useEffect(() => {
    initChat();
  }, [initChat]);

  useEffect(() => {
    if (roomId) {
      const roomChannel = supabase
        .channel(`modal_room_${roomId}`)
        .on(
          'postgres_changes',
          { 
            event: 'INSERT', 
            schema: 'public', 
            table: 'private_messages',
            filter: `room_id=eq.${roomId}`
          },
          () => {
             fetchMessages(roomId);
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(roomChannel);
      };
    }
  }, [roomId, fetchMessages]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSend = async (e?: React.SyntheticEvent) => {
    e?.preventDefault();
    if (!newMessage.trim()) return;

    const content = newMessage.trim();
    setNewMessage('');

    try {
      const { data: newRoomId, error } = await supabase.rpc('admin_send_support_message', {
        p_content: content,
        p_room_id: roomId || null,
        p_target_user_id: roomId ? null : targetUserId
      });

      if (error) throw error;
      
      if (!roomId && newRoomId) {
        setRoomId(newRoomId);
        fetchMessages(newRoomId);
      } else if (roomId) {
        fetchMessages(roomId);
      }
    } catch (error) {
      console.error('Error sending message:', error);
      alert('Mesaj gönderilemedi.');
    }
  };

  const renderContent = () => {
    if (loading) {
      return (
        <div className="flex justify-center items-center h-full">
          <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
        </div>
      );
    }

    if (messages.length === 0) {
      return (
        <div className="h-full flex flex-col items-center justify-center text-center p-6 text-muted-foreground">
          <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mb-3">
            <Send className="w-6 h-6 rotate-45 -translate-y-0.5" />
          </div>
          <p className="text-sm font-medium">Sohbeti başlatmak için bir mesaj yazın.</p>
          <p className="text-xs">Kullanıcıya sistem üzerinden anlık bildirim gidecektir.</p>
        </div>
      );
    }

    return (
      <div className="space-y-4">
        {messages.map((m) => {
          const isMe = m.sender_id === SUPPORT_ID;
          return (
            <div key={m.id} className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}>
              <div className="max-w-[85%]">
                <div className={`p-3 rounded-2xl text-sm shadow-sm ${
                  isMe 
                    ? 'bg-primary text-primary-foreground rounded-tr-none' 
                    : 'bg-card border border-border rounded-tl-none'
                }`}>
                  {m.content}
                  <div className={`flex items-center gap-1 mt-1 justify-end ${isMe ? 'text-primary-foreground/70' : 'text-muted-foreground'} text-[9px]`}>
                    {new Date(m.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}
                    {isMe && (
                      m.is_read ? <CheckCheck className="w-3 h-3" /> : <Check className="w-3 h-3" />
                    )}
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    );
  };

  return (
    <div className="flex flex-col h-[600px] w-full max-w-2xl bg-card border border-border rounded-2xl shadow-2xl overflow-hidden animate-in fade-in zoom-in duration-200">
      {/* Header */}
      <div className="p-4 border-b border-border flex items-center justify-between bg-muted/30 backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center ring-1 ring-primary/20">
            <User className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h3 className="font-bold text-sm leading-tight">{targetUserName || 'Destek Sohbeti'}</h3>
            <div className="flex items-center gap-1.5 mt-0.5">
              <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse"></span>
              <span className="text-[10px] text-muted-foreground font-semibold uppercase tracking-wider">Müşteri Destek</span>
            </div>
          </div>
        </div>
        <button 
          onClick={onClose}
          className="p-2 hover:bg-muted rounded-full transition-all text-muted-foreground hover:text-foreground active:scale-90"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 bg-muted/5 scrollbar-hide">
        {renderContent()}
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div className="p-4 border-t border-border bg-card">
        <form onSubmit={handleSend} className="flex gap-2">
          <input
            type="text"
            placeholder="Mesajınızı yazın..."
            value={newMessage}
            onChange={(e) => setNewMessage(e.target.value)}
            className="flex-1 px-4 py-2.5 bg-muted/20 border border-border rounded-full focus:outline-none focus:ring-1 focus:ring-primary focus:bg-background transition-all text-sm"
          />
          <button
            type="submit"
            disabled={!newMessage.trim()}
            className="w-10 h-10 bg-primary text-primary-foreground rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition-transform disabled:opacity-50 shadow-lg shadow-primary/20 flex-shrink-0"
          >
            <Send className="w-5 h-5 ml-0.5" />
          </button>
        </form>
      </div>
    </div>
  );
}
