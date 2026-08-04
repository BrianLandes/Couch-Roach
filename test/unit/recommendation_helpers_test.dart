import 'package:couch_roach/src/data/tmdb/credits.dart';
import 'package:couch_roach/src/features/discover/recommendation_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CastMember p(int id, String name, {int? order}) =>
      CastMember(personId: id, name: name, order: order);

  group('topRecurringPerson', () {
    test('picks the person appearing across the most titles', () {
      final result = topRecurringPerson([
        [p(1, 'Ana'), p(2, 'Ben')],
        [p(1, 'Ana'), p(3, 'Cal')],
        [p(1, 'Ana'), p(2, 'Ben')],
      ]);
      expect(result, isNotNull);
      expect(result!.personId, 1); // Ana in all three
      expect(result.name, 'Ana');
    });

    test('null when nobody meets the minimum title count', () {
      // Each person appears in only one title.
      expect(
        topRecurringPerson([
          [p(1, 'Ana')],
          [p(2, 'Ben')],
        ]),
        isNull,
      );
    });

    test('counts a person once per title, not per billing slot', () {
      // Ben appears twice in one title (odd data) but that is still one title.
      final result = topRecurringPerson([
        [p(2, 'Ben'), p(2, 'Ben')],
        [p(1, 'Ana')],
      ]);
      expect(result, isNull); // Ben: 1 title, Ana: 1 title → neither reaches 2
    });

    test('ignores people below the billing cutoff', () {
      // With topBilledPerTitle: 1, only the lead of each title counts.
      final result = topRecurringPerson(
        [
          [p(1, 'Lead'), p(9, 'Extra')],
          [p(9, 'Extra'), p(1, 'Lead')],
        ],
        topBilledPerTitle: 1,
      );
      // Lead is billed first in title A, Extra first in title B → each leads once,
      // so nobody reaches 2 titles at the cutoff.
      expect(result, isNull);
    });

    test('ties break toward more appearances then lower id', () {
      final result = topRecurringPerson([
        [p(5, 'Five'), p(2, 'Two')],
        [p(5, 'Five'), p(2, 'Two')],
      ]);
      // Both appear in 2 titles → lower id (2) wins.
      expect(result!.personId, 2);
    });
  });
}
