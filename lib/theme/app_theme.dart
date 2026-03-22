import 'package:flutter/material.dart';

extension ThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceContainerLowest;
  
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color primary;
  final Color outline;
  
  final Color secondaryContainer;
  final Color secondary;
  
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color textHigh;
  final Color textMedium;
  final Color textLow;
  
  final Color accent;
  final Color success;
  final Color surface;
  final Color surfaceVariant;

  AppColors({
    required this.background,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceContainerLowest,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.primary,
    required this.outline,
    required this.secondaryContainer,
    required this.secondary,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.textHigh,
    required this.textMedium,
    required this.textLow,
    required this.accent,
    required this.success,
    required this.surface,
    required this.surfaceVariant,
  });

  @override
  ThemeExtension<AppColors> copyWith() => this;

  @override
  ThemeExtension<AppColors> lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surfaceContainerLow: Color.lerp(surfaceContainerLow, other.surfaceContainerLow, t)!,
      surfaceContainer: Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh: Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      surfaceContainerHighest: Color.lerp(surfaceContainerHighest, other.surfaceContainerHighest, t)!,
      surfaceContainerLowest: Color.lerp(surfaceContainerLowest, other.surfaceContainerLowest, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      secondaryContainer: Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      textHigh: Color.lerp(textHigh, other.textHigh, t)!,
      textMedium: Color.lerp(textMedium, other.textMedium, t)!,
      textLow: Color.lerp(textLow, other.textLow, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
    );
  }
}

class AppTheme {
  static AppColors lightColors = AppColors(
    background: const Color(0xFFF3F7FB),
    surfaceContainerLow: const Color(0xFFECF1F6),
    surfaceContainer: const Color(0xFFE3E9EE),
    surfaceContainerHigh: const Color(0xFFDDE3E8),
    surfaceContainerHighest: const Color(0xFFD7DEE3),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFFFFD709),
    onPrimaryContainer: const Color(0xFF5B4B00),
    primary: const Color(0xFF6C5A00),
    outline: const Color(0xFF7E775F),
    secondaryContainer: const Color(0xFFE5E2E1),
    secondary: const Color(0xFF5C5B5B),
    error: const Color(0xFFB02500),
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF93000A),
    textHigh: const Color(0xFF2A2F32),
    textMedium: const Color(0xFF575C60),
    textLow: const Color(0xFF73777B),
    accent: const Color(0xFFFACC15),
    success: const Color(0xFF16A34A),
    surface: const Color(0xFFFFFFFF),
    surfaceVariant: const Color(0xFFE3E9EE),
  );

  static AppColors darkColors = AppColors(
    background: const Color(0xFF131313),
    surfaceContainerLow: const Color(0xFF1c1b1b),
    surfaceContainer: const Color(0xFF201f1f),
    surfaceContainerHigh: const Color(0xFF2a2a2a),
    surfaceContainerHighest: const Color(0xFF353534),
    surfaceContainerLowest: const Color(0xFF0e0e0e),
    primaryContainer: const Color(0xFFFFD700),
    onPrimaryContainer: const Color(0xFF705e00),
    primary: const Color(0xFFfff6df),
    outline: const Color(0xFF999077),
    secondaryContainer: const Color(0xFF454749),
    secondary: const Color(0xFFc6c6c9),
    error: const Color(0xFFffb4ab),
    errorContainer: const Color(0xFF93000a),
    onErrorContainer: const Color(0xFFffdad6),
    textHigh: const Color(0xFFe5e2e1),
    textMedium: const Color(0xFFd0c6ab),
    textLow: const Color(0xFF999077),
    accent: const Color(0xFFe9c400),
    success: const Color(0xFF16A34A),
    surface: const Color(0xFF131313),
    surfaceVariant: const Color(0xFF353534),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: lightColors.background,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.light,
        seedColor: lightColors.primary,
        background: lightColors.background,
        surface: lightColors.background,
        surfaceVariant: lightColors.surfaceContainerLow,
        primaryContainer: lightColors.primaryContainer,
        onPrimaryContainer: lightColors.onPrimaryContainer,
        secondaryContainer: lightColors.secondaryContainer,
        error: lightColors.error,
        errorContainer: lightColors.errorContainer,
        onErrorContainer: lightColors.onErrorContainer,
      ),
      extensions: [lightColors],
      textTheme: TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        displayMedium: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        displaySmall: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        headlineLarge: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        headlineSmall: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: lightColors.textHigh),
        titleMedium: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, color: lightColors.textHigh),
        bodyLarge: TextStyle(color: lightColors.textHigh),
        bodyMedium: TextStyle(color: lightColors.textMedium),
        labelLarge: TextStyle(fontWeight: FontWeight.bold, color: lightColors.textHigh),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: darkColors.background,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: darkColors.primary,
        background: darkColors.background,
        surface: darkColors.background,
        surfaceVariant: darkColors.surfaceContainerLow,
        primaryContainer: darkColors.primaryContainer,
        onPrimaryContainer: darkColors.onPrimaryContainer,
        secondaryContainer: darkColors.secondaryContainer,
        error: darkColors.error,
        errorContainer: darkColors.errorContainer,
        onErrorContainer: darkColors.onErrorContainer,
      ),
      extensions: [darkColors],
      textTheme: TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        displayMedium: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        displaySmall: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        headlineLarge: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        headlineSmall: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: darkColors.textHigh),
        titleMedium: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
        titleSmall: TextStyle(fontWeight: FontWeight.w600, color: darkColors.textHigh),
        bodyLarge: TextStyle(color: darkColors.textHigh),
        bodyMedium: TextStyle(color: darkColors.textMedium),
        labelLarge: TextStyle(fontWeight: FontWeight.bold, color: darkColors.textHigh),
      ),
    );
  }
}
