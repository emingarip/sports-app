import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_theme_definition.dart';

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
  final Color navBackground;
  final Color navBackgroundOverlay;
  final Color navSelected;
  final Color navInactive;
  final Color navAccent;
  final Color navGlow;
  final Color chipBackground;
  final Color chipSelectedBackground;
  final Color chipSelectedForeground;
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final Color heroGlow;
  final Color supportFabStart;
  final Color supportFabEnd;
  final Color supportFabIcon;
  final Color liveAccent;
  final Color liveAccentMuted;
  final Color badgeOwnedBackground;
  final Color badgeOwnedForeground;
  final Color overlayScrim;
  final Color cardShadow;

  const AppColors({
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
    required this.navBackground,
    required this.navBackgroundOverlay,
    required this.navSelected,
    required this.navInactive,
    required this.navAccent,
    required this.navGlow,
    required this.chipBackground,
    required this.chipSelectedBackground,
    required this.chipSelectedForeground,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.heroGlow,
    required this.supportFabStart,
    required this.supportFabEnd,
    required this.supportFabIcon,
    required this.liveAccent,
    required this.liveAccentMuted,
    required this.badgeOwnedBackground,
    required this.badgeOwnedForeground,
    required this.overlayScrim,
    required this.cardShadow,
  });

  @override
  ThemeExtension<AppColors> copyWith() => this;

  @override
  ThemeExtension<AppColors> lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }

    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surfaceContainerLow:
          Color.lerp(surfaceContainerLow, other.surfaceContainerLow, t)!,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh:
          Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      surfaceContainerHighest: Color.lerp(
        surfaceContainerHighest,
        other.surfaceContainerHighest,
        t,
      )!,
      surfaceContainerLowest: Color.lerp(
        surfaceContainerLowest,
        other.surfaceContainerLowest,
        t,
      )!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer:
          Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      secondaryContainer:
          Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer:
          Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      textHigh: Color.lerp(textHigh, other.textHigh, t)!,
      textMedium: Color.lerp(textMedium, other.textMedium, t)!,
      textLow: Color.lerp(textLow, other.textLow, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      navBackgroundOverlay:
          Color.lerp(navBackgroundOverlay, other.navBackgroundOverlay, t)!,
      navSelected: Color.lerp(navSelected, other.navSelected, t)!,
      navInactive: Color.lerp(navInactive, other.navInactive, t)!,
      navAccent: Color.lerp(navAccent, other.navAccent, t)!,
      navGlow: Color.lerp(navGlow, other.navGlow, t)!,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
      chipSelectedBackground: Color.lerp(
        chipSelectedBackground,
        other.chipSelectedBackground,
        t,
      )!,
      chipSelectedForeground: Color.lerp(
        chipSelectedForeground,
        other.chipSelectedForeground,
        t,
      )!,
      heroGradientStart:
          Color.lerp(heroGradientStart, other.heroGradientStart, t)!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      heroGlow: Color.lerp(heroGlow, other.heroGlow, t)!,
      supportFabStart: Color.lerp(supportFabStart, other.supportFabStart, t)!,
      supportFabEnd: Color.lerp(supportFabEnd, other.supportFabEnd, t)!,
      supportFabIcon: Color.lerp(supportFabIcon, other.supportFabIcon, t)!,
      liveAccent: Color.lerp(liveAccent, other.liveAccent, t)!,
      liveAccentMuted: Color.lerp(liveAccentMuted, other.liveAccentMuted, t)!,
      badgeOwnedBackground:
          Color.lerp(badgeOwnedBackground, other.badgeOwnedBackground, t)!,
      badgeOwnedForeground:
          Color.lerp(badgeOwnedForeground, other.badgeOwnedForeground, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

class AppTheme {
  static const String classicThemeCode = 'classic';

  static final ThemeConfig classicLightConfig = ThemeConfig(
    background: '#F3F7FB',
    surfaceContainerLow: '#ECF1F6',
    surfaceContainer: '#E3E9EE',
    surfaceContainerHigh: '#DDE3E8',
    surfaceContainerHighest: '#D7DEE3',
    surfaceContainerLowest: '#FFFFFF',
    primaryContainer: '#FFD709',
    onPrimaryContainer: '#5B4B00',
    primary: '#6C5A00',
    outline: '#7E775F',
    secondaryContainer: '#E5E2E1',
    secondary: '#5C5B5B',
    error: '#B02500',
    errorContainer: '#FFDAD6',
    onErrorContainer: '#93000A',
    textHigh: '#2A2F32',
    textMedium: '#575C60',
    textLow: '#73777B',
    accent: '#FACC15',
    success: '#16A34A',
    surface: '#FFFFFF',
    surfaceVariant: '#E3E9EE',
    navBackground: '#1E1E1E',
    navBackgroundOverlay: '#1E1E1E',
    navSelected: '#FACC15',
    navInactive: '#F8FAFC',
    navAccent: '#FACC15',
    navGlow: '#FACC15',
    chipBackground: '#ECF1F6',
    chipSelectedBackground: '#FFD709',
    chipSelectedForeground: '#5B4B00',
    heroGradientStart: '#E11D48',
    heroGradientEnd: '#9333EA',
    heroGlow: '#E11D48',
    supportFabStart: '#FFD700',
    supportFabEnd: '#FACC15',
    supportFabIcon: '#5B4B00',
    liveAccent: '#DC2626',
    liveAccentMuted: '#FCA5A5',
    badgeOwnedBackground: '#DCFCE7',
    badgeOwnedForeground: '#166534',
    overlayScrim: '#20252B',
    cardShadow: '#111827',
    typographyPreset: 'system',
  );

  static final ThemeConfig classicDarkConfig = ThemeConfig(
    background: '#131313',
    surfaceContainerLow: '#1C1B1B',
    surfaceContainer: '#201F1F',
    surfaceContainerHigh: '#2A2A2A',
    surfaceContainerHighest: '#353534',
    surfaceContainerLowest: '#0E0E0E',
    primaryContainer: '#FFD700',
    onPrimaryContainer: '#705E00',
    primary: '#FFF6DF',
    outline: '#999077',
    secondaryContainer: '#454749',
    secondary: '#C6C6C9',
    error: '#FFB4AB',
    errorContainer: '#93000A',
    onErrorContainer: '#FFDAD6',
    textHigh: '#E5E2E1',
    textMedium: '#D0C6AB',
    textLow: '#999077',
    accent: '#E9C400',
    success: '#16A34A',
    surface: '#131313',
    surfaceVariant: '#353534',
    navBackground: '#111111',
    navBackgroundOverlay: '#1E1E1E',
    navSelected: '#FACC15',
    navInactive: '#E5E7EB',
    navAccent: '#FACC15',
    navGlow: '#FACC15',
    chipBackground: '#252525',
    chipSelectedBackground: '#FFD700',
    chipSelectedForeground: '#302400',
    heroGradientStart: '#E11D48',
    heroGradientEnd: '#9333EA',
    heroGlow: '#E11D48',
    supportFabStart: '#FFD700',
    supportFabEnd: '#E9C400',
    supportFabIcon: '#3A2F00',
    liveAccent: '#FB7185',
    liveAccentMuted: '#FDA4AF',
    badgeOwnedBackground: '#14532D',
    badgeOwnedForeground: '#DCFCE7',
    overlayScrim: '#080B11',
    cardShadow: '#000000',
    typographyPreset: 'system',
  );

  static final AppThemeDefinition classicDefinition = AppThemeDefinition(
    themeCode: classicThemeCode,
    name: 'Classic',
    description: 'Default SportsApp theme.',
    status: 'published',
    version: 1,
    supportedModes: const ['light', 'dark'],
    lightConfig: classicLightConfig,
    darkConfig: classicDarkConfig,
    assets: const ThemeAssets(),
    isActive: true,
  );

  static ThemeData get lightTheme => buildTheme(brightness: Brightness.light);

  static ThemeData get darkTheme => buildTheme(brightness: Brightness.dark);

  static ThemeData buildTheme({
    required Brightness brightness,
    AppThemeDefinition? definition,
  }) {
    final config = resolveConfig(definition, brightness);
    final colors = _buildColors(config);
    final textTheme = _resolveTextTheme(
      config.typographyPreset,
      brightness,
      colors,
    );
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.primaryContainer,
      brightness: brightness,
    ).copyWith(
      primary: colors.primaryContainer,
      onPrimary: colors.onPrimaryContainer,
      secondary: colors.secondary,
      onSecondary: colors.textHigh,
      error: colors.error,
      onError: colors.onErrorContainer,
      surface: colors.surface,
      onSurface: colors.textHigh,
      outline: colors.outline,
      surfaceTint: colors.primaryContainer,
      scrim: colors.overlayScrim.withValues(alpha: 0.82),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      cardColor: colors.surfaceContainer,
      primaryColor: colors.primaryContainer,
      colorScheme: colorScheme,
      dividerColor: colors.outline.withValues(alpha: 0.14),
      extensions: [colors],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: colors.textHigh),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colors.textHigh,
          fontWeight: FontWeight.w800,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.textHigh,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colors.textHigh,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.textMedium,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.chipBackground,
        selectedColor: colors.chipSelectedBackground,
        secondarySelectedColor: colors.chipSelectedBackground,
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.textMedium),
        secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
          color: colors.chipSelectedForeground,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.08)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      iconTheme: IconThemeData(color: colors.textMedium),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textHigh,
          side: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textLow),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colors.outline.withValues(alpha: 0.06),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primaryContainer, width: 1.6),
        ),
      ),
    );
  }

  static ThemeConfig resolveConfig(
    AppThemeDefinition? definition,
    Brightness brightness,
  ) {
    final base =
        brightness == Brightness.dark ? classicDarkConfig : classicLightConfig;
    final override = brightness == Brightness.dark
        ? definition?.darkConfig
        : definition?.lightConfig;
    return (override ?? base).merge(base);
  }

  static AppColors resolveColors({
    AppThemeDefinition? definition,
    required Brightness brightness,
  }) {
    return _buildColors(resolveConfig(definition, brightness));
  }

  static AppThemeDefinition resolveDefinition(AppThemeDefinition? definition) {
    return definition ?? classicDefinition;
  }

  static AppColors _buildColors(ThemeConfig config) {
    return AppColors(
      background: _hex(config.background, '#F3F7FB'),
      surfaceContainerLow: _hex(config.surfaceContainerLow, '#ECF1F6'),
      surfaceContainer: _hex(config.surfaceContainer, '#E3E9EE'),
      surfaceContainerHigh: _hex(config.surfaceContainerHigh, '#DDE3E8'),
      surfaceContainerHighest: _hex(config.surfaceContainerHighest, '#D7DEE3'),
      surfaceContainerLowest: _hex(config.surfaceContainerLowest, '#FFFFFF'),
      primaryContainer: _hex(config.primaryContainer, '#FFD709'),
      onPrimaryContainer: _hex(config.onPrimaryContainer, '#5B4B00'),
      primary: _hex(config.primary, '#6C5A00'),
      outline: _hex(config.outline, '#7E775F'),
      secondaryContainer: _hex(config.secondaryContainer, '#E5E2E1'),
      secondary: _hex(config.secondary, '#5C5B5B'),
      error: _hex(config.error, '#B02500'),
      errorContainer: _hex(config.errorContainer, '#FFDAD6'),
      onErrorContainer: _hex(config.onErrorContainer, '#93000A'),
      textHigh: _hex(config.textHigh, '#2A2F32'),
      textMedium: _hex(config.textMedium, '#575C60'),
      textLow: _hex(config.textLow, '#73777B'),
      accent: _hex(config.accent, '#FACC15'),
      success: _hex(config.success, '#16A34A'),
      surface: _hex(config.surface, '#FFFFFF'),
      surfaceVariant: _hex(config.surfaceVariant, '#E3E9EE'),
      navBackground: _hex(config.navBackground, '#1E1E1E'),
      navBackgroundOverlay: _hex(config.navBackgroundOverlay, '#1E1E1E'),
      navSelected: _hex(config.navSelected, '#FACC15'),
      navInactive: _hex(config.navInactive, '#F8FAFC'),
      navAccent: _hex(config.navAccent, '#FACC15'),
      navGlow: _hex(config.navGlow, '#FACC15'),
      chipBackground: _hex(config.chipBackground, '#ECF1F6'),
      chipSelectedBackground: _hex(config.chipSelectedBackground, '#FFD709'),
      chipSelectedForeground: _hex(config.chipSelectedForeground, '#5B4B00'),
      heroGradientStart: _hex(config.heroGradientStart, '#E11D48'),
      heroGradientEnd: _hex(config.heroGradientEnd, '#9333EA'),
      heroGlow: _hex(config.heroGlow, '#E11D48'),
      supportFabStart: _hex(config.supportFabStart, '#FFD700'),
      supportFabEnd: _hex(config.supportFabEnd, '#FACC15'),
      supportFabIcon: _hex(config.supportFabIcon, '#5B4B00'),
      liveAccent: _hex(config.liveAccent, '#DC2626'),
      liveAccentMuted: _hex(config.liveAccentMuted, '#FCA5A5'),
      badgeOwnedBackground: _hex(config.badgeOwnedBackground, '#DCFCE7'),
      badgeOwnedForeground: _hex(config.badgeOwnedForeground, '#166534'),
      overlayScrim: _hex(config.overlayScrim, '#20252B'),
      cardShadow: _hex(config.cardShadow, '#111827'),
    );
  }

  static TextTheme _resolveTextTheme(
    String preset,
    Brightness brightness,
    AppColors colors,
  ) {
    final base = brightness == Brightness.dark
        ? ThemeData(brightness: Brightness.dark).textTheme
        : ThemeData(brightness: Brightness.light).textTheme;

    final themedBase = switch (preset) {
      'sports' => GoogleFonts.barlowCondensedTextTheme(base),
      'display' => GoogleFonts.oswaldTextTheme(base),
      _ => base,
    };

    return themedBase.copyWith(
      displayLarge: themedBase.displayLarge?.copyWith(color: colors.textHigh),
      displayMedium: themedBase.displayMedium?.copyWith(color: colors.textHigh),
      displaySmall: themedBase.displaySmall?.copyWith(color: colors.textHigh),
      headlineLarge: themedBase.headlineLarge?.copyWith(color: colors.textHigh),
      headlineMedium:
          themedBase.headlineMedium?.copyWith(color: colors.textHigh),
      headlineSmall: themedBase.headlineSmall?.copyWith(color: colors.textHigh),
      titleLarge: themedBase.titleLarge?.copyWith(
        color: colors.textHigh,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: themedBase.titleMedium?.copyWith(
        color: colors.textHigh,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: themedBase.titleSmall?.copyWith(
        color: colors.textHigh,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: themedBase.bodyLarge?.copyWith(color: colors.textHigh),
      bodyMedium: themedBase.bodyMedium?.copyWith(color: colors.textMedium),
      bodySmall: themedBase.bodySmall?.copyWith(color: colors.textLow),
      labelLarge: themedBase.labelLarge?.copyWith(
        color: colors.textHigh,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: themedBase.labelMedium?.copyWith(color: colors.textMedium),
      labelSmall: themedBase.labelSmall?.copyWith(color: colors.textLow),
    );
  }

  static Color _hex(String? value, String fallback) {
    return _parseHexColor(value ?? fallback) ?? _parseHexColor(fallback)!;
  }

  static Color? _parseHexColor(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (normalized.length != 6 && normalized.length != 8) {
      return null;
    }

    final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
    final parsed = int.tryParse(withAlpha, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
