// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('exact cache builds fewer offscreen rows and preserves seeks', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final built = <int>{};

    Future<void> open(double? cacheExtent) async {
      await tester.pumpWidget(const SizedBox.shrink());
      built.clear();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PageStorage(
            bucket: PageStorageBucket(),
            child: Center(
              child: SizedBox(
                width: 320,
                height: 400,
                child: ScrollablePositionedList.separated(
                  cacheExtent: cacheExtent,
                  itemCount: 100,
                  initialScrollIndex: 50,
                  itemScrollController: controller,
                  itemPositionsListener: positions,
                  separatorBuilder: (_, _) => const SizedBox.shrink(),
                  itemBuilder: (_, index) {
                    built.add(index);
                    return const SizedBox(height: 100);
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    await open(null);
    final defaultRows = built.length;
    expectLeadingEdge(positions, 50);

    await open(100);
    expect(built.length, lessThan(defaultRows));
    expectLeadingEdge(positions, 50);

    controller.jumpTo(index: 85);
    await tester.pump();
    expectLeadingEdge(positions, 85);
  });
}

void expectLeadingEdge(ItemPositionsListener positions, int index) {
  final item = positions.itemPositions.value.singleWhere(
    (position) => position.index == index,
  );
  expect(item.itemLeadingEdge, closeTo(0, 0.001));
}
