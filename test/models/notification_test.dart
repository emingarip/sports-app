import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/notification.dart';

void main() {
  test('AppNotification parses external match metadata when present', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-1',
      'title': 'GOL! Home FC',
      'message': 'Home FC 1 - 0 Away FC',
      'type': 'GOAL',
      'is_read': false,
      'created_at': '2026-05-08T10:00:00Z',
      'match_id': null,
      'external_match_id': 'ai-match-1',
      'source': 'ai_sport_agent',
      'event_key': 'goal:ai-match-1:1-0',
    });

    expect(notification.externalMatchId, 'ai-match-1');
    expect(notification.source, 'ai_sport_agent');
    expect(notification.eventKey, 'goal:ai-match-1:1-0');
    expect(notification.matchId, isNull);
  });

  test('AppNotification keeps external metadata optional', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-1',
      'title': 'System',
      'message': 'Hello',
      'created_at': '2026-05-08T10:00:00Z',
    });

    expect(notification.externalMatchId, isNull);
    expect(notification.source, isNull);
    expect(notification.eventKey, isNull);
  });
}
