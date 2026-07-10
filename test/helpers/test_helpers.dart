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
  String? statusDescription,
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
    statusDescription: statusDescription,
    isFeatured: isFeatured,
    isFavorite: isFavorite,
  );
}

/// Dashboard providers only surface matches whose start time falls on the
/// selected calendar day, so tests deriving times from `DateTime.now()` break
/// when an offset crosses midnight. These helpers keep derived times inside
/// `now`'s day while preserving the intent of the offset.

/// A start time [fromNow] ahead of [now], pulled back to the last moment of
/// [now]'s day when the offset would land on the next day.
DateTime upcomingStartToday(DateTime now, Duration fromNow) {
  final endOfDay = DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 1))
      .subtract(const Duration(milliseconds: 1));
  final candidate = now.add(fromNow);
  return candidate.isAfter(endOfDay) ? endOfDay : candidate;
}

/// A reference instant inside [now]'s day, at least [margin] away from both
/// midnights. Build past/finished match times against this anchor so they
/// stay on today's date even when the suite runs just after midnight.
DateTime todayAnchor(DateTime now,
    {Duration margin = const Duration(hours: 4)}) {
  final startOfDay = DateTime(now.year, now.month, now.day);
  final earliest = startOfDay.add(margin);
  final latest = startOfDay.add(const Duration(hours: 24) - margin);
  if (now.isBefore(earliest)) return earliest;
  if (now.isAfter(latest)) return latest;
  return now;
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
