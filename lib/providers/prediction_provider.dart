import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/prediction_service.dart';

final predictionServiceProvider = Provider<PredictionService>(
  (ref) {
    return PredictionService();
  },
  name: 'predictionServiceProvider',
);

final activeMarketsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final service = ref.read(predictionServiceProvider);
    return await service.getAllActivePredictions();
  },
  name: 'activeMarketsProvider',
);

final myBetsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) async {
    final service = ref.read(predictionServiceProvider);
    return await service.getMyBets();
  },
  name: 'myBetsProvider',
);
