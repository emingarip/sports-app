import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/navigation_provider.dart';
import '../providers/match_provider.dart';
import 'package:intl/intl.dart';

class CustomBottomNav extends ConsumerStatefulWidget {
  const CustomBottomNav({super.key});

  @override
  ConsumerState<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends ConsumerState<CustomBottomNav> {
  late final ScrollController _calendarScroller;

  @override
  void initState() {
    super.initState();
    _calendarScroller = ScrollController();
  }

  @override
  void dispose() {
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
          final difference = selectedDate.difference(DateTime(now.year, now.month, now.day)).inDays;
          
          final screenWidth = MediaQuery.of(context).size.width;
          final containerWidth = (screenWidth > 600 ? 600.0 : screenWidth) - 32.0;
          final targetIndex = 10000 + difference;
          final targetOffset = (targetIndex * 64.0) - (containerWidth / 2) + 32.0;

          _calendarScroller.jumpTo(targetOffset);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationProvider);
    final selectedDate = ref.watch(matchStateProvider).selectedDate;
    final _showCalendarOverlay = ref.watch(calendarOverlayProvider);
    
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: 180, // Critical: Forces hit-test bounds to include the floating overlay
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Horizontal Calendar Overlay
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              bottom: _showCalendarOverlay ? 90.0 : -80.0,
              left: 16.0,
              right: 16.0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showCalendarOverlay ? 1.0 : 0.0,
                // Critical: Added IgnorePointer conditional to absolutely prevent ghost clicks 
                // when hidden beneath bottom bounds.
                child: IgnorePointer(
                  ignoring: !_showCalendarOverlay,
                  child: _buildHorizontalCalendarOverlay(selectedDate),
                ),
              ),
            ),

            // Main Navigation Bar
            Padding(
              padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E).withOpacity(0.95),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, 5))
                  ],
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(currentIndex, 0, "Matches", Icons.sports_soccer),
                    _buildNavItem(currentIndex, 1, "Insights", Icons.query_stats),
                    _buildNavItem(currentIndex, 2, "Market", Icons.analytics),
                    _buildNavItem(currentIndex, 3, "Ranking", Icons.emoji_events),
                    _buildDateItem(selectedDate),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
              color: const Color(0xFF1E1E1E).withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, -4))
              ]
            ),
            child: Stack(
            alignment: Alignment.center,
            children: [
              NotificationListener<ScrollEndNotification>(
                onNotification: (notification) {
                  // Snap effect: Calculate nearest item (64px width)
                  final position = _calendarScroller.position.pixels;
                  final screenWidth = MediaQuery.of(context).size.width;
                  final containerWidth = (screenWidth > 600 ? 600.0 : screenWidth) - 32.0;
                  
                  // The item in the absolute center
                  final centerOffset = position + (containerWidth / 2) - 32.0;
                  final nearestIndex = (centerOffset / 64.0).round();
                  
                  final int offsetFromToday = nearestIndex - 10000;
                  final snapDate = now.add(Duration(days: offsetFromToday));

                  // If snapped date is different from selected date, automatically select it!
                  if (snapDate.difference(selectedDate).inDays != 0) {
                      HapticFeedback.selectionClick();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                          ref.read(matchStateProvider.notifier).setDate(snapDate);
                      });
                  }

                  // Animate physical scroll structurally onto the exact centered pixel
                  final targetOffset = (nearestIndex * 64.0) - (containerWidth / 2) + 32.0;
                  Future.microtask(() {
                    if (_calendarScroller.hasClients) {
                      _calendarScroller.animateTo(
                        targetOffset.clamp(0.0, _calendarScroller.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  });
                  return false;
                },
                child: ListView.builder(
                  controller: _calendarScroller,
                  scrollDirection: Axis.horizontal,
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

                    String dayName = DateFormat('E').format(date).toUpperCase();
                    String dayNum = DateFormat('d').format(date);
                    
                    if (isToday) dayName = "TDY";

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(matchStateProvider.notifier).setDate(date);

                        // Keep it open, but gently center it
                        final screenWidth = MediaQuery.of(context).size.width;
                        final containerWidth = (screenWidth > 600 ? 600.0 : screenWidth) - 32.0;
                        final targetOffset = (index * 64.0) - (containerWidth / 2) + 32.0;

                        _calendarScroller.animateTo(
                           targetOffset.clamp(0.0, _calendarScroller.position.maxScrollExtent), 
                           duration: const Duration(milliseconds: 300), 
                           curve: Curves.easeInOut
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayName,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                                color: isSelected ? const Color(0xFFFACC15) : context.colors.textMedium,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dayNum,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: isSelected ? const Color(0xFFFACC15) : context.colors.textHigh,
                              ),
                            ),
                          ],
                        ),
                      )
                    );
                  },
                ),
              ),
              
              // Fixed Selection Reticle Window
              IgnorePointer(
                child: Container(
                  width: 56,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.5), width: 1.5),
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

  Widget _buildDateItem(DateTime date) {
    bool isToday = date.year == DateTime.now().year && date.month == DateTime.now().month && date.day == DateTime.now().day;
    String dayPrefix = isToday ? "TDY" : DateFormat('d').format(date);
    String monthStr = DateFormat('MMM').format(date).toUpperCase();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Fast reset to "Today" if tapped while closed, or simply close if already today
        final _showCalendarOverlay = ref.read(calendarOverlayProvider);
        if (!isToday) {
          HapticFeedback.mediumImpact();
          final now = DateTime.now();
          ref.read(matchStateProvider.notifier).setDate(DateTime(now.year, now.month, now.day));
        } else if (_showCalendarOverlay) {
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
      onHorizontalDragEnd: (details) {
        // Quick swipe logic for extreme power-users without ever opening the UI
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -300) {
            // Swipe Left -> Next Day
            HapticFeedback.lightImpact();
            ref.read(matchStateProvider.notifier).setDate(date.add(const Duration(days: 1)));
          } else if (details.primaryVelocity! > 300) {
            // Swipe Right -> Previous Day
            HapticFeedback.lightImpact();
            ref.read(matchStateProvider.notifier).setDate(date.subtract(const Duration(days: 1)));
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: ref.watch(calendarOverlayProvider) ? context.colors.primaryContainer.withOpacity(0.3) : const Color(0xFFFACC15).withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BouncingChevron(),
            const Icon(
              Icons.calendar_month, 
              color: Color(0xFFFACC15), 
              size: 20
            ),
            const SizedBox(height: 2),
            Text(
              "$dayPrefix $monthStr",
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Color(0xFFFACC15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int currentIndex, int index, String label, IconData icon) {
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
          color: isSelected ? context.colors.primaryContainer.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              color: isSelected ? context.colors.primary : context.colors.textMedium.withOpacity(0.7), 
              size: isSelected ? 22 : 20
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isSelected ? context.colors.primary : context.colors.textMedium.withOpacity(0.7),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _BouncingChevron extends StatefulWidget {
  const _BouncingChevron();
  @override
  State<_BouncingChevron> createState() => _BouncingChevronState();
}

class _BouncingChevronState extends State<_BouncingChevron> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -3 * _controller.value),
          child: const Icon(Icons.keyboard_arrow_up, color: Color(0x88FACC15), size: 16),
        );
      },
    );
  }
}
