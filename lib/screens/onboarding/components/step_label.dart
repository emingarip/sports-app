import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class StepLabel extends StatelessWidget {
  final int step;
  final int totalSteps;

  const StepLabel({super.key, required this.step, this.totalSteps = 5});

  @override
  Widget build(BuildContext context) {
    return Text(
      "STEP $step OF $totalSteps",
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        color: context.colors.textMedium,
      ),
    );
  }
}
