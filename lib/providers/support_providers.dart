import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/support/support_repository.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository();
});

class SupportButtonVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setVisible(bool visible) {
    state = visible;
  }
}

final supportButtonVisibilityProvider = NotifierProvider<SupportButtonVisibilityNotifier, bool>(SupportButtonVisibilityNotifier.new);
