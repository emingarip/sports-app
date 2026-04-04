import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/app_theme_definition.dart';
import 'package:sports_app/models/store_purchase_result.dart';
import 'package:sports_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppThemeDefinition + AppTheme', () {
    test('remote theme overrides tokens and falls back to classic defaults', () {
      const definition = AppThemeDefinition(
        themeCode: 'galatasaray',
        name: 'Galatasaray Legacy',
        description: 'Premium club theme',
        status: 'published',
        version: 3,
        supportedModes: ['light', 'dark'],
        lightConfig: ThemeConfig(
          primaryContainer: '#C8102E',
          onPrimaryContainer: '#FFF4D1',
          navBackground: '#7A0019',
          typographyPreset: 'sports',
        ),
        darkConfig: ThemeConfig(
          primaryContainer: '#FFD166',
          onPrimaryContainer: '#4A0010',
          navBackground: '#22060B',
          typographyPreset: 'display',
        ),
        assets: ThemeAssets(
          emblemUrl: 'https://cdn.example.com/gs.png',
        ),
        previewLightUrl: 'https://cdn.example.com/gs-light.png',
        previewDarkUrl: 'https://cdn.example.com/gs-dark.png',
        isActive: true,
      );

      final lightColors = AppTheme.resolveColors(
        definition: definition,
        brightness: Brightness.light,
      );
      final classicLightColors = AppTheme.resolveColors(
        brightness: Brightness.light,
      );
      final darkColors = AppTheme.resolveColors(
        definition: definition,
        brightness: Brightness.dark,
      );

      expect(lightColors.primaryContainer, const Color(0xFFC8102E));
      expect(lightColors.onPrimaryContainer, const Color(0xFFFFF4D1));
      expect(lightColors.navBackground, const Color(0xFF7A0019));
      expect(lightColors.heroGradientStart, classicLightColors.heroGradientStart);
      expect(darkColors.primaryContainer, const Color(0xFFFFD166));
      expect(darkColors.navBackground, const Color(0xFF22060B));
      expect(
        AppTheme.resolveDefinition(definition).assets.emblemUrl,
        'https://cdn.example.com/gs.png',
      );
    });

    test('definition parsing preserves metadata and mode support', () {
      final definition = AppThemeDefinition.fromJson({
        'theme_code': 'galatasaray',
        'name': 'Galatasaray Legacy',
        'description': 'Premium club theme',
        'status': 'published',
        'version': 2,
        'supported_modes': ['light'],
        'light_config': {
          'primary_container': '#C8102E',
          'typography_preset': 'sports',
        },
        'dark_config': <String, dynamic>{},
        'assets': <String, dynamic>{
          'emblem_url': 'https://cdn.example.com/gs.png',
        },
        'is_active': true,
      });

      expect(definition.isPublished, isTrue);
      expect(definition.supportsMode('light'), isTrue);
      expect(definition.supportsMode('dark'), isFalse);
      expect(definition.lightConfig.typographyPreset, 'sports');
      expect(definition.assets.emblemUrl, 'https://cdn.example.com/gs.png');
    });
  });

  group('StorePurchaseResult', () {
    test('detects theme purchases from server payload', () {
      final result = StorePurchaseResult.fromJson({
        'success': true,
        'product_code': 'theme_galatasaray',
        'product_category': 'app_theme',
        'new_balance': 1900,
        'transaction_id': 'tx_123',
        'entitlement_id': 'ent_123',
        'theme_code': 'galatasaray',
      });

      expect(result.success, isTrue);
      expect(result.isThemePurchase, isTrue);
      expect(result.themeCode, 'galatasaray');
      expect(result.newBalance, 1900);
    });
  });
}
