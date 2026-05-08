class WizardInsightReport {
  final WizardMatchSummary match;
  final String decision;
  final int confidence;
  final String riskLevel;
  final String summary;
  final WizardQuickContext quickContext;
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
    required this.quickContext,
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
      quickContext: WizardQuickContext.fromJson(_asMap(json['quickContext'])),
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

class WizardQuickContext {
  final bool available;
  final WizardQuickForm form;
  final WizardQuickStandings standings;
  final WizardQuickH2H h2h;
  final WizardQuickStakes stakes;

  const WizardQuickContext({
    required this.available,
    required this.form,
    required this.standings,
    required this.h2h,
    required this.stakes,
  });

  factory WizardQuickContext.fromJson(Map<String, dynamic> json) {
    return WizardQuickContext(
      available: json['available'] == true,
      form: WizardQuickForm.fromJson(_asMap(json['form'])),
      standings: WizardQuickStandings.fromJson(_asMap(json['standings'])),
      h2h: WizardQuickH2H.fromJson(_asMap(json['h2h'])),
      stakes: WizardQuickStakes.fromJson(_asMap(json['stakes'])),
    );
  }
}

class WizardQuickForm {
  final String? home;
  final String? away;
  final String edge;
  final String summary;

  const WizardQuickForm({
    required this.home,
    required this.away,
    required this.edge,
    required this.summary,
  });

  factory WizardQuickForm.fromJson(Map<String, dynamic> json) {
    return WizardQuickForm(
      home: _nullableString(json['home']),
      away: _nullableString(json['away']),
      edge: json['edge']?.toString() ?? 'unknown',
      summary: json['summary']?.toString() ?? 'Form verisi henuz yok.',
    );
  }
}

class WizardQuickStandings {
  final int? homeRank;
  final int? awayRank;
  final int? homePoints;
  final int? awayPoints;
  final int? teamCount;
  final String summary;

  const WizardQuickStandings({
    required this.homeRank,
    required this.awayRank,
    required this.homePoints,
    required this.awayPoints,
    required this.teamCount,
    required this.summary,
  });

  factory WizardQuickStandings.fromJson(Map<String, dynamic> json) {
    return WizardQuickStandings(
      homeRank: _asNullableInt(json['homeRank']),
      awayRank: _asNullableInt(json['awayRank']),
      homePoints: _asNullableInt(json['homePoints']),
      awayPoints: _asNullableInt(json['awayPoints']),
      teamCount: _asNullableInt(json['teamCount']),
      summary:
          json['summary']?.toString() ?? 'Lig siralamasi verisi henuz yok.',
    );
  }
}

class WizardQuickH2H {
  final int matches;
  final int homeWins;
  final int draws;
  final int awayWins;
  final String summary;

  const WizardQuickH2H({
    required this.matches,
    required this.homeWins,
    required this.draws,
    required this.awayWins,
    required this.summary,
  });

  factory WizardQuickH2H.fromJson(Map<String, dynamic> json) {
    return WizardQuickH2H(
      matches: _asInt(json['matches']),
      homeWins: _asInt(json['homeWins']),
      draws: _asInt(json['draws']),
      awayWins: _asInt(json['awayWins']),
      summary: json['summary']?.toString() ?? 'Ikili rekabet verisi henuz yok.',
    );
  }
}

class WizardQuickStakes {
  final String summary;

  const WizardQuickStakes({required this.summary});

  factory WizardQuickStakes.fromJson(Map<String, dynamic> json) {
    return WizardQuickStakes(
      summary:
          json['summary']?.toString() ?? 'Mac baglami icin yeterli veri yok.',
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

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}

DateTime _asDateTime(Object? value) {
  if (value is DateTime) return value;
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
}
