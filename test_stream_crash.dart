void main() {
  List<Map<String, dynamic>> items = [
    {'id': 1, 'started_at': null},
    {'id': 2, 'started_at': '2026-01-01'}
  ];
  try {
    items.sort((a, b) {
      final valA = a['started_at'];
      final valB = b['started_at'];
      return valA.compareTo(valB);
    });
    print('Sorted successfully!');
  } catch (e) {
    print('Crash reproduced: $e');
  }
}
