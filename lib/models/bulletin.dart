/// Models for the iddaa bulletin (bulletin_matches / bulletin_odds /
/// bulletin_predictions Supabase tables).
library;

/// Canonical ordering for markets when listing them on the analysis screen.
const List<String> bulletinMarketOrder = [
  'MS',
  'IY',
  'IY_MS',
  'CS',
  'KG',
  'AU_1_5',
  'AU_2_5',
  'AU_3_5',
  'IY_AU_0_5',
  'IY_AU_1_5',
  'TG',
  'H_MS_1',
  'H_MS_MINUS_1',
];

/// Canonical ordering for selections inside a market (1-X-2, Alt-Ust, ...).
const List<String> bulletinSelectionOrder = [
  'home',
  'draw',
  'away',
  'over',
  'under',
  'yes',
  'no',
  'home_home',
  'home_draw',
  'home_away',
  'draw_home',
  'draw_draw',
  'draw_away',
  'away_home',
  'away_draw',
  'away_away',
];

/// Turkish fallback names when `market_name_tr` is missing on the odds rows.
const Map<String, String> bulletinMarketNamesTr = {
  'MS': 'Maç Sonucu',
  'IY': 'İlk Yarı Sonucu',
  'IY_MS': 'İY/MS',
  'CS': 'Çifte Şans',
  'KG': 'Karşılıklı Gol',
  'AU_1_5': 'Alt/Üst 1,5',
  'AU_2_5': 'Alt/Üst 2,5',
  'AU_3_5': 'Alt/Üst 3,5',
  'IY_AU_0_5': 'İY Alt/Üst 0,5',
  'IY_AU_1_5': 'İY Alt/Üst 1,5',
  'TG': 'Toplam Gol',
  'H_MS_1': 'Handikaplı MS (+1)',
  'H_MS_MINUS_1': 'Handikaplı MS (-1)',
};

String bulletinMarketLabel(String marketCode, {String? nameTr}) {
  if (nameTr != null && nameTr.trim().isNotEmpty) return nameTr;
  return bulletinMarketNamesTr[marketCode] ?? marketCode;
}

/// Turkish fallback labels when `selection_label_tr` is missing.
const Map<String, String> bulletinSelectionLabelsTr = {
  'home': '1',
  'draw': 'X',
  'away': '2',
  'over': 'Üst',
  'under': 'Alt',
  'yes': 'Var',
  'no': 'Yok',
  'home_home': '1/1',
  'home_draw': '1/X',
  'home_away': '1/2',
  'draw_home': 'X/1',
  'draw_draw': 'X/X',
  'draw_away': 'X/2',
  'away_home': '2/1',
  'away_draw': '2/X',
  'away_away': '2/2',
};

String bulletinSelectionLabel(String selectionKey, {String? labelTr}) {
  if (labelTr != null && labelTr.trim().isNotEmpty) return labelTr;
  return bulletinSelectionLabelsTr[selectionKey] ?? selectionKey;
}

class BulletinMatch {
  final String id;
  final String? sportsApiMatchId;

  /// Canlı skor tarafındaki (AI Sport Agent) maç kimliği; ana ekran kartını
  /// bülten kaydına bağlayan köprü. Eşleşme yoksa null.
  final String? agentMatchId;
  final DateTime? eventDate;
  final DateTime? kickoffAt;
  final String status;
  final String competitionName;
  final String homeTeam;
  final String awayTeam;
  final int? mbs;
  final DateTime? updatedAt;
  final List<BulletinMarket> markets;

  const BulletinMatch({
    required this.id,
    required this.sportsApiMatchId,
    this.agentMatchId,
    required this.eventDate,
    required this.kickoffAt,
    required this.status,
    required this.competitionName,
    required this.homeTeam,
    required this.awayTeam,
    required this.mbs,
    required this.updatedAt,
    this.markets = const [],
  });

  BulletinMarket? marketByCode(String marketCode) {
    for (final market in markets) {
      if (market.marketCode == marketCode) return market;
    }
    return null;
  }

  BulletinMatch copyWith({List<BulletinMarket>? markets}) {
    return BulletinMatch(
      id: id,
      sportsApiMatchId: sportsApiMatchId,
      agentMatchId: agentMatchId,
      eventDate: eventDate,
      kickoffAt: kickoffAt,
      status: status,
      competitionName: competitionName,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      mbs: mbs,
      updatedAt: updatedAt,
      markets: markets ?? this.markets,
    );
  }

