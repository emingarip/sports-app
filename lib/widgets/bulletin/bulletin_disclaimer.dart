import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Responsible-play footer shown on all bulletin screens.
class BulletinDisclaimer extends StatelessWidget {
  const BulletinDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        '18+ | Bu ekran analiz amaçlıdır; bahis oynatmaz. '
        'Sorumlu oyun: oynamayı bırakamıyorsanız destek alın.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.colors.textLow,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }
}
