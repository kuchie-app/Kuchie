import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/pull_refresh_indicator.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late int refreshes;

  Future<void> pumpPage(WidgetTester tester) async {
    refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefresh(
            top: 0,
            onRefresh: () async => refreshes++,
            child: ListView(
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 80, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pull(WidgetTester tester, double distance) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row 1')),
    );
    for (var moved = 0.0; moved < distance; moved += 10) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the page fills its space and shows no arrow at rest', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(0));
    expect(find.byType(PullRefreshIcon), findsNothing);
  });

  testWidgets('pulling far enough and letting go refreshes once', (
    tester,
  ) async {
    await pumpPage(tester);
    await pull(tester, 300);
    expect(refreshes, 1);
    expect(find.byType(PullRefreshIcon), findsNothing);
  });

  testWidgets('a short pull does not refresh', (tester) async {
    await pumpPage(tester);
    await pull(tester, 40);
    expect(refreshes, 0);
  });

  testWidgets('the arrow shows while pulling', (tester) async {
    await pumpPage(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row 1')),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(PullRefreshIcon), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
