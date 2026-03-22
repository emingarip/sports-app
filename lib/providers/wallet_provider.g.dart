// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(kCoinRepository)
final kCoinRepositoryProvider = KCoinRepositoryProvider._();

final class KCoinRepositoryProvider extends $FunctionalProvider<KCoinRepository,
    KCoinRepository, KCoinRepository> with $Provider<KCoinRepository> {
  KCoinRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'kCoinRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$kCoinRepositoryHash();

  @$internal
  @override
  $ProviderElement<KCoinRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KCoinRepository create(Ref ref) {
    return kCoinRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KCoinRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KCoinRepository>(value),
    );
  }
}

String _$kCoinRepositoryHash() => r'8633b1a95b649fa367d94b816286368c9ad8ff91';

@ProviderFor(kCoinPackages)
final kCoinPackagesProvider = KCoinPackagesProvider._();

final class KCoinPackagesProvider extends $FunctionalProvider<
        AsyncValue<List<KCoinPackage>>,
        List<KCoinPackage>,
        FutureOr<List<KCoinPackage>>>
    with
        $FutureModifier<List<KCoinPackage>>,
        $FutureProvider<List<KCoinPackage>> {
  KCoinPackagesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'kCoinPackagesProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$kCoinPackagesHash();

  @$internal
  @override
  $FutureProviderElement<List<KCoinPackage>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<KCoinPackage>> create(Ref ref) {
    return kCoinPackages(ref);
  }
}

String _$kCoinPackagesHash() => r'ffed6d43e0dc48d9c94816367204c47af6dd644a';

@ProviderFor(WalletBalance)
final walletBalanceProvider = WalletBalanceProvider._();

final class WalletBalanceProvider
    extends $NotifierProvider<WalletBalance, int> {
  WalletBalanceProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'walletBalanceProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$walletBalanceHash();

  @$internal
  @override
  WalletBalance create() => WalletBalance();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$walletBalanceHash() => r'd600a0fae0c6e2f7c77e4153f190447e64b8d0e5';

abstract class _$WalletBalance extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element = ref.element
        as $ClassProviderElement<AnyNotifier<int, int>, int, Object?, Object?>;
    element.handleCreate(ref, build);
  }
}
