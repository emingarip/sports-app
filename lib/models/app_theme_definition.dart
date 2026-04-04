class AppThemeDefinition {
  final String themeCode;
  final String name;
  final String description;
  final String status;
  final int version;
  final List<String> supportedModes;
  final ThemeConfig lightConfig;
  final ThemeConfig darkConfig;
  final ThemeAssets assets;
  final String? previewLightUrl;
  final String? previewDarkUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppThemeDefinition({
    required this.themeCode,
    required this.name,
    required this.description,
    required this.status,
    required this.version,
    required this.supportedModes,
    required this.lightConfig,
    required this.darkConfig,
    required this.assets,
    this.previewLightUrl,
    this.previewDarkUrl,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPublished => isActive && status == 'published';

  bool supportsMode(String mode) =>
      supportedModes.isEmpty || supportedModes.contains(mode);

  factory AppThemeDefinition.fromJson(Map<String, dynamic> json) {
    final lightConfigSource =
        Map<String, dynamic>.from(json['light_config'] as Map? ?? const {});
    final darkConfigSource =
        Map<String, dynamic>.from(json['dark_config'] as Map? ?? const {});
    final assetsSource =
        Map<String, dynamic>.from(json['assets'] as Map? ?? const {});

    return AppThemeDefinition(
      themeCode: (json['theme_code'] as String?)?.trim().isNotEmpty == true
          ? json['theme_code'] as String
          : 'classic',
      name: (json['name'] as String?)?.trim() ?? 'Classic',
      description: (json['description'] as String?)?.trim() ?? '',
      status: (json['status'] as String?)?.trim() ?? 'draft',
      version: (json['version'] as num?)?.toInt() ?? 1,
      supportedModes: ((json['supported_modes'] as List<dynamic>?) ?? const [])
          .map((mode) => mode.toString())
          .toList(),
      lightConfig: ThemeConfig.fromJson(lightConfigSource),
      darkConfig: ThemeConfig.fromJson(darkConfigSource),
      assets: ThemeAssets.fromJson(assetsSource),
      previewLightUrl: json['preview_light_url'] as String?,
      previewDarkUrl: json['preview_dark_url'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme_code': themeCode,
      'name': name,
      'description': description,
      'status': status,
      'version': version,
      'supported_modes': supportedModes,
      'light_config': lightConfig.toJson(),
      'dark_config': darkConfig.toJson(),
      'assets': assets.toJson(),
      'preview_light_url': previewLightUrl,
      'preview_dark_url': previewDarkUrl,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class ThemeAssets {
  final String? backgroundTextureUrl;
  final String? emblemUrl;
  final String? badgeLogoUrl;
  final String? supportFabTextureUrl;

  const ThemeAssets({
    this.backgroundTextureUrl,
    this.emblemUrl,
    this.badgeLogoUrl,
    this.supportFabTextureUrl,
  });

  factory ThemeAssets.fromJson(Map<String, dynamic>? json) {
    final source = Map<String, dynamic>.from(json ?? const <String, dynamic>{});
    return ThemeAssets(
      backgroundTextureUrl: _stringOrNull(source['background_texture_url']),
      emblemUrl: _stringOrNull(source['emblem_url']),
      badgeLogoUrl: _stringOrNull(source['badge_logo_url']),
      supportFabTextureUrl: _stringOrNull(source['support_fab_texture_url']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'background_texture_url': backgroundTextureUrl,
      'emblem_url': emblemUrl,
      'badge_logo_url': badgeLogoUrl,
      'support_fab_texture_url': supportFabTextureUrl,
    };
  }
}

class ThemeConfig {
  final String? background;
  final String? surfaceContainerLow;
  final String? surfaceContainer;
  final String? surfaceContainerHigh;
  final String? surfaceContainerHighest;
  final String? surfaceContainerLowest;
  final String? primaryContainer;
  final String? onPrimaryContainer;
  final String? primary;
  final String? outline;
  final String? secondaryContainer;
  final String? secondary;
  final String? error;
  final String? errorContainer;
  final String? onErrorContainer;
  final String? textHigh;
  final String? textMedium;
  final String? textLow;
  final String? accent;
  final String? success;
  final String? surface;
  final String? surfaceVariant;
  final String? navBackground;
  final String? navBackgroundOverlay;
  final String? navSelected;
  final String? navInactive;
  final String? navAccent;
  final String? navGlow;
  final String? chipBackground;
  final String? chipSelectedBackground;
  final String? chipSelectedForeground;
  final String? heroGradientStart;
  final String? heroGradientEnd;
  final String? heroGlow;
  final String? supportFabStart;
  final String? supportFabEnd;
  final String? supportFabIcon;
  final String? liveAccent;
  final String? liveAccentMuted;
  final String? badgeOwnedBackground;
  final String? badgeOwnedForeground;
  final String? overlayScrim;
  final String? cardShadow;
  final String typographyPreset;

  const ThemeConfig({
    this.background,
    this.surfaceContainerLow,
    this.surfaceContainer,
    this.surfaceContainerHigh,
    this.surfaceContainerHighest,
    this.surfaceContainerLowest,
    this.primaryContainer,
    this.onPrimaryContainer,
    this.primary,
    this.outline,
    this.secondaryContainer,
    this.secondary,
    this.error,
    this.errorContainer,
    this.onErrorContainer,
    this.textHigh,
    this.textMedium,
    this.textLow,
    this.accent,
    this.success,
    this.surface,
    this.surfaceVariant,
    this.navBackground,
    this.navBackgroundOverlay,
    this.navSelected,
    this.navInactive,
    this.navAccent,
    this.navGlow,
    this.chipBackground,
    this.chipSelectedBackground,
    this.chipSelectedForeground,
    this.heroGradientStart,
    this.heroGradientEnd,
    this.heroGlow,
    this.supportFabStart,
    this.supportFabEnd,
    this.supportFabIcon,
    this.liveAccent,
    this.liveAccentMuted,
    this.badgeOwnedBackground,
    this.badgeOwnedForeground,
    this.overlayScrim,
    this.cardShadow,
    this.typographyPreset = 'system',
  });

  factory ThemeConfig.fromJson(Map<String, dynamic>? json) {
    final source = Map<String, dynamic>.from(json ?? const <String, dynamic>{});
    return ThemeConfig(
      background: _stringOrNull(source['background']),
      surfaceContainerLow: _stringOrNull(source['surface_container_low']),
      surfaceContainer: _stringOrNull(source['surface_container']),
      surfaceContainerHigh: _stringOrNull(source['surface_container_high']),
      surfaceContainerHighest:
          _stringOrNull(source['surface_container_highest']),
      surfaceContainerLowest: _stringOrNull(source['surface_container_lowest']),
      primaryContainer: _stringOrNull(source['primary_container']),
      onPrimaryContainer: _stringOrNull(source['on_primary_container']),
      primary: _stringOrNull(source['primary']),
      outline: _stringOrNull(source['outline']),
      secondaryContainer: _stringOrNull(source['secondary_container']),
      secondary: _stringOrNull(source['secondary']),
      error: _stringOrNull(source['error']),
      errorContainer: _stringOrNull(source['error_container']),
      onErrorContainer: _stringOrNull(source['on_error_container']),
      textHigh: _stringOrNull(source['text_high']),
      textMedium: _stringOrNull(source['text_medium']),
      textLow: _stringOrNull(source['text_low']),
      accent: _stringOrNull(source['accent']),
      success: _stringOrNull(source['success']),
      surface: _stringOrNull(source['surface']),
      surfaceVariant: _stringOrNull(source['surface_variant']),
      navBackground: _stringOrNull(source['nav_background']),
      navBackgroundOverlay: _stringOrNull(source['nav_background_overlay']),
      navSelected: _stringOrNull(source['nav_selected']),
      navInactive: _stringOrNull(source['nav_inactive']),
      navAccent: _stringOrNull(source['nav_accent']),
      navGlow: _stringOrNull(source['nav_glow']),
      chipBackground: _stringOrNull(source['chip_background']),
      chipSelectedBackground: _stringOrNull(source['chip_selected_background']),
      chipSelectedForeground: _stringOrNull(source['chip_selected_foreground']),
      heroGradientStart: _stringOrNull(source['hero_gradient_start']),
      heroGradientEnd: _stringOrNull(source['hero_gradient_end']),
      heroGlow: _stringOrNull(source['hero_glow']),
      supportFabStart: _stringOrNull(source['support_fab_start']),
      supportFabEnd: _stringOrNull(source['support_fab_end']),
      supportFabIcon: _stringOrNull(source['support_fab_icon']),
      liveAccent: _stringOrNull(source['live_accent']),
      liveAccentMuted: _stringOrNull(source['live_accent_muted']),
      badgeOwnedBackground: _stringOrNull(source['badge_owned_background']),
      badgeOwnedForeground: _stringOrNull(source['badge_owned_foreground']),
      overlayScrim: _stringOrNull(source['overlay_scrim']),
      cardShadow: _stringOrNull(source['card_shadow']),
      typographyPreset: _stringOrNull(source['typography_preset']) ?? 'system',
    );
  }

  ThemeConfig merge(ThemeConfig fallback) {
    return ThemeConfig(
      background: background ?? fallback.background,
      surfaceContainerLow: surfaceContainerLow ?? fallback.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? fallback.surfaceContainer,
      surfaceContainerHigh:
          surfaceContainerHigh ?? fallback.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? fallback.surfaceContainerHighest,
      surfaceContainerLowest:
          surfaceContainerLowest ?? fallback.surfaceContainerLowest,
      primaryContainer: primaryContainer ?? fallback.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? fallback.onPrimaryContainer,
      primary: primary ?? fallback.primary,
      outline: outline ?? fallback.outline,
      secondaryContainer: secondaryContainer ?? fallback.secondaryContainer,
      secondary: secondary ?? fallback.secondary,
      error: error ?? fallback.error,
      errorContainer: errorContainer ?? fallback.errorContainer,
      onErrorContainer: onErrorContainer ?? fallback.onErrorContainer,
      textHigh: textHigh ?? fallback.textHigh,
      textMedium: textMedium ?? fallback.textMedium,
      textLow: textLow ?? fallback.textLow,
      accent: accent ?? fallback.accent,
      success: success ?? fallback.success,
      surface: surface ?? fallback.surface,
      surfaceVariant: surfaceVariant ?? fallback.surfaceVariant,
      navBackground: navBackground ?? fallback.navBackground,
      navBackgroundOverlay:
          navBackgroundOverlay ?? fallback.navBackgroundOverlay,
      navSelected: navSelected ?? fallback.navSelected,
      navInactive: navInactive ?? fallback.navInactive,
      navAccent: navAccent ?? fallback.navAccent,
      navGlow: navGlow ?? fallback.navGlow,
      chipBackground: chipBackground ?? fallback.chipBackground,
      chipSelectedBackground:
          chipSelectedBackground ?? fallback.chipSelectedBackground,
      chipSelectedForeground:
          chipSelectedForeground ?? fallback.chipSelectedForeground,
      heroGradientStart: heroGradientStart ?? fallback.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? fallback.heroGradientEnd,
      heroGlow: heroGlow ?? fallback.heroGlow,
      supportFabStart: supportFabStart ?? fallback.supportFabStart,
      supportFabEnd: supportFabEnd ?? fallback.supportFabEnd,
      supportFabIcon: supportFabIcon ?? fallback.supportFabIcon,
      liveAccent: liveAccent ?? fallback.liveAccent,
      liveAccentMuted: liveAccentMuted ?? fallback.liveAccentMuted,
      badgeOwnedBackground:
          badgeOwnedBackground ?? fallback.badgeOwnedBackground,
      badgeOwnedForeground:
          badgeOwnedForeground ?? fallback.badgeOwnedForeground,
      overlayScrim: overlayScrim ?? fallback.overlayScrim,
      cardShadow: cardShadow ?? fallback.cardShadow,
      typographyPreset: typographyPreset.isNotEmpty
          ? typographyPreset
          : fallback.typographyPreset,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'background': background,
      'surface_container_low': surfaceContainerLow,
      'surface_container': surfaceContainer,
      'surface_container_high': surfaceContainerHigh,
      'surface_container_highest': surfaceContainerHighest,
      'surface_container_lowest': surfaceContainerLowest,
      'primary_container': primaryContainer,
      'on_primary_container': onPrimaryContainer,
      'primary': primary,
      'outline': outline,
      'secondary_container': secondaryContainer,
      'secondary': secondary,
      'error': error,
      'error_container': errorContainer,
      'on_error_container': onErrorContainer,
      'text_high': textHigh,
      'text_medium': textMedium,
      'text_low': textLow,
      'accent': accent,
      'success': success,
      'surface': surface,
      'surface_variant': surfaceVariant,
      'nav_background': navBackground,
      'nav_background_overlay': navBackgroundOverlay,
      'nav_selected': navSelected,
      'nav_inactive': navInactive,
      'nav_accent': navAccent,
      'nav_glow': navGlow,
      'chip_background': chipBackground,
      'chip_selected_background': chipSelectedBackground,
      'chip_selected_foreground': chipSelectedForeground,
      'hero_gradient_start': heroGradientStart,
      'hero_gradient_end': heroGradientEnd,
      'hero_glow': heroGlow,
      'support_fab_start': supportFabStart,
      'support_fab_end': supportFabEnd,
      'support_fab_icon': supportFabIcon,
      'live_accent': liveAccent,
      'live_accent_muted': liveAccentMuted,
      'badge_owned_background': badgeOwnedBackground,
      'badge_owned_foreground': badgeOwnedForeground,
      'overlay_scrim': overlayScrim,
      'card_shadow': cardShadow,
      'typography_preset': typographyPreset,
    };
  }
}

String? _stringOrNull(dynamic value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
