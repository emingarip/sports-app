import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingState {
  final Set<String> selectedTeams;
  final Set<String> selectedCompetitions;

  OnboardingState({
    required this.selectedTeams,
    required this.selectedCompetitions,
  });

  OnboardingState copyWith({
    Set<String>? selectedTeams,
    Set<String>? selectedCompetitions,
  }) {
    return OnboardingState(
      selectedTeams: selectedTeams ?? this.selectedTeams,
      selectedCompetitions: selectedCompetitions ?? this.selectedCompetitions,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    return OnboardingState(
      selectedTeams: {},
      selectedCompetitions: {},
    );
  }

  void toggleTeam(String teamName) {
    if (state.selectedTeams.contains(teamName)) {
      state = state.copyWith(
        selectedTeams: {...state.selectedTeams}..remove(teamName),
      );
    } else {
      state = state.copyWith(
        selectedTeams: {...state.selectedTeams, teamName},
      );
    }
  }

  void toggleCompetition(String compName) {
    if (state.selectedCompetitions.contains(compName)) {
      state = state.copyWith(
        selectedCompetitions: {...state.selectedCompetitions}..remove(compName),
      );
    } else {
      state = state.copyWith(
        selectedCompetitions: {...state.selectedCompetitions, compName},
      );
    }
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(() {
  return OnboardingNotifier();
});
