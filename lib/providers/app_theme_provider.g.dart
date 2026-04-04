// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(themeService)
final themeServiceProvider = ThemeServiceProvider._();

final class ThemeServiceProvider
    extends $FunctionalProvider<ThemeService?, ThemeService?, ThemeService?>
    with $Provider<ThemeService?> {
  ThemeServiceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'themeServiceProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$themeServiceHash();

  @$internal
  @override
  $ProviderElement<ThemeService?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeService? create(Ref ref) {
    return themeService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeService? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeService?>(value),
    );
  }
}

String _$themeServiceHash() => r'6713506d7c4aab6292d714105b10ce1703c7d527';

@ProviderFor(ThemeCatalog)
final themeCatalogProvider = ThemeCatalogProvider._();

final class ThemeCatalogProvider
    extends $AsyncNotifierProvider<ThemeCatalog, List<AppThemeDefinition>> {
  ThemeCatalogProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'themeCatalogProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$themeCatalogHash();

  @$internal
  @override
  ThemeCatalog create() => ThemeCatalog();
}

String _$themeCatalogHash() => r'e66d9bfcd7c65f6342f36fe48175e643725ce48b';

abstract class _$ThemeCatalog extends $AsyncNotifier<List<AppThemeDefinition>> {
  FutureOr<List<AppThemeDefinition>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref
        as $Ref<AsyncValue<List<AppThemeDefinition>>, List<AppThemeDefinition>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<List<AppThemeDefinition>>,
            List<AppThemeDefinition>>,
        AsyncValue<List<AppThemeDefinition>>,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(ownedThemeCodes)
final ownedThemeCodesProvider = OwnedThemeCodesProvider._();

final class OwnedThemeCodesProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  OwnedThemeCodesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'ownedThemeCodesProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$ownedThemeCodesHash();

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    return ownedThemeCodes(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$ownedThemeCodesHash() => r'd1a7757b4fed753be1c418ccc6935d02985fe4d4';

@ProviderFor(AppThemeController)
final appThemeControllerProvider = AppThemeControllerProvider._();

final class AppThemeControllerProvider
    extends $NotifierProvider<AppThemeController, AppThemeState> {
  AppThemeControllerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'appThemeControllerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$appThemeControllerHash();

  @$internal
  @override
  AppThemeController create() => AppThemeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppThemeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppThemeState>(value),
    );
  }
}

String _$appThemeControllerHash() =>
    r'0efaccfa9e68f6bfa1c12a2ac1d3a1de7e51ff4a';

abstract class _$AppThemeController extends $Notifier<AppThemeState> {
  AppThemeState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AppThemeState, AppThemeState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AppThemeState, AppThemeState>,
        AppThemeState,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(resolvedLightTheme)
final resolvedLightThemeProvider = ResolvedLightThemeProvider._();

final class ResolvedLightThemeProvider
    extends $FunctionalProvider<ThemeData, ThemeData, ThemeData>
    with $Provider<ThemeData> {
  ResolvedLightThemeProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'resolvedLightThemeProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$resolvedLightThemeHash();

  @$internal
  @override
  $ProviderElement<ThemeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeData create(Ref ref) {
    return resolvedLightTheme(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeData>(value),
    );
  }
}

String _$resolvedLightThemeHash() =>
    r'54762dc68d26fce590ab5319956a71d13ba80a88';

@ProviderFor(resolvedDarkTheme)
final resolvedDarkThemeProvider = ResolvedDarkThemeProvider._();

final class ResolvedDarkThemeProvider
    extends $FunctionalProvider<ThemeData, ThemeData, ThemeData>
    with $Provider<ThemeData> {
  ResolvedDarkThemeProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'resolvedDarkThemeProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$resolvedDarkThemeHash();

  @$internal
  @override
  $ProviderElement<ThemeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeData create(Ref ref) {
    return resolvedDarkTheme(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeData>(value),
    );
  }
}

String _$resolvedDarkThemeHash() => r'c16a04452a3f2af183a4e40ed100bd25fd6fe869';
