import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../providers/match_provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class CustomBottomNav extends ConsumerStatefulWidget {
  const CustomBottomNav({super.key});

  @override
  ConsumerState<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends ConsumerState<CustomBottomNav>
    with SingleTickerProviderStateMixin {
  late final ScrollController _calendarScroller;
  late final AnimationController _hintController;
  static const double _dateSwipeThreshold = 18.0;
  double _dateItemHorizontalDragDistance = 0.0;
  bool _isHintAnimationActive = false;

  @override
  void initState() {
    super.initState();
    _calendarScroller = ScrollController();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() {
        _isHintAnimationActive = true;
      });
      _hintController.repeat();
    });
  }

  @override
  void dispose() {
    _hintController.dispose();
    _calendarScroller.dispose();
    super.dispose();
  }

  void _setCalendarState(bool isVisible) {
    if (ref.read(calendarOverlayProvider) == isVisible) return;
    HapticFeedback.lightImpact();
    ref.read(calendarOverlayProvider.notifier).setState(isVisible);

    if (isVisible) {
      // Auto-focus the calendar on the currently selected date in global state
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_calendarScroller.hasClients) {
          final now = DateTime.now();
          final selectedDate = ref.read(matchStateProvider).selectedDate;
          final difference = selectedDate
              .difference(DateTime(now.year, now.month, now.day))
              .inDays;

          final screenWidth = MediaQuery.of(context).size.width;
          final containerWidth =
              (screenWidth > 600 ? 600.0 : screenWidth) - 32.0;
          final targetIndex = 10000 + difference;
          final targetOffset =
              (targetIndex * 64.0) - (containerWidth / 2) + 32.0;

          _calendarScroller.jumpTo(targetOffset);
        }
      });
    }
  }

  void _shiftSelectedDate(DateTime date, int dayOffset) {
    HapticFeedback.lightImpact();
    ref.read(matchStateProvider.notifier).setDate(
          date.add(Duration(days: dayOffset)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationProvider);
    final selectedDate = ref.watch(matchStateProvider).selectedDate;
    final showCalendarOverlay = ref.watch(calendarOverlayProvider);

    return AnimatedBuilder(
      animation: _hintController,
      builder: (context, child) {
        final shouldAnimateHints =
            !showCalendarOverlay && _isHintAnimationActive;
        final hintCycleProgress =
            shouldAnimateHints ? _hintController.value : 1.0;
        final hintProgress =
            shouldAnimateHints ? math.sin(hintCycleProgress * math.pi) : 0.0;

        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height:
                180, // Critical: Forces hit-test bounds to include the floating overlay
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // Horizontal Calendar Overlay
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  bottom: showCalendarOverlay ? 90.0 : -80.0,
                  left: 16.0,
                  right: 16.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: showCalendarOverlay ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !showCalendarOverlay,
                      child: _buildHorizontalCalendarOverlay(selectedDate),
                    ),
                  ),
                ),

                // Main Navigation Bar
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color:
                          context.colors.navBackground.withValues(alpha: 0.95),
                      boxShadow: [
                        BoxShadow(
                            color: context.colors.cardShadow
                                .withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                            offset: const Offset(0, 5))
                      ],
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavItem(
                            currentIndex, 0, "Matches", Icons.sports_soccer),
                        _buildNavItem(
                            currentIndex, 1, "Insights", Icons.query_stats),
                        _buildNavItem(
                            currentIndex, 2, "Market", Icons.analytics),
                        _buildNavItem(
                            currentIndex, 3, "Ranking", Icons.emoji_events),
                        _buildDateItem(
                          selectedDate,
                          showCalendarOverlay: showCalendarOverlay,
                          hintProgress: hintProgress,
                          hintCycleProgress: hintCycleProgress,
                          showHintArrows: shouldAnimateHints,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorizontalCalendarOverlay(DateTime selectedDate) {
    final now = DateTime.now();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: GestureDetector(
          onVerticalDragUpdate: (details) {
            if (details.delta.dy > 5 || details.delta.dy < -5) {
              _setCalendarState(false);
            }
          },
          child: Container(
            height: 64,
            decoration: BoxDecoration(
                color:
                    context.colors.navBackgroundOverlay.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: context.colors.navInactive.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                      color: context.colors.cardShadow.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, -4)),
                ]),
            child: Stack(
              alignment: Alignment.center,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Only run snap if user has actually lifted their finger AND stopped moving.
                    if (notification is UserScrollNotification &&
                        notification.direction == ScrollDirection.idle) {
                      final position = _calendarScroller.position.pixels;
                      final screenWidth = MediaQuery.of(context).size.width;
                      final containerWidth =
                          (screenWidth > 600 ? 600.0 : screenWidth) - 32.0;

                      final centerOffset =
                          position + (containerWidth / 2) - 32.0;
                      final nearestIndex = (centerOffset / 64.0).round();

                      final targetOffset =
                          (nearestIndex * 64.0) - (containerWidth / 2) + 32.0;

                      if ((position - targetOffset).abs() > 1.0) {
                        Future.microtask(() {
                          if (_calendarScroller.hasClients) {
                            _calendarScroller.animateTo(
                              targetOffset.clamp(0.0,
                                  _calendarScroller.position.maxScrollExtent),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        });
                      }

                      final int offsetFromToday = nearestIndex - 10000;
                      final snapDate = now.add(Duration(days: offsetFromToday));

                      if (snapDate.difference(selectedDate).inDays != 0) {
                        HapticFeedback.selectionClick();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ref
                              .read(matchStateProvider.notifier)
                              .setDate(snapDate);
                        });
                      }
                    }
                    return false;
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad
                      },
                    ),
                    child: ListView.builder(
                      controller: _calendarScroller,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemExtent: 64.0,
                      itemCount: 20000,
                      itemBuilder: (context, index) {
                        final int offsetFromToday = index - 10000;
                        final date = now.add(Duration(days: offsetFromToday));

                        final isSelected = date.year == selectedDate.year &&
                            date.month == selectedDate.month &&
                            date.day == selectedDate.day;

                        final isToday = date.year == now.year &&
                            date.month == now.month &&
                            date.day == now.day;

                        String dayName =
                            DateFormat('E').format(date).toUpperCase();
                        String dayNum = DateFormat('d').format(date);

                        if (isToday) dayName = "TDY";

                        return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ref
                                  .read(matchStateProvider.notifier)
                                  .setDate(date);

                              final screenWidth =
                                  MediaQuery.of(context).size.width;
                              final containerWidth =
                                  (screenWidth > 600 ? 600.0 : screenWidth) -
                                      32.0;
                              final targetOffset =
                                  (index * 64.0) - (containerWidth / 2) + 32.0;

                              _calendarScroller.animateTo(
                                  targetOffset.clamp(
                                      0.0,
                                      _calendarScroller
                                          .position.maxScrollExtent),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    dayName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isSelected
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: isSelected
                                          ? context.colors.navSelected
                                          : context.colors.navInactive
                                              .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dayNum,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: isSelected
                                          ? context.colors.navSelected
                                          : context.colors.navInactive
                                              .withValues(alpha: 0.92),
                                    ),
                                  ),
                                ],
                              ),
                            ));
                      },
                    ),
                  ),
                ),

                // Fixed Selection Reticle Window
                IgnorePointer(
                  child: Container(
                    width: 56,
                    height: 48,
                    decoration: BoxDecoration(
                      color: context.colors.navAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color:
                              context.colors.navAccent.withValues(alpha: 0.5),
                          width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateItem(
    DateTime date, {
    required bool showCalendarOverlay,
    required double hintProgress,
    required double hintCycleProgress,
    required bool showHintArrows,
  }) {
    bool isToday = date.year == DateTime.now().year &&
        date.month == DateTime.now().month &&
        date.day == DateTime.now().day;
    String dayPrefix =
        isToday ? "TODAY" : DateFormat('E').format(date).toUpperCase();
    String dayNumber = DateFormat('d').format(date);
    String monthStr = DateFormat('MMM').format(date).toUpperCase();
    const chipLift = 0.0;
    final chipScale =
        showCalendarOverlay ? 1.0 : lerpDouble(1.0, 1.02, hintProgress)!;
    const contentLift = 0.0;
    final fillOpacity =
        showCalendarOverlay ? 0.30 : lerpDouble(0.14, 0.24, hintProgress)!;
    final borderOpacity =
        showCalendarOverlay ? 0.45 : lerpDouble(0.30, 0.54, hintProgress)!;
    final glowOpacity =
        showCalendarOverlay ? 0.16 : lerpDouble(0.08, 0.18, hintProgress)!;
    final highlightOpacity =
        showCalendarOverlay ? 0.0 : lerpDouble(0.12, 0.28, hintProgress)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Fast reset to "Today" if tapped while closed, or simply close if already today
        final showCalendarOverlay = ref.read(calendarOverlayProvider);
        if (!isToday) {
          HapticFeedback.mediumImpact();
          final now = DateTime.now();
          ref
              .read(matchStateProvider.notifier)
              .setDate(DateTime(now.year, now.month, now.day));
        } else if (showCalendarOverlay) {
          _setCalendarState(false);
        }
      },
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -5) {
          // Swipe Up -> Open Calendar (Trigger safe; avoids spam internally)
          _setCalendarState(true);
        } else if (details.delta.dy > 5) {
          // Swipe Down -> Close Calendar
          _setCalendarState(false);
        }
      },
      onHorizontalDragStart: (_) {
        _dateItemHorizontalDragDistance = 0.0;
      },
      onHorizontalDragUpdate: (details) {
        _dateItemHorizontalDragDistance += details.primaryDelta ?? 0.0;
      },
      onHorizontalDragEnd: (_) {
        if (_dateItemHorizontalDragDistance <= -_dateSwipeThreshold) {
          // Swipe Left -> Next Day
          _shiftSelectedDate(date, 1);
        } else if (_dateItemHorizontalDragDistance >= _dateSwipeThreshold) {
          // Swipe Right -> Previous Day
          _shiftSelectedDate(date, -1);
        }
        _dateItemHorizontalDragDistance = 0.0;
      },
      child: Transform.translate(
        offset: const Offset(0, chipLift),
        child: Transform.scale(
          scale: chipScale,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _buildSwipeHintArrow(
                cycleProgress: hintCycleProgress,
                startFraction: 0.00,
                isHidden: !showHintArrows,
                size: 24,
                peakOpacity: 0.78,
              ),
              _buildSwipeHintArrow(
                cycleProgress: hintCycleProgress,
                startFraction: 0.14,
                isHidden: !showHintArrows,
                size: 20,
                peakOpacity: 0.60,
              ),
              _buildSwipeHintArrow(
                cycleProgress: hintCycleProgress,
                startFraction: 0.28,
                isHidden: !showHintArrows,
                size: 16,
                peakOpacity: 0.42,
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                constraints: const BoxConstraints(minWidth: 78),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      context.colors.navAccent.withValues(alpha: fillOpacity),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: context.colors.navAccent
                        .withValues(alpha: borderOpacity),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          context.colors.navGlow.withValues(alpha: glowOpacity),
                      blurRadius: lerpDouble(10, 18, hintProgress)!,
                      spreadRadius: lerpDouble(0.0, 1.0, hintProgress)!,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  context.colors.navSelected.withValues(
                                    alpha: highlightOpacity,
                                  ),
                                  context.colors.navAccent.withValues(
                                    alpha: highlightOpacity * 0.65,
                                  ),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.36, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, contentLift),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dayPrefix,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: context.colors.navSelected,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              "$dayNumber $monthStr",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                                color: context.colors.navSelected,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeHintArrow({
    required double cycleProgress,
    required double startFraction,
    required bool isHidden,
    required double size,
    required double peakOpacity,
  }) {
    if (isHidden) {
      return const SizedBox.shrink();
    }

    const activeWindow = 0.34;
    final phasedProgress = cycleProgress - startFraction;

    if (phasedProgress < 0.0 || phasedProgress > activeWindow) {
      return const SizedBox.shrink();
    }

    final localProgress = (phasedProgress / activeWindow).clamp(0.0, 1.0);
    final travelProgress = Curves.easeOutCubic.transform(localProgress);
    final opacity = localProgress < 0.18
        ? lerpDouble(0.0, peakOpacity, localProgress / 0.18)!
        : lerpDouble(peakOpacity, 0.0, (localProgress - 0.18) / 0.82)!;
    final bottom = lerpDouble(-12.0, 30.0, travelProgress)!;
    final scale = lerpDouble(0.86, 1.04, travelProgress)!;

    return Positioned(
      bottom: bottom,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              color: context.colors.navAccent,
              size: size,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int currentIndex, int index, String label, IconData icon) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isSelected) return;
        ref.read(navigationProvider.notifier).setIndex(index);

        // Ensure calendar overlay hides when switching primary tabs
        if (ref.read(calendarOverlayProvider)) {
          ref.read(calendarOverlayProvider.notifier).setState(false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colors.navAccent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isSelected
                    ? context.colors.navSelected
                    : context.colors.navInactive.withValues(alpha: 0.65),
                size: isSelected ? 22 : 20),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isSelected
                    ? context.colors.navSelected
                    : context.colors.navInactive.withValues(alpha: 0.65),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
