import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_hold_gesture_detector.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late int holds;
  late int taps;

  Future<void> pumpStrip(WidgetTester tester) async {
    holds = 0;
    taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderHoldGestureDetector(
          onTap: () => taps++,
          onLongPressStart: (_) => holds++,
          child: ListView.builder(
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 120, child: Text('$i')),
          ),
        ),
      ),
    );
  }

  Future<void> hold(WidgetTester tester, Duration length) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await tester.pump(length);
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a still hold opens only after the reader delay', (tester) async {
    await pumpStrip(tester);

    await hold(tester, const Duration(milliseconds: 550));
    expect(holds, 0);

    await hold(
      tester,
      kReaderLongPressDelay + const Duration(milliseconds: 50),
    );
    expect(holds, 1);
  });

  testWidgets('a tap still taps', (tester) async {
    await pumpStrip(tester);
    await tester.tap(find.byType(ListView));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(holds, 0);
  });

  testWidgets('touching to stop a fling and resting there opens nothing', (
    tester,
  ) async {
    await pumpStrip(tester);

    await tester.fling(find.byType(ListView), const Offset(0, -600), 3000);
    await tester.pump(const Duration(milliseconds: 50));
    await hold(
      tester,
      kReaderLongPressDelay + const Duration(milliseconds: 200),
    );
    expect(holds, 0);

    // Once the page is still, a hold works again.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await hold(
      tester,
      kReaderLongPressDelay + const Duration(milliseconds: 50),
    );
    expect(holds, 1);
  });
}
