import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/match.dart';

void main() {
  group('MatchStatus enum', () {
    test('has all expected values', () {
      expect(MatchStatus.values.length, 3);
      expect(MatchStatus.values, contains(MatchStatus.live));
      expect(MatchStatus.values, contains(MatchStatus.upcoming));
      expect(MatchStatus.values, contains(MatchStatus.finished));
    });
  });

  group('Match model', () {
    test('constructs with all required fields', () {
      final match = Match(
        id: 'abc-123',
        leagueId: 'premier_league',
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        homeLogo: 'https://example.com/arsenal.png',
        awayLogo: 'https://example.com/chelsea.png',
        startTime: DateTime(2026, 3, 20, 20, 0),
        status: MatchStatus.live,
      );

      expect(match.id, 'abc-123');
      expect(match.leagueId, 'premier_league');
      expect(match.homeTeam, 'Arsenal');
      expect(match.awayTeam, 'Chelsea');
      expect(match.status, MatchStatus.live);
    });

    test('optional fields default to null/false', () {
      final match = Match(
        id: '1',
        leagueId: 'la_liga',
        homeTeam: 'Barcelona',
        awayTeam: 'Real Madrid',
        homeLogo: '',
        awayLogo: '',
        startTime: DateTime.now(),
        status: MatchStatus.upcoming,
      );

      expect(match.homeScore, isNull);
      expect(match.awayScore, isNull);
      expect(match.liveMinute, isNull);
      expect(match.leagueName, isNull);
      expect(match.leagueLogoUrl, isNull);
      expect(match.isFeatured, false);
      expect(match.isFavorite, false);
    });

    test('accepts optional league metadata fields', () {
      final match = Match(
        id: '2',
        leagueId: '142901',
        leagueName: 'Bundesliga',
        leagueLogoUrl: 'https://example.com/bundesliga.png',
        homeTeam: 'Bayern',
        awayTeam: 'Dortmund',
        homeLogo: '',
        awayLogo: '',
        startTime: DateTime.now(),
        status: MatchStatus.live,
        homeScore: '3',
        awayScore: '1',
        liveMinute: "65'",
      );

      expect(match.leagueName, 'Bundesliga');
      expect(match.leagueLogoUrl, 'https://example.com/bundesliga.png');
      expect(match.homeScore, '3');
      expect(match.awayScore, '1');
      expect(match.liveMinute, "65'");
    });

    test('isFeatured and isFavorite can be set', () {
      final match = Match(
        id: '3',
        leagueId: 'serie_a',
        homeTeam: 'Milan',
        awayTeam: 'Inter',
        homeLogo: '',
        awayLogo: '',
        startTime: DateTime.now(),
        status: MatchStatus.finished,
        isFeatured: true,
        isFavorite: true,
      );

      expect(match.isFeatured, true);
      expect(match.isFavorite, true);
    });
  });
}
