// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:kuchie/src/features/offline/data/offline_nav_status.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:kuchie/src/widgets/shell/small_screen_navigation_bar.dart';
import 'package:material_ui/material_ui.dart';

const _bridge = MethodChannel('kuchie/apple_liquid_glass');
const _tabBar = 'kuchie/apple_liquid_glass/tab_bar';

Future<void> _pumpBar(
  WidgetTester tester, {
  required bool glass,
  ValueChanged<int>? onSelect,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(bottom: 34)
    ..viewPadding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);

  var selected = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadsPausedBadgeProvider.overrideWith((ref) => true),
        extensionUpdateBadgeCountProvider.overrideWith((ref) async => 3),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: SmallScreenNavigationBar(
              selectedIndex: selected,
              glassLayout: glass,
              onDestinationSelected: (index) {
                onSelect?.call(index);
                setState(() => selected = index);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const ios = TargetPlatformVariant({TargetPlatform.iOS});

  testWidgets('iOS 26 bridges native tabs, badges and selection to Flutter', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    var probes = 0;
    messenger.setMockMethodCallHandler(_bridge, (call) async {
      expect(call.method, 'isSupported');
      probes++;
      return true;
    });

    late MethodChannel tabChannel;
    Map<Object?, Object?>? state;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method != 'create') return null;
      final args = call.arguments as Map;
      expect(args['viewType'], _tabBar);
      state =
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(args['params'] as Uint8List),
              )
              as Map<Object?, Object?>;
      tabChannel = MethodChannel('$_tabBar/${args['id']}');
      messenger.setMockMethodCallHandler(tabChannel, (call) async {
        expect(call.method, 'update');
        state = call.arguments as Map<Object?, Object?>;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(tabChannel, null));
      return null;
    });

    final selections = <int>[];
    final glass = await appleGlassAvailable();
    await _pumpBar(tester, glass: glass, onSelect: selections.add);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpAndSettle();
    expect(probes, 1);
    final tabs = (state!['tabs'] as List).cast<Map>();
    expect(tabs.map((tab) => tab['title']), [
      'Library',
      'Updates',
      'Browse',
      'History',
      'More',
    ]);
    expect(tabs[2]['badge'], '3');
    expect(tabs[4]['badge'], '');
    expect(state!['selectedIndex'], 0);
    // The selected tab follows the theme accent rather than UIKit's blue.
    expect(
      state!['tint'],
      Theme.of(
        tester.element(find.byType(UiKitView)),
      ).colorScheme.primary.toARGB32(),
    );
    expect(tester.getSize(find.byType(UiKitView)).height, 114);

    Future<void> nativeSelect(int index) async {
      await messenger.handlePlatformMessage(
        tabChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('select', index),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await nativeSelect(2);
    expect(state!['selectedIndex'], 2);
    await nativeSelect(2);
    await nativeSelect(99);
    expect(selections, [2, 2]);
  }, variant: ios);

  testWidgets('iOS before 26 retains the standard navigation bar', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _bridge,
      (call) async => false,
    );
    await _pumpBar(tester, glass: await appleGlassAvailable());
    await tester.pumpAndSettle();
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(Badge), findsNWidgets(2));
  }, variant: ios);

  testWidgets('Android never asks UIKit for a navigation bar', (tester) async {
    var requested = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_bridge, (
      call,
    ) async {
      requested = true;
      return true;
    });
    await _pumpBar(tester, glass: await appleGlassAvailable());
    expect(requested, isFalse);
    expect(find.byType(NavigationBar), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
