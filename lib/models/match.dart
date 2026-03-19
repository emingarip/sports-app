enum MatchStatus { live, upcoming, finished }

class Match {
  final String id;
  final String leagueId;
  final String homeTeam;
  final String awayTeam;
  final String homeLogo;
  final String awayLogo;
  final DateTime startTime;
  final MatchStatus status;
  final String? homeScore;
  final String? awayScore;
  final String? liveMinute;
  final bool isFeatured;
  final bool isFavorite;

  const Match({
    required this.id,
    required this.leagueId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeLogo,
    required this.awayLogo,
    required this.startTime,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.liveMinute,
    this.isFeatured = false,
    this.isFavorite = false,
  });
}
