import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/support/support_repository.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository();
});
