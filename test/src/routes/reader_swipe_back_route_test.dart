import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/routes/reader_swipe_back_route.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> openReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  ReaderSwipeBackRoute(
                    builder: (_) => const ColoredBox(
                      color: Colors.black,
                      child: Center(child: Text('Reader')),
                    ),
                  ),
                ),
                child: const Text('Series page'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Series page'));
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
  }

  testWidgets('dragging from the left edge past halfway closes the reader', (
    tester,
  ) async {
    await openReader(tester);
    final gesture = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 25; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Mid-swipe the series page shows behind the reader.
    expect(find.text('Series page'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Reader')).dx, greaterThan(200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsNothing);
  });

  testWidgets('a short edge drag springs back', (tester) async {
    await openReader(tester);
    final gesture = await tester.startGesture(const Offset(5, 400));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
    expect(tester.getCenter(find.text('Reader')).dx, closeTo(200, 1));
  });

  testWidgets('a drag in the middle of the page does not close it', (
    tester,
  ) async {
    await openReader(tester);
    await tester.dragFrom(const Offset(200, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
  });
}
