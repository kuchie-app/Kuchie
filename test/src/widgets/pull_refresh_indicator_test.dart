import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/pull_refresh_indicator.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late int refreshes;

  Future<void> pumpPage(
    WidgetTester tester, {
    Future<void> Function()? onRefresh,
  }) async {
    refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefresh(
            top: 0,
            onRefresh: () async {
              refreshes++;
              await onRefresh?.call();
            },
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

  // The arrow spins while refreshing, so the page never settles on its own.
  Future<void> settleWhileSpinning(WidgetTester tester) async {
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('stays lowered with the arrow spinning until it finishes', (
    tester,
  ) async {
    final done = Completer<void>();
    await pumpPage(tester, onRefresh: () => done.future);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row 1')),
    );
    for (var moved = 0.0; moved < 300; moved += 10) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settleWhileSpinning(tester);

    expect(refreshes, 1);
    expect(
      tester.getTopLeft(find.text('Row 0')).dy,
      closeTo(kPullRefreshHold, 1),
      reason: 'the page waits below the arrow',
    );
    expect(find.byType(PullRefreshIcon), findsOneWidget);
    expect(
      tester.widget<PullRefreshIcon>(find.byType(PullRefreshIcon)).refreshing,
      isTrue,
    );

    done.complete();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Row 0')).dy, 0);
    expect(find.byType(PullRefreshIcon), findsNothing);
  });

  testWidgets('the arrow moves with the page while it refreshes', (
    tester,
  ) async {
    final done = Completer<void>();
    await pumpPage(tester, onRefresh: () => done.future);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row 1')),
    );
    for (var moved = 0.0; moved < 300; moved += 10) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settleWhileSpinning(tester);
    final held = tester.getTopLeft(find.byType(PullRefreshIcon)).dy;

    // Scrolling the page up takes the arrow with it, then out of sight.
    await tester.drag(find.text('Row 2'), const Offset(0, -30));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(PullRefreshIcon)).dy, lessThan(held));
    await tester.drag(find.text('Row 3'), const Offset(0, -300));
    await settleWhileSpinning(tester);
    expect(find.byType(PullRefreshIcon), findsNothing);

    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PullRefreshIcon), findsNothing);
    expect(refreshes, 1);
  });
}