  factory BulletinMatch.fromJson(Map<String, dynamic> json) {
    return BulletinMatch(
      id: json['id']?.toString() ?? '',
      sportsApiMatchId: _nullableString(json['sports_api_match_id']),
      agentMatchId: _nullableString(json['agent_match_id']),
      eventDate: _nullableDateTime(json['event_date']),
      kickoffAt: _nullableDateTime(json['kickoff_at']),
      status: json['status']?.toString() ?? 'scheduled',
      competitionName: _nullableString(json['competition_name']) ?? 'Diğer',
      homeTeam: json['home_team']?.toString() ?? '',
      awayTeam: json['away_team']?.toString() ?? '',
      mbs: _nullableInt(json['mbs']),
      updatedAt: _nullableDateTime(json['updated_at']),
      markets: _asList(json['markets'])
          .map((item) => BulletinMarket.fromJson(_asMap(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sports_api_match_id': sportsApiMatchId,
      'agent_match_id': agentMatchId,
      'event_date': eventDate?.toIso8601String(),
      'kickoff_at': kickoffAt?.toIso8601String(),
      'status': status,
      'competition_name': competitionName,
      'home_team': homeTeam,
      'away_team': awayTeam,
      'mbs': mbs,
      'updated_at': updatedAt?.toIso8601String(),
      'markets': markets.map((market) => market.toJson()).toList(),
    };
  }
}

class BulletinMarket {
  final String marketCode;
  final String? marketType;
  final String nameTr;
  final double? lineValue;
  final List<BulletinSelection> selections;

  const BulletinMarket({
    required this.marketCode,
    required this.marketType,
    required this.nameTr,
    required this.lineValue,
    required this.selections,
  });

  String get displayName => bulletinMarketLabel(marketCode, nameTr: nameTr);

  BulletinSelection? selectionByKey(String selectionKey) {
    for (final selection in selections) {
      if (selection.selectionKey == selectionKey) return selection;
    }
    return null;
  }

  factory BulletinMarket.fromJson(Map<String, dynamic> json) {
    final marketCode = json['market_code']?.toString() ?? '';
    return BulletinMarket(
      marketCode: marketCode,
      marketType: _nullableString(json['market_type']),
      nameTr: _nullableString(json['market_name_tr']) ??
          bulletinMarketLabel(marketCode),
      lineValue: _nullableDouble(json['line_value']),
      selections: _asList(json['selections'])
          .map((item) => BulletinSelection.fromJson(_asMap(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'market_code': marketCode,
      'market_type': marketType,
      'market_name_tr': nameTr,
      'line_value': lineValue,
      'selections': selections.map((selection) => selection.toJson()).toList(),
    };
  }
}

class BulletinSelection {
  final String selectionKey;
  final String labelTr;
  final double odds;
  final double? openingOdds;
  final double? movementPct;
  final bool isDropping;
  final double? impliedProb;
  final double? normalizedProb;
  final bool suspended;

  const BulletinSelection({
    required this.selectionKey,
    required this.labelTr,
    required this.odds,
    required this.openingOdds,
    required this.movementPct,
    required this.isDropping,
    required this.impliedProb,
    required this.normalizedProb,
    required this.suspended,
  });

  factory BulletinSelection.fromJson(Map<String, dynamic> json) {
    final selectionKey = json['selection_key']?.toString() ?? '';
    return BulletinSelection(
      selectionKey: selectionKey,
      labelTr: _nullableString(json['selection_label_tr']) ?? selectionKey,
      odds: _asDouble(json['odds']),
      openingOdds: _nullableDouble(json['opening_odds']),
      movementPct: _nullableDouble(json['movement_pct']),
      isDropping: json['is_dropping'] == true,
      impliedProb: _nullableDouble(json['implied_prob']),
      normalizedProb: _nullableDouble(json['normalized_prob']),
      suspended: json['suspended'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selection_key': selectionKey,
      'selection_label_tr': labelTr,
      'odds': odds,
      'opening_odds': openingOdds,
      'movement_pct': movementPct,
      'is_dropping': isDropping,
      'implied_prob': impliedProb,
      'normalized_prob': normalizedProb,
      'suspended': suspended,
    };
  }
}

class BulletinPrediction {
  final String id;
  final String bulletinMatchId;
  final String? sportsApiMatchId;
  final String modelVersion;
  final DateTime? generatedAt;
  final double lambdaHome;
  final double lambdaAway;
  final double? rho;
  final Map<String, Map<String, double>> marketProbs;
  final List<ValuePick> valuePicks;

  const BulletinPrediction({
    required this.id,
    required this.bulletinMatchId,
    required this.sportsApiMatchId,
    required this.modelVersion,
    required this.generatedAt,
    required this.lambdaHome,
    required this.lambdaAway,
    required this.rho,
    required this.marketProbs,
    required this.valuePicks,
  });

  /// Model probability for a given market/selection pair, if the model
  /// produced one.
  double? probabilityFor(String marketCode, String selectionKey) {
    return marketProbs[marketCode]?[selectionKey];
  }

  bool isValuePick(String marketCode, String selectionKey) {
    return valuePicks.any((pick) =>
        pick.marketCode == marketCode && pick.selectionKey == selectionKey);
  }

  factory BulletinPrediction.fromJson(Map<String, dynamic> json) {
    return BulletinPrediction(
      id: json['id']?.toString() ?? '',
      bulletinMatchId: json['bulletin_match_id']?.toString() ?? '',
      sportsApiMatchId: _nullableString(json['sports_api_match_id']),
      modelVersion: json['model_version']?.toString() ?? '',
      generatedAt: _nullableDateTime(json['generated_at']),
      lambdaHome: _asDouble(json['lambda_home']),
      lambdaAway: _asDouble(json['lambda_away']),
      rho: _nullableDouble(json['rho']),
      marketProbs: _parseMarketProbs(json['market_probs']),
      valuePicks: _asList(json['value_picks'])
          .map((item) => ValuePick.fromJson(_asMap(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bulletin_match_id': bulletinMatchId,
      'sports_api_match_id': sportsApiMatchId,
      'model_version': modelVersion,
      'generated_at': generatedAt?.toIso8601String(),
      'lambda_home': lambdaHome,
      'lambda_away': lambdaAway,
      'rho': rho,
      'market_probs': marketProbs,
      'value_picks': valuePicks.map((pick) => pick.toJson()).toList(),
    };
  }

  static Map<String, Map<String, double>> _parseMarketProbs(Object? value) {
    final raw = _asMap(value);
    final result = <String, Map<String, double>>{};
    raw.forEach((marketCode, selections) {
      final selectionMap = _asMap(selections);
      if (selectionMap.isEmpty) return;
      final probs = <String, double>{};
      selectionMap.forEach((selectionKey, prob) {
        final parsed = _nullableDouble(prob);
        if (parsed != null) probs[selectionKey] = parsed;
      });
      if (probs.isNotEmpty) result[marketCode] = probs;
    });
    return result;
  }
}

class ValuePick {
  final String marketCode;
  final String selectionKey;
  /// Blended probability the pick was flagged on (model + de-vigged market).
  final double modelProbability;
  final double oddsDecimal;
  final double? impliedProbability;
  final double expectedValue;
  final double? kellyStake;

  /// Pure Dixon-Coles probability before the market blend. Emitted by
  /// `PredictionService` for transparency; null on older rows.
  final double? dcProbability;

  /// Shin-devigged market probability that went into the blend. Null when the
  /// bulletin did not cover the full market, in which case the pick is pure
  /// model output.
  final double? marketProbability;

  const ValuePick({
    required this.marketCode,
    required this.selectionKey,
    required this.modelProbability,
    required this.oddsDecimal,
    required this.impliedProbability,
    required this.expectedValue,
    required this.kellyStake,
    this.dcProbability,
    this.marketProbability,
  });

  factory ValuePick.fromJson(Map<String, dynamic> json) {
    return ValuePick(
      marketCode: json['market_code']?.toString() ?? '',
      selectionKey: json['selection_key']?.toString() ?? '',
      modelProbability: _asDouble(json['model_probability']),
      oddsDecimal: _asDouble(json['odds_decimal']),
      impliedProbability: _nullableDouble(json['implied_probability']),
      expectedValue: _asDouble(json['expected_value']),
      kellyStake: _nullableDouble(json['kelly_stake']),
      dcProbability: _nullableDouble(json['dc_probability']),
      marketProbability: _nullableDouble(json['market_probability']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'market_code': marketCode,
      'selection_key': selectionKey,
      'model_probability': modelProbability,
      'odds_decimal': oddsDecimal,
      'implied_probability': impliedProbability,
      'expected_value': expectedValue,
      'kelly_stake': kellyStake,
      'dc_probability': dcProbability,
      'market_probability': marketProbability,
    };
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

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(Object? value) {
  if (value == null || value is bool) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
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
