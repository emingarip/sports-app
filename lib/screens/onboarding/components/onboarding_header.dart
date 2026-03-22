import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class OnboardingHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailingIcon;

  const OnboardingHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                  color: context.colors.textHigh,
                ),
              ),
            ),
            if (trailingIcon != null) trailingIcon!,
          ],
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: context.colors.textMedium,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
