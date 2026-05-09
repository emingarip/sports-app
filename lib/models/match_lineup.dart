class MatchLineupReport {
  final String matchId;
  final String status;
  final String? providerSlug;
  final bool confirmed;
  final DateTime? syncedAt;
  final TeamLineup home;
  final TeamLineup away;
  final List<LineupSubstitution> substitutions;
  final Map<String, dynamic> summary;

  const MatchLineupReport({
    required this.matchId,
    required this.status,
    required this.providerSlug,
    required this.confirmed,
    required this.syncedAt,
    required this.home,
    required this.away,
    required this.substitutions,
    required this.summary,
  });

  bool get hasLineups =>
      home.starters.isNotEmpty ||
      away.starters.isNotEmpty ||
      substitutions.isNotEmpty;

  factory MatchLineupReport.fromJson(Map<String, dynamic> json) {
    return MatchLineupReport(
      matchId: json['match_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'missing',
      providerSlug: _nullableString(json['provider_slug']),
      confirmed: json['confirmed'] == true,
      syncedAt: _nullableDateTime(json['synced_at']),
      home: TeamLineup.fromJson(_asMap(json['home'])),
      away: TeamLineup.fromJson(_asMap(json['away'])),
      substitutions: _asList(json['substitutions'])
          .map((item) => LineupSubstitution.fromJson(_asMap(item)))
          .toList(),
      summary: _asMap(json['summary']),
    );
  }
}

class LineupSubstitution {
  final int? minute;
  final int? addedTime;
  final bool? isHome;
  final String? teamName;
  final String? playerInName;
  final String? playerInId;
  final String? playerOutName;
  final String? playerOutId;

  const LineupSubstitution({
    required this.minute,
    required this.addedTime,
    required this.isHome,
    required this.teamName,
    required this.playerInName,
    required this.playerInId,
    required this.playerOutName,
    required this.playerOutId,
  });

  String get minuteLabel {
    if (minute == null) return '';
    if (addedTime != null && addedTime! > 0) {
      return "$minute+$addedTime'";
    }
    return "$minute'";
  }

  factory LineupSubstitution.fromJson(Map<String, dynamic> json) {
    return LineupSubstitution(
      minute: _nullableInt(json['minute']),
      addedTime: _nullableInt(json['added_time']),
      isHome: json['is_home'] is bool ? json['is_home'] as bool : null,
      teamName: _nullableString(json['team_name']),
      playerInName: _nullableString(json['player_in_name']),
      playerInId: _nullableString(json['player_in_id']),
      playerOutName: _nullableString(json['player_out_name']),
      playerOutId: _nullableString(json['player_out_id']),
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

int? _nullableInt(Object? value) {
  if (value == null || value is bool) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
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
