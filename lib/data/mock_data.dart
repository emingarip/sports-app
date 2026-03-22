import '../models/match.dart';
import '../models/league.dart';

class MockData {
  static final List<League> leagues = [
    League(id: 'premier_league', name: 'Premier League', logoUrl: 'https://upload.wikimedia.org/wikipedia/en/thumb/f/f2/Premier_League_Logo.svg/1200px-Premier_League_Logo.svg.png', tier: 1),
    League(id: 'la_liga', name: 'La Liga', logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/LaLiga.svg/1200px-LaLiga.svg.png', tier: 1),
    League(id: 'serie_a', name: 'Serie A', logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Serie_A_logo_%282022%29.svg/1200px-Serie_A_logo_%282022%29.svg.png', tier: 1),
    League(id: 'bundesliga', name: 'Bundesliga', logoUrl: 'https://upload.wikimedia.org/wikipedia/en/d/df/Bundesliga_logo_%282017%29.svg', tier: 1),
    League(id: 'league_two', name: 'English League Two', logoUrl: 'https://upload.wikimedia.org/wikipedia/en/thumb/f/f2/Premier_League_Logo.svg/1200px-Premier_League_Logo.svg.png', tier: 2),
    League(id: 'super_lig', name: 'Süper Lig', logoUrl: 'https://upload.wikimedia.org/wikipedia/tr/b/b3/T%C3%BCrkiye_S%C3%BCper_Lig_Logo.png', tier: 2),
  ];

  static List<Match> getMatches() {
    List<Match> matches = [];
    
    // 1. Featured Match
    matches.add(Match(
      id: 'm_featured_1',
      leagueId: 'la_liga',
      homeTeam: 'R. Madrid',
      awayTeam: 'Barcelona',
      homeLogo: 'https://upload.wikimedia.org/wikipedia/en/thumb/5/56/Real_Madrid_CF.svg/1200px-Real_Madrid_CF.svg.png',
      awayLogo: 'https://upload.wikimedia.org/wikipedia/en/thumb/4/47/FC_Barcelona_%28crest%29.svg/1200px-FC_Barcelona_%28crest%29.svg.png',
      startTime: DateTime.now().add(const Duration(hours: 2)),
      status: MatchStatus.upcoming,
      isFeatured: true,
      isFavorite: true,
    ));

    // 2. Generate large dataset (50+ matches)
    for (int i = 0; i < leagues.length; i++) {
        String lId = leagues[i].id;
        for (int j = 0; j < 9; j++) {
            MatchStatus status;
            bool isFav = false;
            String? homeS;
            String? awayS;
            String? liveM;
            DateTime time;

            if (j < 2) {
                // Live matches
                status = MatchStatus.live;
                homeS = (j).toString();
                awayS = (j+1).toString();
                liveM = "${70 + j}'";
                isFav = (i == 0 && j == 1); // Random favoriting
                time = DateTime.now().subtract(const Duration(minutes: 70));
            } else if (j < 6) {
                // Upcoming
                status = MatchStatus.upcoming;
                time = DateTime.now().add(Duration(hours: j));
            } else {
                // Finished
                status = MatchStatus.finished;
                homeS = '2';
                awayS = '0';
                time = DateTime.now().subtract(Duration(hours: 5 + j));
            }

            matches.add(Match(
                id: 'm_${i}_$j',
                leagueId: lId,
                homeTeam: 'Home $i$j',
                awayTeam: 'Away $i$j',
                homeLogo: 'https://upload.wikimedia.org/wikipedia/en/thumb/5/53/Arsenal_FC.svg/1200px-Arsenal_FC.svg.png',
                awayLogo: 'https://upload.wikimedia.org/wikipedia/en/thumb/c/cc/Chelsea_FC.svg/1200px-Chelsea_FC.svg.png',
                startTime: time,
                status: status,
                homeScore: homeS,
                awayScore: awayS,
                liveMinute: liveM,
                isFavorite: isFav,
            ));
        }
    }
    return matches;
  }
}
