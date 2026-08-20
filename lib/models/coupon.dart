import 'bulletin.dart';

/// One selection inside an analysis coupon.
class CouponSelection {
  final String bulletinMatchId;
  final String? sportsApiMatchId;
  final String matchLabel;
  final DateTime? kickoffAt;
  final String marketCode;
  final String marketName;
  final String selectionKey;
  final String selectionLabel;
  final double odds;
  final double? lineValue;

  /// Model probability for this selection at the time it was added,
  /// null when no prediction exists for the match.
  final double? modelProbability;

  const CouponSelection({
    required this.bulletinMatchId,
    required this.sportsApiMatchId,
    required this.matchLabel,
    required this.kickoffAt,
    required this.marketCode,
    required this.marketName,
    required this.selectionKey,
    required this.selectionLabel,
    required this.odds,
    this.lineValue,
    this.modelProbability,
  });

  factory CouponSelection.fromBulletin({
    required BulletinMatch match,
    required BulletinMarket market,
    required BulletinSelection selection,
    BulletinPrediction? prediction,
  }) {
    return CouponSelection(
      bulletinMatchId: match.id,
      sportsApiMatchId: match.sportsApiMatchId,
      matchLabel: '${match.homeTeam} - ${match.awayTeam}',
      kickoffAt: match.kickoffAt,
      marketCode: market.marketCode,
      marketName: market.displayName,
      selectionKey: selection.selectionKey,
      selectionLabel: selection.labelTr,
      odds: selection.odds,
      lineValue: market.lineValue,
      modelProbability:
          prediction?.probabilityFor(market.marketCode, selection.selectionKey),
    );
  }

  /// Identity of a selection slot: one pick per match+market.
  String get slotKey => '$bulletinMatchId|$marketCode';

  /// Full identity including the picked selection.
  String get selectionId => '$bulletinMatchId|$marketCode|$selectionKey';

  bool get hasStarted =>
      kickoffAt != null && kickoffAt!.isBefore(DateTime.now());

  /// Payload shape expected by the `share_coupon` RPC.
  Map<String, dynamic> toRpcJson() {
    return {
      'bulletin_match_id': bulletinMatchId,
      'sports_api_match_id': sportsApiMatchId,
      'match_label': matchLabel,
      'kickoff_at': kickoffAt?.toUtc().toIso8601String(),
      'market_code': marketCode,
      'market_name': marketName,
      'selection_key': selectionKey,
      'selection_label': selectionLabel,
      'odds_at_share': odds,
      'line_value': lineValue,
      'result': 'pending',
      'closing_odds': null,
      'clv': null,
    };
  }
}

/// The coupon being built on the client. All derived numbers live here so the
/// UI and the share flow use the same math.
class CouponDraft {
  final List<CouponSelection> selections;

  const CouponDraft({this.selections = const []});

  bool get isEmpty => selections.isEmpty;
  int get count => selections.length;

  /// Combined decimal odds (product of selections).
  double get totalOdds =>
      selections.fold(1.0, (acc, selection) => acc * selection.odds);

  /// Bookmaker implied probability of the combo (product of 1/odds).
  double get combinedImpliedProb =>
      selections.fold(1.0, (acc, selection) => acc * (1.0 / selection.odds));

  /// Whether every selection has a model probability.
  bool get isFullyModeled =>
      selections.isNotEmpty &&
      selections.every((selection) => selection.modelProbability != null);

  /// Combined model probability, assuming independent matches.
  /// Null when any selection lacks a model probability.
  double? get combinedModelProb {
    if (!isFullyModeled) return null;
    return selections.fold<double>(
      1.0,
      (acc, selection) => acc * selection.modelProbability!,
    );
  }

  /// Expected value per 1 unit staked: p*odds - 1. Null without full model coverage.
  double? get expectedValue {
    final probability = combinedModelProb;
    if (probability == null) return null;
    return probability * totalOdds - 1.0;
  }

