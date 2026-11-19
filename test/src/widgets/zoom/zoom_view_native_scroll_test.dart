// At 1x the strip inside ZoomView must scroll like a plain list: the list's
// own drag recognizer wins at the 18px touch slop (not the scale recognizer's
// 36px pan slop), short flicks move it, a release keeps momentum, and a tap
// does not leave the position held. Zoomed, the custom pan still owns
// one-finger drags, and a pinch still zooms.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/zoom/zoom_view.dart';
import 'package:material_ui/material_ui.dart';

const _width = 400.0;
const _height = 800.0;

final _mobile = TargetPlatformVariant(const {
  TargetPlatform.iOS,
  TargetPlatform.android,
});

Future<(ScrollController, ZoomViewController)> _pump(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(_width, _height);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  final controller = ScrollController();
  final zoom = ZoomViewController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ZoomView(
          controller: controller,
          zoomViewController: zoom,
          maxScale: 4,
          forceHoldOnPointerDown: true,
          onDoubleTap: (_) {},
          child: ListView.builder(
            controller: controller,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(
              height: _height,
              child: ColoredBox(color: i.isEven ? Colors.red : Colors.blue),
            ),
          ),
        ),
      ),
    ),
  );
  return (controller, zoom);
}

/// Drags 20px per frame and returns the offset after each move.
Future<List<double>> _drag(
  WidgetTester tester,
  ScrollController controller, {
  Offset step = const Offset(0, -20),
  int steps = 10,
}) async {
  final gesture = await tester.startGesture(const Offset(_width / 2, 600));
  final offsets = <double>[];
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
    offsets.add(controller.offset);
  }
  await gesture.up();
  await tester.pumpAndSettle();
  return offsets;
}

void main() {
  testWidgets('the list, not the scale recognizer, wins a one-finger drag', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester);
    final offsets = await _drag(tester, controller);
    // Accepted on the first 20px move (touch slop 18), so the second move
    // already scrolls; with the old 36px pan slop it only started on the third.
    expect(offsets[1], greaterThan(0));
    expect(offsets[2] - offsets[1], closeTo(20, 0.01));
  }, variant: _mobile);

  testWidgets('a short flick under the old 36px pan slop still scrolls', (
    tester,
  ) async {
    final (controller, _) = await _pump(tester);
    await tester.flingFrom(
      const Offset(_width / 2, 500),
      const Offset(0, -30),
      1500,
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  }, variant: _mobile);

  testWidgets('a fling keeps momentum after release', (tester) async {
    final (controller, _) = await _pump(tester);
    await tester.fling(find.byType(ListView), const Offset(0, -300), 3000);
    await tester.pump();
    final atRelease = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(atRelease + 300));
  }, variant: _mobile);

  testWidgets('a tap does not leave the position held', (tester) async {
    final (controller, _) = await _pump(tester);
    await tester.tap(find.byType(ListView));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(controller.position.activity, isA<IdleScrollActivity>());
  }, variant: _mobile);

  testWidgets('zoomed in, a one-finger drag pans and a tap releases holds', (
    tester,
  ) async {
    final (controller, zoom) = await _pump(tester);
    zoom.setScale(2, focalPoint: const Offset(_width / 2, _height / 2));
    await tester.pumpAndSettle();
    expect(zoom.scale, closeTo(2, 0.001));
    final before = controller.offset;
    await _drag(tester, controller, step: const Offset(-10, -20));
    // 200px of finger travel at 2x is 100px of strip; the pan starts at once.
    expect(controller.offset - before, inInclusiveRange(75, 100));

    await tester.tapAt(const Offset(_width / 2, _height / 2));
    await tester.pumpAndSettle();
    expect(controller.position.activity, isA<IdleScrollActivity>());
  }, variant: _mobile);

  testWidgets('a two-finger pinch still zooms at 1x', (tester) async {
    final (_, zoom) = await _pump(tester);
    final a = await tester.startGesture(const Offset(200, 380));
    final b = await tester.startGesture(const Offset(200, 420));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(0, -10));
      await b.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(zoom.scale, greaterThan(1.5));
  }, variant: _mobile);
}
