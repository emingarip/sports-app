import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class OnboardingBottomBar extends StatelessWidget {
  final String primaryText;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryText;
  final VoidCallback? onSecondaryPressed;
  final bool isSecondaryDestructive;

  const OnboardingBottomBar({
    super.key,
    required this.primaryText,
    this.onPrimaryPressed,
    this.secondaryText,
    this.onSecondaryPressed,
    this.isSecondaryDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: context.colors.background,
        boxShadow: [
          BoxShadow(
            color: context.colors.surfaceContainerLowest.withOpacity(0.8),
            blurRadius: 20,
            offset: const Offset(0, -10),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: onPrimaryPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryContainer,
                  foregroundColor: context.colors.onPrimaryContainer,
                  disabledBackgroundColor: context.colors.surfaceContainerHigh,
                  disabledForegroundColor: context.colors.textMedium.withOpacity(0.5),
                  elevation: onPrimaryPressed == null ? 0 : 4,
                  shadowColor: context.colors.primaryContainer.withOpacity(0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  textStyle: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                child: Text(primaryText.toUpperCase()),
              ),
            ),
            if (secondaryText != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onSecondaryPressed,
                style: TextButton.styleFrom(
                  foregroundColor: isSecondaryDestructive ? context.colors.error : context.colors.textMedium,
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(secondaryText!),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
