enum UserVoteType {
  none,
  agree,
  unsure,
  disagree,
}

class ConsensusData {
  final int agreePercent;
  final int unsurePercent;
  final int disagreePercent;
  final String? fanLabel;

  const ConsensusData({
    required this.agreePercent,
    required this.unsurePercent,
    required this.disagreePercent,
    this.fanLabel,
  });
}

class MatchInsight {
  final String id;
  final String label;
  final String text;
  final ConsensusData? consensusData;
  UserVoteType userVote;
  String? disagreeReason;
  String? customReason;

  MatchInsight({
    required this.id,
    required this.label,
    required this.text,
    this.consensusData,
    this.userVote = UserVoteType.none,
    this.disagreeReason,
    this.customReason,
  });

  bool get isAnswered => userVote != UserVoteType.none;
}
