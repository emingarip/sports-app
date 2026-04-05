import 'match.dart' as model;

enum MatchPriorityBucket {
  favoriteLive,
  liveCritical,
  liveOther,
  favoriteStartingSoon,
  startingSoon,
  favoriteLaterToday,
  laterToday,
  finished,
}

class MatchListItemViewModel {
  final model.Match match;
  final MatchPriorityBucket priorityBucket;
  final String? reasonLabel;
  final String statusLabel;
  final String? secondaryLabel;

  const MatchListItemViewModel({
    required this.match,
    required this.priorityBucket,
    required this.statusLabel,
    this.reasonLabel,
    this.secondaryLabel,
  });

  MatchListItemViewModel copyWith({
    model.Match? match,
    MatchPriorityBucket? priorityBucket,
    String? reasonLabel,
    bool clearReasonLabel = false,
    String? statusLabel,
    String? secondaryLabel,
    bool clearSecondaryLabel = false,
  }) {
    return MatchListItemViewModel(
      match: match ?? this.match,
      priorityBucket: priorityBucket ?? this.priorityBucket,
      reasonLabel: clearReasonLabel ? null : reasonLabel ?? this.reasonLabel,
      statusLabel: statusLabel ?? this.statusLabel,
      secondaryLabel:
          clearSecondaryLabel ? null : secondaryLabel ?? this.secondaryLabel,
    );
  }
}

class MatchSectionViewModel {
  final String title;
  final List<MatchListItemViewModel> items;
  final bool groupedByLeague;

  const MatchSectionViewModel({
    required this.title,
    required this.items,
    this.groupedByLeague = false,
  });
}

enum SearchMatchEntityType { team, league, mixed }

class SearchMatchResultViewModel {
  final model.Match match;
  final int score;
  final SearchMatchEntityType matchedEntityType;

  const SearchMatchResultViewModel({
    required this.match,
    required this.score,
    required this.matchedEntityType,
  });
}
