import 'package:couch_roach/src/theme/theme.dart';
import 'package:couch_roach/src/widgets/poster_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pull the scrim's gradient back out of the built widget tree so the tokens
/// and stops are asserted on directly, rather than via a golden.
LinearGradient _gradientOf(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(PosterScrim),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).gradient! as LinearGradient;
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SizedBox(width: 150, height: 225, child: child))),
    );

void main() {
  group('PosterArt', () {
    testWidgets('with no image falls back to the placeholder gradient',
        (tester) async {
      await _pump(tester, const PosterArt(seed: 'Night of the Living Dead'));
      expect(find.byType(DecoratedBox), findsOneWidget);
    });

    testWidgets('the placeholder gradient is stable for a given seed',
        (tester) async {
      LinearGradient gradientFor(WidgetTester t) =>
          ((t.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
                  as BoxDecoration)
              .gradient!) as LinearGradient;

      await _pump(tester, const PosterArt(seed: 'Metropolis'));
      final first = gradientFor(tester);
      await _pump(tester, const PosterArt(seed: 'Metropolis'));
      expect(gradientFor(tester).colors, first.colors);
    });
  });

  group('PosterScrim', () {
    testWidgets('ramps alpha over the app background, not toward pure black',
        (tester) async {
      await _pump(tester, const PosterScrim());
      final g = _gradientOf(tester);
      // A pure alpha ramp: both ends share the base RGB, so the fade darkens
      // without shifting hue across the middle of the gradient.
      expect(g.colors, [AppColors.posterScrimClear, AppColors.posterScrim]);
      for (final c in g.colors) {
        expect((c.r, c.g, c.b), (AppColors.bg.r, AppColors.bg.g, AppColors.bg.b));
      }
      expect(g.colors.first.a, 0);
    });

    testWidgets('fades bottom-up, starting partway down the poster',
        (tester) async {
      await _pump(tester, const PosterScrim());
      final g = _gradientOf(tester);
      expect(g.begin, Alignment.topCenter);
      expect(g.end, Alignment.bottomCenter);
      expect(g.stops, [0.45, 1]);
    });

    testWidgets('strong is darker and starts higher than the default',
        (tester) async {
      await _pump(tester, const PosterScrim());
      final normal = _gradientOf(tester);
      await _pump(tester, const PosterScrim.strong());
      final strong = _gradientOf(tester);

      expect(strong.colors.last.a, greaterThan(normal.colors.last.a));
      expect(strong.stops!.first, lessThan(normal.stops!.first));
    });
  });
}
