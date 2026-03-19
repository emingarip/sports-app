import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class SelectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const SelectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryContainer.withOpacity(0.1) : AppTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppTheme.primaryContainer : AppTheme.surfaceContainerHighest,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected 
            ? [BoxShadow(color: AppTheme.primaryContainer.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))]
            : [BoxShadow(color: AppTheme.textHigh.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              icon!,
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppTheme.primary : AppTheme.textHigh,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppTheme.textMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppTheme.primaryContainer : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryContainer : AppTheme.surfaceContainerHighest,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Center(child: Icon(Icons.check, size: 16, color: AppTheme.onPrimaryContainer))
                  : null,
            )
          ],
        ),
      ),
    );
  }
}
