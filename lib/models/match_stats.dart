class MatchStatsReport {
  final String matchId;
  final String status;
  final DateTime? syncedAt;
  final List<MatchStatData> stats;
  final List<MomentumPoint> momentum;
  final int shotmapCount;
  final int bestPlayersCount;

  const MatchStatsReport({
    required this.matchId,
    required this.status,
    required this.syncedAt,
    required this.stats,
    required this.momentum,
    required this.shotmapCount,
    required this.bestPlayersCount,
  });

  bool get hasData =>
      stats.isNotEmpty ||
      momentum.isNotEmpty ||
      shotmapCount > 0 ||
      bestPlayersCount > 0;

  factory MatchStatsReport.fromJson(Map<String, dynamic> json) {
    return MatchStatsReport(
      matchId: json['matchId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'missing',
      syncedAt: _nullableDateTime(json['syncedAt']),
      stats: _asList(json['stats'])
          .map((item) => MatchStatData.fromJson(_asMap(item)))
          .toList(),
      momentum: _asList(json['momentum'])
          .map((item) => MomentumPoint.fromJson(_asMap(item)))
          .toList(),
      shotmapCount: _asInt(json['shotmapCount']),
      bestPlayersCount: _asInt(json['bestPlayersCount']),
    );
  }
}

class MatchStatData {
  final String label;
  final num? homeValue;
  final num? awayValue;
  final String homeDisplay;
  final String awayDisplay;
  final bool isPercentage;

  const MatchStatData({
    required this.label,
    required this.homeValue,
    required this.awayValue,
    required this.homeDisplay,
    required this.awayDisplay,
    required this.isPercentage,
  });

  num get homeNumeric => homeValue ?? 0;
  num get awayNumeric => awayValue ?? 0;
  num get total => isPercentage ? 100 : homeNumeric + awayNumeric;
  double get homeRatio => total == 0 ? 0 : homeNumeric / total;
  double get awayRatio => total == 0 ? 0 : awayNumeric / total;

  factory MatchStatData.fromJson(Map<String, dynamic> json) {
    final homeValue = _nullableNum(json['homeValue']);
    final awayValue = _nullableNum(json['awayValue']);
    return MatchStatData(
      label: json['label']?.toString() ?? '',
      homeValue: homeValue,
      awayValue: awayValue,
      homeDisplay: json['homeDisplay']?.toString() ?? _displayNum(homeValue),
      awayDisplay: json['awayDisplay']?.toString() ?? _displayNum(awayValue),
      isPercentage: json['isPercentage'] == true,
    );
  }
}

class MomentumPoint {
  final int? minute;
  final double value;

  const MomentumPoint({required this.minute, required this.value});

  factory MomentumPoint.fromJson(Map<String, dynamic> json) {
    return MomentumPoint(
      minute: _nullableInt(json['minute']),
      value: (_nullableNum(json['value']) ?? 0).toDouble(),
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

int _asInt(Object? value) => _nullableInt(value) ?? 0;

int? _nullableInt(Object? value) {
  if (value == null || value is bool) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

num? _nullableNum(Object? value) {
  if (value == null || value is bool) return null;
  if (value is num) return value;
  return num.tryParse(value.toString().replaceAll('%', '').trim());
}

String _displayNum(num? value) {
  if (value == null) return '-';
  return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
}

DateTime? _nullableDateTime(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text);
}
