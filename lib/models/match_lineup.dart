class MatchLineupReport {
  final String matchId;
  final String status;
  final String? providerSlug;
  final bool confirmed;
  final DateTime? syncedAt;
  final TeamLineup home;
  final TeamLineup away;
  final Map<String, dynamic> summary;

  const MatchLineupReport({
    required this.matchId,
    required this.status,
    required this.providerSlug,
    required this.confirmed,
    required this.syncedAt,
    required this.home,
    required this.away,
    required this.summary,
  });

  bool get hasLineups => home.starters.isNotEmpty || away.starters.isNotEmpty;

  factory MatchLineupReport.fromJson(Map<String, dynamic> json) {
    return MatchLineupReport(
      matchId: json['match_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'missing',
      providerSlug: _nullableString(json['provider_slug']),
      confirmed: json['confirmed'] == true,
      syncedAt: _nullableDateTime(json['synced_at']),
      home: TeamLineup.fromJson(_asMap(json['home'])),
      away: TeamLineup.fromJson(_asMap(json['away'])),
      summary: _asMap(json['summary']),
    );
  }
}

class TeamLineup {
  final LineupTeam team;
  final String? formation;
  final List<LineupPlayer> starters;
  final List<LineupPlayer> bench;

  const TeamLineup({
    required this.team,
    required this.formation,
    required this.starters,
    required this.bench,
  });

  factory TeamLineup.fromJson(Map<String, dynamic> json) {
    return TeamLineup(
      team: LineupTeam.fromJson(_asMap(json['team'])),
      formation: _nullableString(json['formation']),
      starters: _asList(json['starters'])
          .map((item) => LineupPlayer.fromJson(_asMap(item)))
          .toList(),
      bench: _asList(json['bench'])
          .map((item) => LineupPlayer.fromJson(_asMap(item)))
          .toList(),
    );
  }
}

class LineupTeam {
  final String id;
  final String name;
  final String? shortName;

  const LineupTeam({
    required this.id,
    required this.name,
    required this.shortName,
  });

  factory LineupTeam.fromJson(Map<String, dynamic> json) {
    return LineupTeam(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortName: _nullableString(json['short_name']),
    );
  }
}

class LineupPlayer {
  final String playerId;
  final String? providerPlayerId;
  final String name;
  final String? shortName;
  final String? position;
  final String? shirtNumber;
  final bool isStarting;
  final bool isBench;
  final bool isCaptain;
  final int sortOrder;
  final Map<String, dynamic> statistics;

  const LineupPlayer({
    required this.playerId,
    required this.providerPlayerId,
    required this.name,
    required this.shortName,
    required this.position,
    required this.shirtNumber,
    required this.isStarting,
    required this.isBench,
    required this.isCaptain,
    required this.sortOrder,
    required this.statistics,
  });

  factory LineupPlayer.fromJson(Map<String, dynamic> json) {
    return LineupPlayer(
      playerId: json['player_id']?.toString() ?? '',
      providerPlayerId: _nullableString(json['provider_player_id']),
      name: json['name']?.toString() ?? '',
      shortName: _nullableString(json['short_name']),
      position: _nullableString(json['position']),
      shirtNumber: _nullableString(json['shirt_number']),
      isStarting: json['is_starting'] == true,
      isBench: json['is_bench'] == true,
      isCaptain: json['is_captain'] == true,
      sortOrder: _asInt(json['sort_order']),
      statistics: _asMap(json['statistics']),
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

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}

DateTime? _nullableDateTime(Object? value) {
  final text = _nullableString(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}
