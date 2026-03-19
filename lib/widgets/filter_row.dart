import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FilterRow extends StatelessWidget {
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;

  const FilterRow({
    super.key,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('All'),
          _buildFilterChip('Live 🔴'),
          _buildFilterChip('Starred ⭐'),
          _buildFilterChip('Finished'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () => onFilterChanged(label),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceContainerHigh.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.surfaceContainerLowest : AppTheme.textHigh,
            ),
          ),
        ),
      ),
    );
  }
}
