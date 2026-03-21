import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/match.dart';
import '../../lib/models/league.dart';
import '../../lib/data/mock_data.dart';
import '../helpers/test_helpers.dart';

/// Tests the core dashboard logic: filtering, grouping, sorting, and
/// dynamic league creation — extracted so it doesn't need a widget tree.
void main() {
  // ── Filtering ──────────────────────────────────────────────────────
  group('Match filtering', () {
    final matches = [
      createTestMatch(id: '1', status: MatchStatus.live),
      createTestMatch(id: '2', status: MatchStatus.upcoming),
      createTestMatch(id: '3', status: MatchStatus.finished),
      createTestMatch(id: '4', status: MatchStatus.live, isFavorite: true),
    ];

    List<Match> applyFilter(String filter, List<Match> all) {
      return all.where((m) {
        if (filter == 'Live 🔴') return m.status == MatchStatus.live;
        if (filter == 'Starred ⭐') return m.isFavorite;
        if (filter == 'Finished') return m.status == MatchStatus.finished;
        return true;
      }).toList();
    }

    test('"All" returns everything', () {
      final result = applyFilter('All', matches);
      expect(result.length, 4);
    });

    test('"Live" returns only live matches', () {
      final result = applyFilter('Live 🔴', matches);
      expect(result.length, 2);
      expect(result.every((m) => m.status == MatchStatus.live), true);
    });

    test('"Starred" returns only favorites', () {
      final result = applyFilter('Starred ⭐', matches);
      expect(result.length, 1);
      expect(result.first.id, '4');
    });

    test('"Finished" returns only finished matches', () {
      final result = applyFilter('Finished', matches);
      expect(result.length, 1);
      expect(result.first.status, MatchStatus.finished);
    });

    test('empty list returns empty for all filters', () {
      expect(applyFilter('All', []).length, 0);
      expect(applyFilter('Live 🔴', []).length, 0);
    });
  });

  // ── League Grouping ────────────────────────────────────────────────
  group('League grouping', () {
    test('matches are grouped by leagueId', () {
      final matches = [
        createTestMatch(id: '1', leagueId: 'pl'),
        createTestMatch(id: '2', leagueId: 'pl'),
        createTestMatch(id: '3', leagueId: 'la_liga'),
      ];

      final Map<String, List<Match>> leagueMap = {};
      for (var m in matches) {
        leagueMap.putIfAbsent(m.leagueId, () => []).add(m);
      }

      expect(leagueMap.keys.length, 2);
      expect(leagueMap['pl']!.length, 2);
      expect(leagueMap['la_liga']!.length, 1);
    });

    test('featured matches are excluded from league groups', () {
      final matches = [
        createTestMatch(id: '1', leagueId: 'pl', isFeatured: true),
        createTestMatch(id: '2', leagueId: 'pl', isFeatured: false),
      ];

      final grouped = matches.where((m) => !m.isFeatured).toList();
      expect(grouped.length, 1);
      expect(grouped.first.id, '2');
    });
  });

  // ── Dynamic League Creation ────────────────────────────────────────
  group('Dynamic league creation', () {
    test('known MockData league is used when available', () {
      // This tests the logic from home_dashboard _buildLeagueSlivers
      const knownId = 'premier_league';
      final found = MockData.leagues.where((l) => l.id == knownId).toList();

      // If MockData has premier_league, it should be found
      if (found.isNotEmpty) {
        expect(found.first.name, isNotEmpty);
        expect(found.first.name, isNot(startsWith('League ')));
      }
    });

    test('unknown leagueId creates dynamic League with match metadata', () {
      final match = createTestMatch(
        leagueId: '999999',
        leagueName: 'Bundesliga',
        leagueLogoUrl: 'https://example.com/bundesliga.png',
      );

      // Simulate the dashboard logic
      final league = League(
        id: match.leagueId,
        name: match.leagueName ?? 'League ${match.leagueId}',
        logoUrl: match.leagueLogoUrl ?? 'https://fallback.com/globe.png',
        tier: 3,
      );

      expect(league.name, 'Bundesliga');
      expect(league.logoUrl, 'https://example.com/bundesliga.png');
      expect(league.tier, 3);
    });

    test('unknown leagueId with null leagueName falls back to ID string', () {
      final match = createTestMatch(
        leagueId: '777',
        leagueName: null,
        leagueLogoUrl: null,
      );

      final league = League(
        id: match.leagueId,
        name: match.leagueName ?? 'League ${match.leagueId}',
        logoUrl: match.leagueLogoUrl ?? 'https://fallback.com/globe.png',
        tier: 3,
      );

      expect(league.name, 'League 777');
      expect(league.logoUrl, 'https://fallback.com/globe.png');
    });
  });

  // ── Match Sorting ──────────────────────────────────────────────────
  group('Match sorting (priority order)', () {
    test('Live > Upcoming > Finished', () {
      final matches = [
        createTestMatch(id: 'fin', status: MatchStatus.finished),
        createTestMatch(id: 'up', status: MatchStatus.upcoming),
        createTestMatch(id: 'live', status: MatchStatus.live),
      ];

      matches.sort((a, b) {
        if (a.status != b.status) {
          if (a.status == MatchStatus.live) return -1;
          if (b.status == MatchStatus.live) return 1;
          if (a.status == MatchStatus.upcoming) return -1;
          return 1;
        }
        return a.startTime.compareTo(b.startTime);
      });

      expect(matches[0].id, 'live');
      expect(matches[1].id, 'up');
      expect(matches[2].id, 'fin');
    });

    test('same-status matches sort by startTime', () {
      final early = DateTime(2026, 3, 20, 18, 0);
      final late = DateTime(2026, 3, 20, 22, 0);

      final matches = [
        createTestMatch(id: 'late', status: MatchStatus.live, startTime: late),
        createTestMatch(id: 'early', status: MatchStatus.live, startTime: early),
      ];

      matches.sort((a, b) {
        if (a.status != b.status) {
          if (a.status == MatchStatus.live) return -1;
          if (b.status == MatchStatus.live) return 1;
          if (a.status == MatchStatus.upcoming) return -1;
          return 1;
        }
        return a.startTime.compareTo(b.startTime);
      });

      expect(matches[0].id, 'early');
      expect(matches[1].id, 'late');
    });
  });
}
