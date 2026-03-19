import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ProgressTopLine extends StatelessWidget {
  final double progress; // 0.0 to 1.0

  const ProgressTopLine({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      width: double.infinity,
      color: AppTheme.surfaceContainerHigh,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          color: AppTheme.primaryContainer,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(color: AppTheme.primaryContainer.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
