import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-navigation slots, named so cross-tab jumps do not hard-code
/// integers that silently break when the order changes.
const int matchesTabIndex = 0;
const int couponTabIndex = 1;
const int bulletinTabIndex = 2;
const int leaderboardTabIndex = 3;
const int profileTabIndex = 4;

class NavigationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index;
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, int>(
  NavigationNotifier.new,
  name: 'navigationProvider',
);

class CalendarOverlayNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setState(bool isVisible) {
    state = isVisible;
  }
}

final calendarOverlayProvider = NotifierProvider<CalendarOverlayNotifier, bool>(
  CalendarOverlayNotifier.new,
  name: 'calendarOverlayProvider',
);
