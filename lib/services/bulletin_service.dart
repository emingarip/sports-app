import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bulletin.dart';

/// Read-only queries against the iddaa bulletin tables
/// (`bulletin_matches`, `bulletin_odds`, `bulletin_predictions`).
class BulletinService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetches the bulletin for a calendar day, with the odds of every match
  /// assembled into nested [BulletinMarket]/[BulletinSelection] models.
  Future<List<BulletinMatch>> fetchBulletin({required DateTime date}) async {
    final matchRows = await _client
        .from('bulletin_matches')
        .select()
        .eq('event_date', _formatDate(date))
        .order('kickoff_at', ascending: true);

    final matches = _asMapList(matchRows)
        .map(BulletinMatch.fromJson)
        .where((match) => match.id.isNotEmpty)
        .toList();
    if (matches.isEmpty) return matches;

    final oddsRows = await _client.from('bulletin_odds').select().inFilter(
          'bulletin_match_id',
          matches.map((match) => match.id).toList(),
        );

    final marketsByMatch = _groupOddsByMatch(_asMapList(oddsRows));
    return matches
        .map((match) =>
            match.copyWith(markets: marketsByMatch[match.id] ?? const []))
        .toList();
  }

  /// Emits every time the bulletin odds table changes.
  ///
  /// `bulletin_matches` and `bulletin_odds` were added to the
  /// `supabase_realtime` publication when the tables were created
  /// (`20260711090000_bulletin_infrastructure.sql`) and the `sync-bulletin`
  /// function's own comment promises "realtime odds updates" - but nothing on
  /// the client ever subscribed, so odds sat stale until the screen was
  /// rebuilt from scratch.
  ///
  /// The stream carries no payload on purpose: an hourly sync rewrites
  /// hundreds of rows at once, so listeners debounce and refetch the day
  /// rather than patching row by row.
  Stream<void> oddsChanges() {
    final controller = StreamController<void>.broadcast();
    final channel = _client.channel('bulletin_odds_changes');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bulletin_odds',
          callback: (_) {
            if (!controller.isClosed) controller.add(null);
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _client.removeChannel(channel);
    };
    return controller.stream;
  }

  /// Fetches model predictions for the given bulletin matches, keyed by
  /// `bulletin_match_id`.
  Future<Map<String, BulletinPrediction>> fetchPredictions(
      List<String> bulletinMatchIds) async {
    if (bulletinMatchIds.isEmpty) return const {};

    final rows = await _client
        .from('bulletin_predictions')
        .select()
        .inFilter('bulletin_match_id', bulletinMatchIds);

    final predictions = <String, BulletinPrediction>{};
    for (final row in _asMapList(rows)) {
      final prediction = BulletinPrediction.fromJson(row);
      if (prediction.bulletinMatchId.isEmpty) continue;
      predictions[prediction.bulletinMatchId] = prediction;
    }
    return predictions;
  }

  /// Fetches the model prediction for a single bulletin match, or null when
  /// the model has not produced one yet.
  Future<BulletinPrediction?> fetchPrediction(String bulletinMatchId) async {
    final row = await _client
        .from('bulletin_predictions')
        .select()
        .eq('bulletin_match_id', bulletinMatchId)
        .maybeSingle();

    if (row == null) return null;
    return BulletinPrediction.fromJson(row);
  }

  Map<String, List<BulletinMarket>> _groupOddsByMatch(
      List<Map<String, dynamic>> oddsRows) {
    // bulletin_match_id -> market_code -> odds rows
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final row in oddsRows) {
      final matchId = row['bulletin_match_id']?.toString() ?? '';
      final marketCode = row['market_code']?.toString() ?? '';
      if (matchId.isEmpty || marketCode.isEmpty) continue;
      grouped
          .putIfAbsent(matchId, () => {})
          .putIfAbsent(marketCode, () => [])
          .add(row);
    }

    final marketsByMatch = <String, List<BulletinMarket>>{};
    grouped.forEach((matchId, marketRows) {
      final markets = marketRows.entries
          .map((entry) => _buildMarket(entry.key, entry.value))
          .toList()
        ..sort((a, b) => _marketSortIndex(a.marketCode)
            .compareTo(_marketSortIndex(b.marketCode)));
      marketsByMatch[matchId] = markets;
    });
    return marketsByMatch;
  }

  BulletinMarket _buildMarket(
      String marketCode, List<Map<String, dynamic>> rows) {
    final selections = rows.map(BulletinSelection.fromJson).toList()
      ..sort((a, b) => _selectionSortIndex(a.selectionKey)
          .compareTo(_selectionSortIndex(b.selectionKey)));

    final first = rows.first;
    return BulletinMarket(
      marketCode: marketCode,
      marketType: first['market_type']?.toString(),
      nameTr: bulletinMarketLabel(
        marketCode,
        nameTr: first['market_name_tr']?.toString(),
      ),
      lineValue: _nullableDouble(first['line_value']),
      selections: selections,
    );
  }

  int _marketSortIndex(String marketCode) {
    final index = bulletinMarketOrder.indexOf(marketCode);
    return index == -1 ? bulletinMarketOrder.length : index;
  }

  int _selectionSortIndex(String selectionKey) {
    final index = bulletinSelectionOrder.indexOf(selectionKey);
    return index == -1 ? bulletinSelectionOrder.length : index;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! Iterable) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  double? _nullableDouble(Object? value) {
    if (value == null || value is bool) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
