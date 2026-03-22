import 'dart:async';
import 'package:network_image_mock/network_image_mock.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await mockNetworkImagesFor(() => testMain());
}
