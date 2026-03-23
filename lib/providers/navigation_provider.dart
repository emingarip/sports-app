import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavigationNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index;
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, int>(NavigationNotifier.new);

class CalendarOverlayNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setState(bool isVisible) {
    state = isVisible;
  }
}

final calendarOverlayProvider = NotifierProvider<CalendarOverlayNotifier, bool>(CalendarOverlayNotifier.new);
