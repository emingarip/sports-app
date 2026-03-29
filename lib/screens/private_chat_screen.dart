import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class PrivateChatScreen extends StatefulWidget {
  final String roomId;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatarUrl;
  final bool isBot;

  const PrivateChatScreen({
    super.key,
    required this.roomId,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatarUrl,
    this.isBot = false,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final _supabase = Supabase.instance.client;
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    _subscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await _supabase
          .from('private_messages')
          .select()
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToMessages() {
    _subscription = _supabase
        .channel('public:private_messages:room_${widget.roomId}')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'private_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.roomId,
            ),
            callback: (payload) {
              final newMessage = payload.newRecord;
              if (mounted) {
                setState(() {
                  _messages.add(newMessage);
                });
                _scrollToBottom();
                
                // If it's from the other person, mark as read
                if (newMessage['sender_id'] == widget.otherUserId) {
                  _markAsRead(newMessage['id']);
                }
              }
            })
        .subscribe();
  }

  Future<void> _markMessagesAsRead() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    
    try {
      await _supabase
          .from('private_messages')
          .update({'is_read': true})
          .eq('room_id', widget.roomId)
          .neq('sender_id', myId)
          .eq('is_read', false);
    } catch(e) {
      // Ignore
    }
  }

  Future<void> _markAsRead(String messageId) async {
    try {
      await _supabase
          .from('private_messages')
          .update({'is_read': true})
          .eq('id', messageId);
    } catch(e) {
      // Ignore
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    setState(() => _isSending = true);
    final tempMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'room_id': widget.roomId,
      'sender_id': myId,
      'content': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_read': false,
      'is_temp': true,
    };

    setState(() {
      _messages.add(tempMsg);
      _msgController.clear();
    });
    _scrollToBottom();

    try {
      await _supabase.from('private_messages').insert({
        'room_id': widget.roomId,
        'sender_id': myId,
        'content': text,
      });
      // The Realtime listener will handle pulling down the actual DB record.
      // We could filter out tempMsg but usually the UI handles it smoothly if we just replace or rely on stream.
      // For simplicity, we just reload or let stream add it (it might duplicate if we don't handle temp msg cleanup)
      // Actually, removing temp msg:
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempMsg['id']);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderilemedi: $e')),
      );
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempMsg['id']);
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: context.colors.surfaceContainer,
                  backgroundImage: widget.otherAvatarUrl != null
                      ? NetworkImage(widget.otherAvatarUrl!)
                      : null,
                  child: widget.otherAvatarUrl == null
                      ? Text(widget.otherUsername.substring(0, 1).toUpperCase(), style: TextStyle(color: context.colors.textHigh, fontWeight: FontWeight.bold))
                      : null,
                ),
                if (widget.isBot)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.smart_toy, size: 8, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Text(widget.otherUsername, style: TextStyle(color: context.colors.textHigh, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: context.colors.background,
        elevation: 1,
        shadowColor: Colors.black45,
        iconTheme: IconThemeData(color: context.colors.textHigh),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.blue))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['sender_id'] == _supabase.auth.currentUser?.id;
                      return _buildMessageBubble(msg, isMe);
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? context.colors.primary : context.colors.surfaceContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg['content'] ?? '',
              style: TextStyle(color: isMe ? Colors.white : context.colors.textHigh, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg['created_at']),
                  style: TextStyle(
                    color: isMe ? Colors.white.withOpacity(0.5) : context.colors.textLow,
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg['is_read'] == true ? Icons.done_all : Icons.check,
                    size: 12,
                    color: msg['is_read'] == true ? Colors.blue : (isMe ? Colors.white.withOpacity(0.5) : context.colors.textLow),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String isoTime) {
    try {
      final date = DateTime.parse(isoTime).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        border: Border(top: BorderSide(color: context.colors.surfaceContainerHigh)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgController,
                style: TextStyle(color: context.colors.textHigh),
                decoration: InputDecoration(
                  hintText: 'Mesaj yaz...',
                  hintStyle: TextStyle(color: context.colors.textMedium),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: context.colors.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
