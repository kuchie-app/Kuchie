import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_segments.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the native selection follows the pages while they are swiped', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final positions = <double>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map;
        final channel = MethodChannel(
          '${arguments['viewType']}/${arguments['id']}',
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'position') {
            positions.add(call.arguments as double);
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppleGlassScope(available: true, child: child!),
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              final controller = DefaultTabController.of(context);
              return Scaffold(
                appBar: AppBar(
                  bottom: AppleGlassSegments(
                    labels: const ['Manga', 'Manhwa'],
                    selectedIndex: controller.index,
                    onSelected: controller.animateTo,
                    position: controller.animation,
                    fallback: const PreferredSize(
                      preferredSize: Size.fromHeight(48),
                      child: SizedBox.shrink(),
                    ),
                  ),
                ),
                body: const TabBarView(
                  children: [
                    Center(child: Text('Manga page')),
                    Center(child: Text('Manhwa page')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UiKitView), findsOneWidget);

    // Halfway through a swipe, the selection is halfway too.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Manga page')),
    );
    final width = tester.getSize(find.byType(TabBarView)).width;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(-width / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(positions, isNotEmpty);
    expect(positions.last, closeTo(.5, .1));
    expect(
      positions.where((p) => p > .05 && p < .95),
      isNotEmpty,
      reason: 'the selection moves before the swipe ends',
    );
    await gesture.moveBy(Offset(-width / 2, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(positions.last, closeTo(1, .01));
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
