import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/match_provider.dart';

class FilterRow extends ConsumerWidget {
  const FilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFilter = ref.watch(matchStateProvider).activeFilter;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip(context, ref, 'Senin İçin ✨', activeFilter),
          _buildFilterChip(context, ref, 'Live 🔴', activeFilter),
          _buildFilterChip(context, ref, 'All', activeFilter),
          _buildFilterChip(context, ref, 'Finished', activeFilter),
          _buildFilterChip(context, ref, 'Starred ⭐', activeFilter),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, WidgetRef ref, String label, String activeFilter) {
    final isActive = activeFilter == label;
    return GestureDetector(
      onTap: () {
        ref.read(matchStateProvider.notifier).setFilter(label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? context.colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? context.colors.primary : context.colors.surfaceVariant,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? context.colors.onPrimaryContainer : context.colors.textMedium,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
