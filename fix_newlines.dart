import 'dart:io';

void main() {
  final file = File('lib/screens/match_detail_screen.dart');
  String text = file.readAsStringSync();
  text = text.replaceAll(r'\n', '\n');
  file.writeAsStringSync(text);
  print('Restored newlines!');
}
