class ChatMessage {
  final String sender;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
  });
}

class EmojiReaction {
  final String id;
  final String emoji;
  final String sender;

  EmojiReaction({
    required this.id,
    required this.emoji,
    required this.sender,
  });
}
