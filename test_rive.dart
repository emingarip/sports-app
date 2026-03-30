import 'package:rive/rive.dart';

void main() {
  final animation = RiveAnimation.network('https://example.com/file.riv');
  print(animation);
}
