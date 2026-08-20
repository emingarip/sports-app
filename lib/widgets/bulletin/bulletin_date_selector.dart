import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

const List<String> _turkishWeekdaysShort = [
  'Pzt',
  'Sal',
  'Çar',
  'Per',
  'Cum',
  'Cmt',
  'Paz',
];

/// Horizontal day selector for the bulletin (today +/- [dayRange] days).
class BulletinDateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final int dayRange;

  const BulletinDateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.dayRange = 3,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dayRange * 2 + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = today.add(Duration(days: index - dayRange));
          final isSelected = date.year == selectedDate.year &&
              date.month == selectedDate.month &&
              date.day == selectedDate.day;
          final isToday = date == today;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onDateSelected(date);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected
                    ? context.colors.chipSelectedBackground
                    : context.colors.chipBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? context.colors.accent.withValues(alpha: 0.6)
                      : context.colors.outline.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isToday
                        ? 'Bugün'
                        : _turkishWeekdaysShort[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? context.colors.chipSelectedForeground
                          : context.colors.textMedium,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? context.colors.chipSelectedForeground
                          : context.colors.textHigh,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
