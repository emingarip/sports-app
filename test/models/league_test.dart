import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/league.dart';

void main() {
  group('League model', () {
    test('constructs with required fields', () {
      final league = League(
        id: 'premier_league',
        name: 'Premier League',
        logoUrl: 'https://example.com/pl.png',
      );

      expect(league.id, 'premier_league');
      expect(league.name, 'Premier League');
      expect(league.logoUrl, 'https://example.com/pl.png');
    });

    test('tier defaults to 2', () {
      final league = League(
        id: 'test',
        name: 'Test League',
        logoUrl: '',
      );

      expect(league.tier, 2);
    });

    test('custom tier is accepted', () {
      final league = League(
        id: 'cl',
        name: 'Champions League',
        logoUrl: '',
        tier: 1,
      );

      expect(league.tier, 1);
    });

    test('tier-based sorting works correctly', () {
      final leagues = [
        League(id: 'c', name: 'League C', logoUrl: '', tier: 3),
        League(id: 'a', name: 'League A', logoUrl: '', tier: 1),
        League(id: 'b', name: 'League B', logoUrl: '', tier: 2),
      ];

      leagues.sort((a, b) => a.tier.compareTo(b.tier));

      expect(leagues[0].id, 'a');
      expect(leagues[1].id, 'b');
      expect(leagues[2].id, 'c');
    });
  });
}
