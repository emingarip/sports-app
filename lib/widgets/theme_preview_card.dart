import 'package:flutter/material.dart';

import '../models/app_theme_definition.dart';
import '../theme/app_theme.dart';

class ThemePreviewCard extends StatelessWidget {
  final AppThemeDefinition definition;
  final bool owned;
  final bool active;
  final String? priceLabel;
  final String primaryLabel;
  final VoidCallback? onPrimaryTap;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;
  final bool compact;

  const ThemePreviewCard({
    super.key,
    required this.definition,
    required this.owned,
    required this.active,
    required this.primaryLabel,
    this.onPrimaryTap,
    this.priceLabel,
    this.secondaryLabel,
    this.onSecondaryTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lightColors = AppTheme.resolveColors(
      definition: definition,
      brightness: Brightness.light,
    );
    final darkColors = AppTheme.resolveColors(
      definition: definition,
      brightness: Brightness.dark,
    );
    final textTheme = Theme.of(context).textTheme;

    final previewHeight = compact ? 102.0 : 116.0;

    return Container(
      width: compact ? 280 : null,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: active
              ? context.colors.primaryContainer.withValues(alpha: 0.45)
              : context.colors.outline.withValues(alpha: 0.12),
          width: active ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.cardShadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ThemeHeroPreview(
              definition: definition,
              lightColors: lightColors,
              darkColors: darkColors,
              compact: compact,
              height: previewHeight,
            ),
            SizedBox(height: compact ? 14 : 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: context.colors.textHigh,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        definition.description.isEmpty
                            ? 'Premium team theme pack'
                            : definition.description,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: context.colors.textMedium,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ThemeStatusPill(
                  label: active
                      ? 'Active'
                      : owned
                          ? 'Owned'
                          : 'Premium',
                  backgroundColor: active
                      ? context.colors.primaryContainer.withValues(alpha: 0.16)
                      : owned
                          ? context.colors.badgeOwnedBackground
                          : context.colors.surfaceContainerHigh,
                  foregroundColor: active
                      ? context.colors.primary
                      : owned
                          ? context.colors.badgeOwnedForeground
                          : context.colors.textMedium,
                ),
              ],
            ),
            SizedBox(height: compact ? 12 : 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ThemeTokenChip(
                  icon: Icons.light_mode_rounded,
                  label: 'Light',
                  color: lightColors.primaryContainer,
                  compact: compact,
                ),
                _ThemeTokenChip(
                  icon: Icons.dark_mode_rounded,
                  label: 'Dark',
                  color: darkColors.primaryContainer,
                  compact: compact,
                ),
                if (!compact)
                  _ThemeTokenChip(
                    icon: Icons.text_fields_rounded,
                    label: definition.lightConfig.typographyPreset
                        .toUpperCase(),
                    color: context.colors.surfaceContainerHighest,
                    foregroundColor: context.colors.textHigh,
                  ),
                if (priceLabel != null)
                  _ThemeTokenChip(
                    icon: Icons.monetization_on_rounded,
                    label: priceLabel!,
                    color: context.colors.accent.withValues(alpha: 0.18),
                    foregroundColor: context.colors.primary,
                    compact: compact,
                  ),
              ],
            ),
            SizedBox(height: compact ? 14 : 16),
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: onPrimaryTap,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                    child: Text(primaryLabel),
                  ),
                  if (secondaryLabel != null && onSecondaryTap != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: onSecondaryTap,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                      ),
                      child: Text(secondaryLabel!),
                    ),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onPrimaryTap,
                      child: Text(primaryLabel),
                    ),
                  ),
                  if (secondaryLabel != null && onSecondaryTap != null) ...[
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: onSecondaryTap,
                      child: Text(secondaryLabel!),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeHeroPreview extends StatelessWidget {
  final AppThemeDefinition definition;
  final AppColors lightColors;
  final AppColors darkColors;
  final bool compact;
  final double height;

  const _ThemeHeroPreview({
    required this.definition,
    required this.lightColors,
    required this.darkColors,
    required this.compact,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lightColors.heroGradientStart,
            lightColors.heroGradientEnd,
            darkColors.heroGradientStart,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: compact ? -10 : -12,
            right: compact ? -10 : -8,
            child: Container(
              width: compact ? 74 : 88,
              height: compact ? 74 : 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lightColors.heroGlow.withValues(alpha: 0.22),
              ),
            ),
          ),
          Positioned(
            bottom: compact ? 8 : 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                _ThemeSwatchStrip(
                  compact: compact,
                  colors: [
                    lightColors.primaryContainer,
                    lightColors.navBackground,
                    lightColors.accent,
                    darkColors.primaryContainer,
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: darkColors.surfaceContainerLowest
                        .withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    definition.themeCode.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: darkColors.textHigh,
                          fontWeight: FontWeight.w800,
                          letterSpacing: compact ? 0.4 : 0.6,
                          fontSize: compact ? 10 : null,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatchStrip extends StatelessWidget {
  final List<Color> colors;
  final bool compact;

  const _ThemeSwatchStrip({required this.colors, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final borderColor =
        context.colors.surfaceContainerLowest.withValues(alpha: 0.65);
    return Row(
      children: colors
          .map(
            (color) => Container(
              width: compact ? 20 : 24,
              height: compact ? 20 : 24,
              margin: EdgeInsets.only(right: compact ? 6 : 8),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ThemeTokenChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? foregroundColor;
  final bool compact;

  const _ThemeTokenChip({
    required this.icon,
    required this.label,
    required this.color,
    this.foregroundColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ??
        (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? context.colors.surfaceContainerLowest
            : context.colors.textHigh);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 14, color: fg),
          SizedBox(width: compact ? 5 : 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  fontSize: compact ? 10 : null,
                ),
          ),
        ],
      ),
    );
  }
}

class _ThemeStatusPill extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _ThemeStatusPill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}
