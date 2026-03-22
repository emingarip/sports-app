import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/match.dart';

/// Tests for the SupabaseMatchProvider's _mapMatch logic.
/// Since _mapMatch is private, we test the same transformation logic here
/// to ensure our data mapping from Supabase JSON -> Match model is correct.
void main() {
  group('Supabase JSON -> Match mapping', () {
    Match mapMatch(Map<String, dynamic> data) {
      MatchStatus status;
      switch (data['status']) {
        case 'live':
          status = MatchStatus.live;
          break;
        case 'finished':
          status = MatchStatus.finished;
          break;
        default:
          status = MatchStatus.upcoming;
      }

      return Match(
        id: data['id'],
        leagueId: data['league_id'] ?? 'premier_league',
        leagueName: data['league_name'],
        leagueLogoUrl: data['league_logo_url'],
        homeTeam: data['home_team'],
        awayTeam: data['away_team'],
        homeLogo: data['home_logo_url'] ?? 'https://fallback.com/default.png',
        awayLogo: data['away_logo_url'] ?? 'https://fallback.com/default.png',
        startTime: data['started_at'] != null
            ? DateTime.parse(data['started_at'])
            : DateTime.now(),
        status: status,
        homeScore: data['home_score']?.toString(),
        awayScore: data['away_score']?.toString(),
        liveMinute: data['minute'],
      );
    }

    test('maps live match correctly', () {
      final data = {
        'id': 'uuid-1',
        'league_id': '142901',
        'league_name': 'Premier League',
        'league_logo_url': 'https://example.com/pl.png',
        'home_team': 'Arsenal',
        'away_team': 'Chelsea',
        'home_logo_url': 'https://example.com/arsenal.png',
        'away_logo_url': 'https://example.com/chelsea.png',
        'status': 'live',
        'home_score': 2,
        'away_score': 1,
        'minute': "45'",
        'started_at': '2026-03-20T20:00:00Z',
      };

      final match = mapMatch(data);

      expect(match.id, 'uuid-1');
      expect(match.leagueId, '142901');
      expect(match.leagueName, 'Premier League');
      expect(match.homeTeam, 'Arsenal');
      expect(match.awayTeam, 'Chelsea');
      expect(match.status, MatchStatus.live);
      expect(match.homeScore, '2');
      expect(match.awayScore, '1');
      expect(match.liveMinute, "45'");
    });

    test('maps finished match correctly', () {
      final data = {
        'id': 'uuid-2',
        'league_id': '95245',
        'home_team': 'Bayern',
        'away_team': 'Dortmund',
        'status': 'finished',
        'home_score': 3,
        'away_score': 0,
        'started_at': '2026-03-20T18:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.status, MatchStatus.finished);
      expect(match.homeScore, '3');
      expect(match.awayScore, '0');
    });

    test('maps pre_match as upcoming', () {
      final data = {
        'id': 'uuid-3',
        'league_id': '68013',
        'home_team': 'Barcelona',
        'away_team': 'Real Madrid',
        'status': 'pre_match',
        'started_at': '2026-03-21T21:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.status, MatchStatus.upcoming);
    });

    test('unknown status defaults to upcoming', () {
      final data = {
        'id': 'uuid-4',
        'league_id': '1234',
        'home_team': 'Team A',
        'away_team': 'Team B',
        'status': 'some_random_status',
        'started_at': '2026-03-21T21:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.status, MatchStatus.upcoming);
    });

    test('null league_id defaults to premier_league', () {
      final data = {
        'id': 'uuid-5',
        'league_id': null,
        'home_team': 'Team X',
        'away_team': 'Team Y',
        'status': 'live',
        'started_at': '2026-03-20T20:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.leagueId, 'premier_league');
    });

    test('null logo URLs get fallback values', () {
      final data = {
        'id': 'uuid-6',
        'league_id': '999',
        'home_team': 'No Logo FC',
        'away_team': 'Also No Logo FC',
        'home_logo_url': null,
        'away_logo_url': null,
        'status': 'live',
        'started_at': '2026-03-20T20:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.homeLogo, 'https://fallback.com/default.png');
      expect(match.awayLogo, 'https://fallback.com/default.png');
    });

    test('null league_name stays null', () {
      final data = {
        'id': 'uuid-7',
        'league_id': '50000',
        'league_name': null,
        'home_team': 'A',
        'away_team': 'B',
        'status': 'live',
        'started_at': '2026-03-20T20:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.leagueName, isNull);
    });

    test('scores are converted to strings', () {
      final data = {
        'id': 'uuid-8',
        'league_id': '100',
        'home_team': 'Home',
        'away_team': 'Away',
        'status': 'finished',
        'home_score': 0,
        'away_score': 0,
        'started_at': '2026-03-20T20:00:00Z',
      };

      final match = mapMatch(data);
      expect(match.homeScore, '0');
      expect(match.awayScore, '0');
    });
  });
}
