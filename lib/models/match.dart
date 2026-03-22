enum MatchStatus { live, upcoming, finished }

class Match {
  final String id;
  final String leagueId;
  final String? leagueName;
  final String? leagueLogoUrl;
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

  Match({
    required this.id,
    required this.leagueId,
    this.leagueName,
    this.leagueLogoUrl,
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
