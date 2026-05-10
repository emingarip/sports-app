class MatchTimelineReport {
  final String matchId;
  final String status;
  final int? minute;
  final MatchTimelineScore score;
  final DateTime? syncedAt;
  final List<MatchTimelineEvent> events;

  const MatchTimelineReport({
    required this.matchId,
    required this.status,
    required this.minute,
    required this.score,
    required this.syncedAt,
    required this.events,
  });

  factory MatchTimelineReport.fromJson(Map<String, dynamic> json) {
    return MatchTimelineReport(
      matchId: json['matchId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'missing',
      minute: _nullableInt(json['minute']),
      score: MatchTimelineScore.fromJson(_asMap(json['score'])),
      syncedAt: _nullableDateTime(json['syncedAt']),
      events: _asList(json['events'])
          .map((item) => MatchTimelineEvent.fromJson(_asMap(item)))
          .toList(),
    );
  }
}

class MatchTimelineScore {
  final int? home;
  final int? away;

  const MatchTimelineScore({required this.home, required this.away});

  bool get hasScore => home != null && away != null;
  String get display => hasScore ? '$home - $away' : 'Skor yok';

  factory MatchTimelineScore.fromJson(Map<String, dynamic> json) {
    return MatchTimelineScore(
      home: _nullableInt(json['home']),
      away: _nullableInt(json['away']),
    );
  }
}

class MatchTimelineEvent {
  final String id;
  final String type;
  final int? minute;
  final int? extraMinute;
  final String? team;
  final String title;
  final String description;
  final String? playerName;
  final String? assistName;
  final String? score;
  final String importance;

  const MatchTimelineEvent({
    required this.id,
    required this.type,
    required this.minute,
    required this.extraMinute,
    required this.team,
    required this.title,
    required this.description,
    required this.playerName,
    required this.assistName,
    required this.score,
    required this.importance,
  });

  String get minuteLabel {
    if (minute == null) return '';
    if (extraMinute != null && extraMinute! > 0) {
      return "$minute+$extraMinute'";
    }
    return "$minute'";
  }

  factory MatchTimelineEvent.fromJson(Map<String, dynamic> json) {
    return MatchTimelineEvent(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'EVENT',
      minute: _nullableInt(json['minute']),
      extraMinute: _nullableInt(json['extraMinute']),
      team: json['team']?.toString(),
      title: json['title']?.toString() ?? 'Olay',
      description: json['description']?.toString() ?? '',
      playerName: json['playerName']?.toString(),
      assistName: json['assistName']?.toString(),
      score: json['score']?.toString(),
      importance: json['importance']?.toString() ?? 'normal',
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

int? _nullableInt(Object? value) {
  if (value == null || value is bool) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _nullableDateTime(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text);
}
