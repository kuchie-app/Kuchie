import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:kuchie/src/widgets/search_field.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // The glass search wrapped SearchField's focus node in Focus(skipTraversal:
  // true) while the useFocusNode hook reset it to false on every rebuild, so
  // each frame scheduled the next one and the screen never went idle.
  testWidgets('an idle glass search field stops scheduling frames', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map;
        final channel = MethodChannel(
          '${arguments['viewType']}/${arguments['id']}',
        );
        messenger.setMockMethodCallHandler(channel, (_) async => null);
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
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> show(String label) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => AppleGlassScope(available: true, child: child!),
        home: Scaffold(body: SearchField(labelText: label)),
      ),
    );
    await show('Search');
    expect(find.byType(UiKitView), findsOneWidget);
    final node = tester
        .widget<Focus>(
          find
              .ancestor(
                of: find.byType(UiKitView),
                matching: find.byWidgetPredicate(
                  (widget) => widget is Focus && widget.focusNode != null,
                ),
              )
              .first,
        )
        .focusNode!;
    var notifications = 0;
    node.addListener(() => notifications++);

    // Any parent rebuild, such as switching tabs, used to start the loop.
    await show('Search extensions');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(notifications, lessThanOrEqualTo(1));
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
