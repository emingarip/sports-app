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
  final LineupFormationAnalysis? formationAnalysis;
  final TacticalBalance? tacticalBalance;
  final FormationPairStatistics? formationStatistics;

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
    required this.formationAnalysis,
    required this.tacticalBalance,
    required this.formationStatistics,
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
      formationAnalysis:
          LineupFormationAnalysis.fromJsonOrNull(json['formation_analysis']),
      tacticalBalance: TacticalBalance.fromJsonOrNull(json['tactical_balance']),
      formationStatistics:
          FormationPairStatistics.fromJsonOrNull(json['formation_statistics']),
    );
  }
}

class FormationPairStatistics {
  final String homeFormation;
  final String awayFormation;
  final int sampleSize;
  final int minReliableSampleSize;
  final double avgTotalGoals;
  final double over25Rate;
  final double bttsRate;
  final FormationResultStatistics result;
  final FormationPeriodStatistics? firstHalf;
  final FormationPeriodStatistics? secondHalf;

  const FormationPairStatistics({
    required this.homeFormation,
    required this.awayFormation,
    required this.sampleSize,
    required this.minReliableSampleSize,
    required this.avgTotalGoals,
    required this.over25Rate,
    required this.bttsRate,
    required this.result,
    required this.firstHalf,
    required this.secondHalf,
  });

  bool get hasReliableSample => sampleSize >= minReliableSampleSize;

  static FormationPairStatistics? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    if (json.isEmpty) return null;
    final result = FormationResultStatistics.fromJsonOrNull(json['result']);
    if (result == null) return null;
    return FormationPairStatistics(
      homeFormation: _nullableString(json['home_formation']) ?? '',
      awayFormation: _nullableString(json['away_formation']) ?? '',
      sampleSize: _asInt(json['sample_size']),
      minReliableSampleSize: _asInt(json['min_reliable_sample_size']),
      avgTotalGoals: _asDouble(json['avg_total_goals']),
      over25Rate: _asDouble(json['over_25_rate']),
      bttsRate: _asDouble(json['btts_rate']),
      result: result,
      firstHalf: FormationPeriodStatistics.fromJsonOrNull(json['first_half']),
      secondHalf: FormationPeriodStatistics.fromJsonOrNull(json['second_half']),
    );
  }
}

class FormationResultStatistics {
  final double homeWinRate;
  final double drawRate;
  final double awayWinRate;
  final double homeAvgGoals;
  final double awayAvgGoals;
  final double avgGoalDiff;

  const FormationResultStatistics({
    required this.homeWinRate,
    required this.drawRate,
    required this.awayWinRate,
    required this.homeAvgGoals,
    required this.awayAvgGoals,
    required this.avgGoalDiff,
  });

  static FormationResultStatistics? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    if (json.isEmpty) return null;
    return FormationResultStatistics(
      homeWinRate: _asDouble(json['home_win_rate']),
      drawRate: _asDouble(json['draw_rate']),
      awayWinRate: _asDouble(json['away_win_rate']),
      homeAvgGoals: _asDouble(json['home_avg_goals']),
      awayAvgGoals: _asDouble(json['away_avg_goals']),
      avgGoalDiff: _asDouble(json['avg_goal_diff']),
    );
  }
}

class FormationPeriodStatistics {
  final double avgGoals;
  final double over05Rate;
  final double over15Rate;
  final double homeAvgGoals;
  final double awayAvgGoals;

  const FormationPeriodStatistics({
    required this.avgGoals,
    required this.over05Rate,
    required this.over15Rate,
    required this.homeAvgGoals,
    required this.awayAvgGoals,
  });

  static FormationPeriodStatistics? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    if (json.isEmpty) return null;
    return FormationPeriodStatistics(
      avgGoals: _asDouble(json['avg_goals']),
      over05Rate: _asDouble(json['over_05_rate']),
      over15Rate: _asDouble(json['over_15_rate']),
      homeAvgGoals: _asDouble(json['home_avg_goals']),
      awayAvgGoals: _asDouble(json['away_avg_goals']),
    );
  }
}

class TacticalBalance {
  final TacticalBalanceSide home;
  final TacticalBalanceSide away;
  final int sampleSize;
  final double confidence;
  final String? confidenceLabel;
  final String? explanation;

  const TacticalBalance({
    required this.home,
    required this.away,
    required this.sampleSize,
    required this.confidence,
    required this.confidenceLabel,
    required this.explanation,
  });

  static TacticalBalance? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    if (json.isEmpty) return null;
    final home = TacticalBalanceSide.fromJsonOrNull(json['home']);
    final away = TacticalBalanceSide.fromJsonOrNull(json['away']);
    if (home == null || away == null) return null;
    return TacticalBalance(
      home: home,
      away: away,
      sampleSize: _asInt(json['sample_size']),
      confidence: _asDouble(json['confidence']),
      confidenceLabel: _nullableString(json['confidence_label']),
      explanation: _nullableString(json['explanation']),
    );
  }
}

class TacticalBalanceSide {
  final String? formation;
  final double score;
  final String label;

  const TacticalBalanceSide({
    required this.formation,
    required this.score,
    required this.label,
  });

  static TacticalBalanceSide? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    if (json.isEmpty) return null;
    return TacticalBalanceSide(
      formation: _nullableString(json['formation']),
      score: _asDouble(json['score']),
      label: _nullableString(json['label']) ?? 'veri yok',
    );
  }
}

class LineupFormationAnalysis {
  final String status;
  final String? engine;
  final String? promptVersion;
  final DateTime? generatedAt;
  final LineupFormationTeamAnalysis home;
  final LineupFormationTeamAnalysis away;
  final String comparison;

  const LineupFormationAnalysis({
    required this.status,
    required this.engine,
    required this.promptVersion,
    required this.generatedAt,
    required this.home,
    required this.away,
    required this.comparison,
  });

  static LineupFormationAnalysis? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    if (json.isEmpty) return null;
    final home = LineupFormationTeamAnalysis.fromJsonOrNull(json['home']);
    final away = LineupFormationTeamAnalysis.fromJsonOrNull(json['away']);
    final comparison = _nullableString(json['comparison']);
    if (home == null || away == null || comparison == null) return null;
    return LineupFormationAnalysis(
      status: json['status']?.toString() ?? 'sent',
      engine: _nullableString(json['engine']),
      promptVersion: _nullableString(json['prompt_version']),
      generatedAt: _nullableDateTime(json['generated_at']),
      home: home,
      away: away,
      comparison: comparison,
    );
  }
}

class LineupFormationTeamAnalysis {
  final String purpose;
  final String plan;
  final String risk;

  const LineupFormationTeamAnalysis({
    required this.purpose,
    required this.plan,
    required this.risk,
  });

  static LineupFormationTeamAnalysis? fromJsonOrNull(Object? value) {
    final json = _asMap(value);
    final purpose = _nullableString(json['purpose']);
    final plan = _nullableString(json['plan']);
    final risk = _nullableString(json['risk']);
    if (purpose == null || plan == null || risk == null) return null;
    return LineupFormationTeamAnalysis(
      purpose: purpose,
      plan: plan,
      risk: risk,
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

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
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
