import 'package:flutter/material.dart';

class AppTheme {
  // Define colors from Stitch design
  static const Color background = Color(0xFFF3F7FB);
  static const Color surfaceContainerLow = Color(0xFFECF1F6);
  static const Color surfaceContainer = Color(0xFFE3E9EE);
  static const Color surfaceContainerHigh = Color(0xFFDDE3E8);
  static const Color surfaceContainerHighest = Color(0xFFD7DEE3);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  
  static const Color primaryContainer = Color(0xFFFFD709);
  static const Color onPrimaryContainer = Color(0xFF5B4B00);
  static const Color primary = Color(0xFF6C5A00);
  static const Color outline = Color(0xFF7E775F);
  
  static const Color secondaryContainer = Color(0xFFE5E2E1);
  static const Color secondary = Color(0xFF5C5B5B);
  
  static const Color error = Color(0xFFB02500);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  static const Color textHigh = Color(0xFF2A2F32);
  static const Color textMedium = Color(0xFF575C60);
  static const Color textLow = Color(0xFF73777B);
  
  static const Color accent = Color(0xFFFACC15); // Yellow accent
  static const Color success = Color(0xFF16A34A); // Green success
  static const Color surface = Color(0xFFFFFFFF); // White surface
  static const Color surfaceVariant = Color(0xFFE3E9EE); // Gray surface
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        background: background,
        surface: background,
        surfaceVariant: surfaceContainerLow,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondaryContainer: secondaryContainer,
        error: error,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        displayMedium: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        displaySmall: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        headlineLarge: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        headlineSmall: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: textHigh),
        titleMedium: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, color: textHigh),
        bodyLarge: TextStyle(color: textHigh),
        bodyMedium: TextStyle(color: textMedium),
        labelLarge: TextStyle(fontWeight: FontWeight.bold, color: textHigh),
      ),
    );
  }
}
