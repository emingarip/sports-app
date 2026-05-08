class WizardInsightReport {
  final WizardMatchSummary match;
  final String decision;
  final int confidence;
  final String riskLevel;
  final String summary;
  final List<WizardCard> cards;
  final List<WizardMarketSignal> markets;
  final List<WizardQuestion> questions;
  final String engine;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final bool stale;

  const WizardInsightReport({
    required this.match,
    required this.decision,
    required this.confidence,
    required this.riskLevel,
    required this.summary,
    required this.cards,
    required this.markets,
    required this.questions,
    required this.engine,
    required this.generatedAt,
    required this.expiresAt,
    required this.stale,
  });

  factory WizardInsightReport.fromJson(Map<String, dynamic> json) {
    return WizardInsightReport(
      match: WizardMatchSummary.fromJson(_asMap(json['match'])),
      decision: json['decision']?.toString() ?? 'WATCH',
      confidence: _asInt(json['confidence']),
      riskLevel: json['riskLevel']?.toString() ?? 'medium',
      summary: json['summary']?.toString() ?? '',
      cards: _asList(json['cards'])
          .map((item) => WizardCard.fromJson(_asMap(item)))
          .toList(),
      markets: _asList(json['markets'])
          .map((item) => WizardMarketSignal.fromJson(_asMap(item)))
          .toList(),
      questions: _asList(json['questions'])
          .map((item) => WizardQuestion.fromJson(_asMap(item)))
          .toList(),
      engine: json['engine']?.toString() ?? 'rules',
      generatedAt: _asDateTime(json['generatedAt']),
      expiresAt: _asDateTime(json['expiresAt']),
      stale: json['stale'] == true,
    );
  }
}

class WizardMatchSummary {
  final String id;
  final String homeTeam;
  final String awayTeam;
  final String? leagueName;
  final DateTime kickoffAt;
  final String status;
  final int? homeScore;
  final int? awayScore;
  final String? statusDescription;

  const WizardMatchSummary({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.leagueName,
    required this.kickoffAt,
    required this.status,
    required this.homeScore,
    required this.awayScore,
    required this.statusDescription,
  });

  factory WizardMatchSummary.fromJson(Map<String, dynamic> json) {
    return WizardMatchSummary(
      id: json['id']?.toString() ?? '',
      homeTeam: json['homeTeam']?.toString() ?? '',
      awayTeam: json['awayTeam']?.toString() ?? '',
      leagueName: json['leagueName']?.toString(),
      kickoffAt: _asDateTime(json['kickoffAt']),
      status: json['status']?.toString() ?? 'upcoming',
      homeScore: _asNullableInt(json['homeScore']),
      awayScore: _asNullableInt(json['awayScore']),
      statusDescription: json['statusDescription']?.toString(),
    );
  }
}

class WizardCard {
  final String type;
  final String title;
  final String text;
  final String signal;
  final int confidence;
  final bool isPremium;
  final List<WizardEvidence> evidence;

  const WizardCard({
    required this.type,
    required this.title,
    required this.text,
    required this.signal,
    required this.confidence,
    required this.isPremium,
    required this.evidence,
  });

  factory WizardCard.fromJson(Map<String, dynamic> json) {
    return WizardCard(
      type: json['type']?.toString() ?? 'card',
      title: json['title']?.toString() ?? 'Analiz',
      text: json['text']?.toString() ?? '',
      signal: json['signal']?.toString() ?? 'neutral',
      confidence: _asInt(json['confidence']),
      isPremium: json['isPremium'] == true,
      evidence: _asList(json['evidence'])
          .map((item) => WizardEvidence.fromJson(_asMap(item)))
          .toList(),
    );
  }
}

class WizardMarketSignal {
  final String type;
  final String title;
  final String signal;
  final int confidence;
  final String text;
  final bool isPremium;
  final List<WizardEvidence> evidence;

  const WizardMarketSignal({
    required this.type,
    required this.title,
    required this.signal,
    required this.confidence,
    required this.text,
    required this.isPremium,
    required this.evidence,
  });

  factory WizardMarketSignal.fromJson(Map<String, dynamic> json) {
    return WizardMarketSignal(
      type: json['type']?.toString() ?? 'market',
      title: json['title']?.toString() ?? 'Market',
      signal: json['signal']?.toString() ?? 'watch',
      confidence: _asInt(json['confidence']),
      text: json['text']?.toString() ?? '',
      isPremium: json['isPremium'] != false,
      evidence: _asList(json['evidence'])
          .map((item) => WizardEvidence.fromJson(_asMap(item)))
          .toList(),
    );
  }
}

class WizardEvidence {
  final String label;
  final String value;

  const WizardEvidence({required this.label, required this.value});

  factory WizardEvidence.fromJson(Map<String, dynamic> json) {
    return WizardEvidence(
      label: json['label']?.toString() ?? 'Veri',
      value: json['value']?.toString() ?? '-',
    );
  }
}

class WizardQuestion {
  final String id;
  final String text;

  const WizardQuestion({required this.id, required this.text});

  factory WizardQuestion.fromJson(Map<String, dynamic> json) {
    return WizardQuestion(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
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

int _asInt(Object? value) => _asNullableInt(value) ?? 0;

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime _asDateTime(Object? value) {
  if (value is DateTime) return value;
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
}
