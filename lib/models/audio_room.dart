class AudioRoom {
  final String id;
  final String roomName;
  final String? matchId;
  final String hostId;
  final DateTime createdAt;
  final String status;
  final int listenerCount;
  final bool isPrivate;

  AudioRoom({
    required this.id,
    required this.roomName,
    this.matchId,
    required this.hostId,
    required this.createdAt,
    required this.status,
    required this.listenerCount,
    this.isPrivate = false,
  });

  factory AudioRoom.fromJson(Map<String, dynamic> json) {
    return AudioRoom(
      id: json['id']?.toString() ?? '',
      roomName: json['room_name']?.toString() ?? '',
      matchId: _stringOrNull(json['match_id']),
      hostId: json['host_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: json['status']?.toString() ?? 'inactive',
      listenerCount: _asInt(json['listener_count']),
      isPrivate: _asBool(json['is_private']),
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
      'is_private': isPrivate,
    };
  }
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  if (value is num) return value != 0;
  return false;
}
