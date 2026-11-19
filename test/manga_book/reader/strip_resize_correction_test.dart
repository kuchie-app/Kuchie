// A page above the visible ones that grows (placeholder -> decoded image)
// must not stop a fling or move what is on screen, and must not rebuild the
// list through an indexed jump (that flashed every page back to its loading
// placeholder and killed the momentum, the stutter seen on device).

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/measure_size.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/strip_resize_correction.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _viewport = 800.0;

class _Harness {
  final items = ItemScrollController();
  final offsets = ScrollOffsetController();
  final positions = ItemPositionsListener.create();
  late final correction = StripResizeCorrection(
    itemScrollController: items,
    scrollOffsetController: offsets,
    positionsListener: positions,
  );
  final heights = ValueNotifier<Map<int, double>>({});

  Widget build({required int initialIndex}) => MaterialApp(
    home: Scaffold(
      body: correction.wrap(
        ValueListenableBuilder<Map<int, double>>(
          valueListenable: heights,
          builder: (context, heights, _) => ScrollablePositionedList.builder(
            itemCount: 200,
            initialScrollIndex: initialIndex,
            itemScrollController: items,
            scrollOffsetController: offsets,
            itemPositionsListener: positions,
            itemBuilder: (context, index) {
              return MeasureSize(
                key: ValueKey(index),
                onResize: (oldSize, newSize) =>
                    correction.onResize(index, newSize.height - oldSize.height),
                child: SizedBox(
                  height: heights[index] ?? 400,
                  child: Text('page $index'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  /// Screen offset of the top of the page labelled [index].
  double top(WidgetTester tester, int index) =>
      tester.getTopLeft(find.text('page $index')).dy;

  int firstVisible() => positions.itemPositions.value
      .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
      .map((p) => p.index)
      .reduce((a, b) => a < b ? a : b);
}

Future<void> _setUp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, _viewport);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a page between the anchor and the screen grows mid-fling: '
      'the fling keeps going and the screen does not jump', (tester) async {
    await _setUp(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build(initialIndex: 10));
    // Scroll forward past the anchor so pages 10.. sit above the screen.
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(ScrollablePositionedList),
      const Offset(0, -300),
      2500,
    );
    await tester.pump(const Duration(milliseconds: 50));
    final first = h.firstVisible();
    expect(first, greaterThan(11));
    final topBefore = h.top(tester, first);
    final anchorBefore = h.items.anchorIndex;

    // Page 11 is above the screen and below the anchor (10): it grows.
    h.heights.value = {...h.heights.value, 11: 1400};
    await tester.pump();
    await tester.pump();
    // Same page, same place, give or take this frame's fling step.
    final moved = (h.top(tester, first) - topBefore).abs();
    expect(moved, lessThan(120), reason: 'no 1000px shove');
    // No indexed jump: the list keeps its anchor instead of rebuilding.
    expect(h.items.anchorIndex, anchorBefore);

    final mid = h.offsets.position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      h.offsets.position.pixels,
      greaterThan(mid + 20),
      reason: 'the fling is still moving after the correction',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a page before the anchor grows away from the screen and is '
      'left alone', (tester) async {
    await _setUp(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build(initialIndex: 50));
    // Scroll back so pages before the anchor are visible.
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, 1200),
    );
    await tester.pumpAndSettle();
    final first = h.firstVisible();
    expect(first, lessThan(50));
    final topBefore = h.top(tester, first + 1);
    final pixelsBefore = h.offsets.position.pixels;
    expect(h.correction.shifts(first - 1), isFalse);

    h.heights.value = {...h.heights.value, first - 1: 1400};
    await tester.pumpAndSettle();
    expect(h.top(tester, first + 1), closeTo(topBefore, 0.5));
    expect(h.offsets.position.pixels, closeTo(pixelsBefore, 0.5));
  });

  testWidgets('a page above the screen grows while idle: the screen stays', (
    tester,
  ) async {
    await _setUp(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build(initialIndex: 0));
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -1700),
    );
    await tester.pumpAndSettle();
    final first = h.firstVisible();
    final topBefore = h.top(tester, first + 1);

    h.heights.value = {...h.heights.value, first - 1: 1000};
    await tester.pump();
    await tester.pump();
    expect(h.top(tester, first + 1), closeTo(topBefore, 0.5));
  });
}
