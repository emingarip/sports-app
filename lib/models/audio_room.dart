class AudioRoom {
  final String id;
  final String roomName;
  final String? matchId;
  final String hostId;
  final DateTime createdAt;
  final String status;
  final int listenerCount;

  AudioRoom({
    required this.id,
    required this.roomName,
    this.matchId,
    required this.hostId,
    required this.createdAt,
    required this.status,
    required this.listenerCount,
  });

  factory AudioRoom.fromJson(Map<String, dynamic> json) {
    return AudioRoom(
      id: json['id'] as String,
      roomName: json['room_name'] as String,
      matchId: json['match_id'] as String?,
      hostId: json['host_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String,
      listenerCount: json['listener_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_name': roomName,
      'match_id': matchId,
      'host_id': hostId,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'listener_count': listenerCount,
    };
  }
}
