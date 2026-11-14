import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/kuchie_motion_reveal.dart';

Widget _scene({Key? key, bool reduceMotion = false, bool tickerMode = true}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: TickerMode(
        enabled: tickerMode,
        child: KuchieMotionReveal(key: key, child: const SizedBox(width: 80)),
      ),
    );

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

void main() {
  testWidgets('reveals each result once and preserves completed states', (
    tester,
  ) async {
    const first = ValueKey('first result');
    const second = ValueKey('second result');
    await tester.pumpWidget(_scene(key: first));
    expect(_opacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);

    await tester.pumpWidget(_scene(key: first));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_scene(key: second));
    expect(_opacity(tester), 0);
  });

  testWidgets('Reduce Motion finishes immediately and does not replay', (
    tester,
  ) async {
    await tester.pumpWidget(_scene());
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), inExclusiveRange(0, 1));

    await tester.pumpWidget(_scene(reduceMotion: true));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_scene());
    expect(_opacity(tester), 1);
  });

  testWidgets('a newly mounted reveal skips motion in a muted subtree', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(tickerMode: false));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(_scene());
    expect(_opacity(tester), 1);
  });
}
