// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_search.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_segments.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_toolbar.dart';
import 'package:material_ui/material_ui.dart';

const _viewType = 'kuchie/apple_liquid_glass/toolbar';

void main() {
  testWidgets(
    'a newly opened iOS page builds native search and tabs immediately',
    (tester) async {
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

      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppleGlassScope(available: true, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    pageBuilder: (_, _, _) => Scaffold(
                      body: Column(
                        children: [
                          AppleGlassSearch(
                            fallback: (_) => const Text('Fallback search'),
                            native: (_) => AppleGlassSearchControl.entry(
                              placeholder: 'Search',
                              label: 'Search',
                              displayText: '',
                              onOpen: () {},
                            ),
                          ),
                          AppleGlassSegments(
                            labels: const ['Sources', 'Extensions'],
                            selectedIndex: 0,
                            onSelected: (_) {},
                            fallback: const PreferredSize(
                              preferredSize: Size.fromHeight(48),
                              child: Text('Fallback tabs'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('Open page'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open page'));
      await tester.pump();
      expect(find.byType(UiKitView), findsNWidgets(2));
      expect(find.text('Fallback search'), findsNothing);
      expect(find.text('Fallback tabs'), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('native glass toolbar preserves callback and enabled state', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    late MethodChannel toolbar;
    late Map<Object?, Object?> configuration;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method != 'create') return null;
      final args = call.arguments as Map;
      expect(args['viewType'], _viewType);
      configuration =
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(args['params'] as Uint8List),
              )
              as Map<Object?, Object?>;
      toolbar = MethodChannel('$_viewType/${args['id']}');
      messenger.setMockMethodCallHandler(toolbar, (call) async {
        expect(call.method, 'update');
        configuration = call.arguments as Map<Object?, Object?>;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(toolbar, null));
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    final calls = <String>[];
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppleGlassScope(available: true, child: child!),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ValueListenableBuilder(
                valueListenable: enabled,
                builder: (context, enabled, _) => AppleGlassToolbar(
                  actions: [
                    AppleGlassToolbarAction(
                      id: 'search',
                      symbol: 'magnifyingglass',
                      label: 'Search',
                      fallbackIcon: Icons.search,
                      onPressed: () => calls.add('search'),
                    ),
                    AppleGlassToolbarAction(
                      id: 'clear',
                      symbol: 'trash',
                      label: 'Clear',
                      fallbackIcon: Icons.delete,
                      onPressed: enabled ? () => calls.add('clear') : null,
                    ),
                    AppleGlassToolbarAction(
                      id: 'more',
                      symbol: 'ellipsis',
                      label: 'More',
                      fallbackIcon: Icons.more_horiz,
                      onPressed: null,
                      menu: [
                        AppleGlassToolbarMenuItem(
                          id: 'display',
                          title: 'Display',
                          symbol: 'square.grid.2x2',
                          fallbackIcon: Icons.grid_view,
                          children: [
                            AppleGlassToolbarMenuItem(
                              id: 'grid',
                              title: 'Grid',
                              symbol: 'square.grid.2x2',
                              fallbackIcon: Icons.grid_view,
                              selected: true,
                              onSelected: () => calls.add('grid'),
                            ),
                          ],
                        ),
                        AppleGlassToolbarMenuItem(
                          id: 'delete',
                          title: 'Delete',
                          symbol: 'trash',
                          fallbackIcon: Icons.delete,
                          destructive: true,
                          onSelected: enabled
                              ? () => calls.add('delete')
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(UiKitView), findsOneWidget);
    expect(find.byTooltip('Search'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(UiKitView)), const Size(144, 48));
    List<Map> actions() => (configuration['actions'] as List).cast<Map>();
    expect(actions().map((action) => action['symbol']), [
      'magnifyingglass',
      'trash',
      'ellipsis',
    ]);
    expect(actions().map((action) => action['label']), [
      'Search',
      'Clear',
      'More',
    ]);
    List<Map> menu() => (actions().last['menu'] as List).cast<Map>();
    expect((menu().first['children'] as List).single['selected'], true);
    expect(menu().last['destructive'], true);

    Future<void> nativePress(String id) async {
      await messenger.handlePlatformMessage(
        toolbar.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('press', id)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    Future<void> nativeSelect(String action, String item) async {
      await messenger.handlePlatformMessage(
        toolbar.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('menuSelect', {'action': action, 'item': item}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await nativePress('clear');
    await nativeSelect('more', 'delete');
    await nativeSelect('more', 'grid');
    enabled.value = false;
    await tester.pumpAndSettle();
    expect(actions()[1]['enabled'], false);
    expect(menu().last['enabled'], false);
    await nativePress('clear');
    await nativePress('unknown');
    await nativeSelect('more', 'delete');
    await nativeSelect('search', 'grid');
    expect(calls, ['clear', 'delete', 'grid']);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
