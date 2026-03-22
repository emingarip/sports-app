import 'package:sports_app/models/match.dart';
import 'package:sports_app/models/league.dart';

/// Factory to create test Match objects with sensible defaults.
Match createTestMatch({
  String id = 'test-match-1',
  String leagueId = 'premier_league',
  String? leagueName = 'Premier League',
  String? leagueLogoUrl = 'https://example.com/pl.png',
  String homeTeam = 'Arsenal',
  String awayTeam = 'Chelsea',
  String homeLogo = 'https://example.com/arsenal.png',
  String awayLogo = 'https://example.com/chelsea.png',
  DateTime? startTime,
  MatchStatus status = MatchStatus.live,
  String? homeScore = '2',
  String? awayScore = '1',
  String? liveMinute = "45'",
  bool isFeatured = false,
  bool isFavorite = false,
}) {
  return Match(
    id: id,
    leagueId: leagueId,
    leagueName: leagueName,
    leagueLogoUrl: leagueLogoUrl,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    homeLogo: homeLogo,
    awayLogo: awayLogo,
    startTime: startTime ?? DateTime(2026, 3, 20, 20, 0),
    status: status,
    homeScore: homeScore,
    awayScore: awayScore,
    liveMinute: liveMinute,
    isFeatured: isFeatured,
    isFavorite: isFavorite,
  );
}

/// Factory to create test League objects with sensible defaults.
League createTestLeague({
  String id = 'premier_league',
  String name = 'Premier League',
  String logoUrl = 'https://example.com/pl.png',
  int tier = 1,
}) {
  return League(id: id, name: name, logoUrl: logoUrl, tier: tier);
}