  /// Quarter-Kelly stake suggestion as a share of bankroll (0..1).
  double? kellyFraction({double fraction = 0.25}) {
    final probability = combinedModelProb;
    if (probability == null) return null;
    final b = totalOdds - 1.0;
    if (b <= 0) return 0.0;
    final full = (b * probability - (1.0 - probability)) / b;
    return full <= 0 ? 0.0 : full * fraction;
  }

  /// Same-match selections are statistically dependent; the combined
  /// probability above overstates independence in that case.
  bool get hasCorrelatedSelections {
    final matchIds = selections.map((s) => s.bulletinMatchId).toList();
    return matchIds.toSet().length != matchIds.length;
  }

  bool get hasStartedSelections =>
      selections.any((selection) => selection.hasStarted);

  bool containsSelection(
    String bulletinMatchId,
    String marketCode,
    String selectionKey,
  ) {
    return selections.any(
      (s) => s.selectionId == '$bulletinMatchId|$marketCode|$selectionKey',
    );
  }

  CouponDraft copyWith({List<CouponSelection>? selections}) {
    return CouponDraft(selections: selections ?? this.selections);
  }
}

/// A stored analysis coupon (own history / feed).
class AnalysisCoupon {
  final String id;
  final String userId;
  final String? originCouponId;
  final String? title;
  final List<Map<String, dynamic>> selections;
  final double totalOdds;
  final double? combinedModelProb;
  final double? expectedValue;
  final int? stakeKcoin;
  final String status;
  final bool isPublic;
  final DateTime? lockedAt;
  final DateTime? firstKickoffAt;
  final DateTime? resolvedAt;
  final double? avgClv;
  final DateTime? createdAt;

  /// Social fields, only populated when the row was fetched with the
  /// `users(...)` / `coupon_likes(...)` embeds (feed queries).
  final String? username;
  final String? avatarUrl;
  final int? likeCount;
  final bool? likedByMe;

  const AnalysisCoupon({
    required this.id,
    required this.userId,
    this.originCouponId,
    this.title,
    this.selections = const [],
    required this.totalOdds,
    this.combinedModelProb,
    this.expectedValue,
    this.stakeKcoin,
    required this.status,
    required this.isPublic,
    this.lockedAt,
    this.firstKickoffAt,
    this.resolvedAt,
    this.avgClv,
    this.createdAt,
    this.username,
    this.avatarUrl,
    this.likeCount,
    this.likedByMe,
  });

  bool get isSettled => status != 'pending';
  bool get isWon => status == 'won';

  /// [currentUserId] is only needed to derive [likedByMe] from an embedded
  /// `coupon_likes(user_id)` list; plain table reads can omit it.
  factory AnalysisCoupon.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final user = json['users'];
    final likes = (json['coupon_likes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final hasLikesEmbed = json.containsKey('coupon_likes');

    return AnalysisCoupon(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      originCouponId: json['origin_coupon_id']?.toString(),
      title: json['title']?.toString(),
      selections: (json['selections'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      totalOdds: _asDouble(json['total_odds']) ?? 1.0,
      combinedModelProb: _asDouble(json['combined_model_prob']),
      expectedValue: _asDouble(json['expected_value']),
      stakeKcoin: (json['stake_kcoin'] as num?)?.toInt(),
      status: json['status']?.toString() ?? 'pending',
      isPublic: json['is_public'] == true,
      lockedAt: _asDateTime(json['locked_at']),
      firstKickoffAt: _asDateTime(json['first_kickoff_at']),
      resolvedAt: _asDateTime(json['resolved_at']),
      avgClv: _asDouble(json['avg_clv']),
      createdAt: _asDateTime(json['created_at']),
      username: user is Map ? user['username']?.toString() : null,
      avatarUrl: user is Map ? user['avatar_url']?.toString() : null,
      likeCount: hasLikesEmbed ? likes.length : null,
      likedByMe: hasLikesEmbed && currentUserId != null
          ? likes.any((like) => like['user_id']?.toString() == currentUserId)
          : null,
    );
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
