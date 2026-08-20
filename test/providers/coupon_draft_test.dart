import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/bulletin.dart';
import 'package:sports_app/models/coupon.dart';
import 'package:sports_app/providers/coupon_provider.dart';

/// The coupon draft carries the numbers the honest-verdict UI is built on:
/// combined odds, combined model probability, EV and the fractional-Kelly
/// stake. Nothing in the suite exercised it before, so a regression here would
/// have shipped a wrong stake suggestion silently.

BulletinMatch _match(String id, {DateTime? kickoff}) => BulletinMatch(
      id: id,
      sportsApiMatchId: 'sa-$id',
      agentMatchId: null,
      eventDate: DateTime(2026, 8, 20),
      kickoffAt: kickoff ?? DateTime(2026, 8, 20, 20, 0),
      status: 'scheduled',
      competitionName: 'Süper Lig',
      homeTeam: 'A',
      awayTeam: 'B',
      mbs: 1,
      updatedAt: null,
      markets: const [],
    );

BulletinMarket _market(String code) => BulletinMarket(
      marketCode: code,
      marketType: code,
      nameTr: code,
      lineValue: null,
      selections: const [],
    );

BulletinSelection _selection(String key, double odds) => BulletinSelection(
      selectionKey: key,
      labelTr: key,
      odds: odds,
      openingOdds: odds,
      movementPct: null,
      isDropping: false,
      impliedProb: 1 / odds,
      normalizedProb: null,
      suspended: false,
    );

BulletinPrediction _prediction(String matchId, Map<String, double> ms) =>
    BulletinPrediction(
      id: 'p-$matchId',
      bulletinMatchId: matchId,
      sportsApiMatchId: 'sa-$matchId',
      modelVersion: 'dc-v1',
      generatedAt: DateTime(2026, 8, 20, 12),
      lambdaHome: 1.6,
      lambdaAway: 1.1,
      rho: 0.0,
      marketProbs: {'MS': ms},
      valuePicks: const [],
    );

void main() {
  late ProviderContainer container;

  CouponDraftNotifier notifier() =>
      container.read(couponDraftProvider.notifier);
  CouponDraft draft() => container.read(couponDraftProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  void add(
    String matchId,
    String marketCode,
    String selectionKey,
    double odds, {
    Map<String, double>? modelProbs,
  }) {
    notifier().toggleSelection(
      match: _match(matchId),
      market: _market(marketCode),
      selection: _selection(selectionKey, odds),
      prediction:
          modelProbs == null ? null : _prediction(matchId, modelProbs),
    );
  }

  group('toggling', () {
    test('adds a selection and removes it when tapped again', () {
      add('m1', 'MS', 'home', 1.80);
      expect(draft().count, 1);
      add('m1', 'MS', 'home', 1.80);
      expect(draft().isEmpty, isTrue);
    });

    test('replaces the pick when another selection of the same slot is tapped',
        () {
      add('m1', 'MS', 'home', 1.80);
      add('m1', 'MS', 'draw', 3.40);
      expect(draft().count, 1);
      expect(draft().selections.single.selectionKey, 'draw');
    });

    test('keeps different markets of the same match as separate slots', () {
      add('m1', 'MS', 'home', 1.80);
      add('m1', 'AU_2_5', 'over', 1.90);
      expect(draft().count, 2);
    });

    test('clear empties the draft', () {
      add('m1', 'MS', 'home', 1.80);
      add('m2', 'MS', 'away', 2.50);
      notifier().clear();
      expect(draft().isEmpty, isTrue);
    });
  });

  group('derived numbers', () {
    test('total odds multiply and implied probability is their inverse', () {
      add('m1', 'MS', 'home', 2.00);
      add('m2', 'MS', 'away', 2.50);
      expect(draft().totalOdds, closeTo(5.0, 1e-9));
      expect(draft().combinedImpliedProb, closeTo(0.2, 1e-9));
    });

    test('combined model probability is null until every leg is modelled', () {
      add('m1', 'MS', 'home', 2.00, modelProbs: {'home': 0.55});
      add('m2', 'MS', 'away', 2.50);
      expect(draft().isFullyModeled, isFalse);
      expect(draft().combinedModelProb, isNull);
      // EV and Kelly must follow, or the UI would show a stake for a coupon
      // the model cannot actually price.
      expect(draft().expectedValue, isNull);
      expect(draft().kellyFraction(), isNull);
    });

    test('expected value is p*odds - 1 once fully modelled', () {
      add('m1', 'MS', 'home', 2.00, modelProbs: {'home': 0.60});
      add('m2', 'MS', 'away', 2.00, modelProbs: {'away': 0.60});
      expect(draft().combinedModelProb, closeTo(0.36, 1e-9));
      expect(draft().expectedValue, closeTo(0.36 * 4.0 - 1.0, 1e-9));
    });

    test('quarter Kelly matches the closed form for a real edge', () {
      add('m1', 'MS', 'home', 2.00, modelProbs: {'home': 0.60});
      // b = 1, p = 0.6 -> full Kelly 0.2 -> quarter 0.05
      expect(draft().kellyFraction(), closeTo(0.05, 1e-9));
    });

    test('Kelly is zero, never negative, when the model sees no edge', () {
      add('m1', 'MS', 'home', 2.00, modelProbs: {'home': 0.40});
      expect(draft().kellyFraction(), 0.0);
    });
  });

  group('honesty guards', () {
    test('flags two selections from the same match as correlated', () {
      // The combined probability assumes independence; two markets of one
      // match are not independent, so the UI has to warn.
      add('m1', 'MS', 'home', 1.80);
      add('m1', 'AU_2_5', 'over', 1.90);
      expect(draft().hasCorrelatedSelections, isTrue);
    });

    test('does not flag selections from different matches', () {
      add('m1', 'MS', 'home', 1.80);
      add('m2', 'MS', 'away', 2.50);
      expect(draft().hasCorrelatedSelections, isFalse);
    });

    test('detects a leg whose match has already kicked off', () {
      notifier().toggleSelection(
        match: _match('m1',
            kickoff: DateTime.now().subtract(const Duration(hours: 1))),
        market: _market('MS'),
        selection: _selection('home', 1.80),
      );
      expect(draft().hasStartedSelections, isTrue);
    });
  });
}
