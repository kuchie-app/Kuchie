// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/browse_center/domain/filter/filter_model.dart';
import 'package:kuchie/src/features/browse_center/presentation/source_manga_list/widgets/source_manga_filter.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:material_ui/material_ui.dart';

Filter _checkBox(String name) => Filter.fromJson({
  '__typename': 'CheckBoxFilter',
  'name': name,
  'checkBoxState': false,
});

Widget _harness({
  required List<Filter> filters,
  required List<FilterChange> appliedChanges,
  ValueChanged<List<FilterChange>?>? onSubmitted,
  bool useGlassSheet = false,
}) => MaterialApp(
  builder: (_, child) =>
      AppleGlassScope(available: useGlassSheet, child: child!),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SourceMangaFilter(
    filters: filters,
    sourceId: '1',
    appliedChanges: appliedChanges,
    onSubmitted: onSubmitted ?? (_) {},
    onReset: () {},
    inSheet: useGlassSheet,
  ),
);

void main() {
  testWidgets('applying a second filter keeps the one already applied', (
    tester,
  ) async {
    List<FilterChange>? submitted;
    await tester.pumpWidget(
      _harness(
        filters: [_checkBox('Completed'), _checkBox('Licensed')],
        appliedChanges: [FilterChange(checkBoxState: true, position: 0)],
        onSubmitted: (value) => submitted = value,
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Licensed'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Filter'));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(
      submitted,
      containsAll(<FilterChange>[
        FilterChange(checkBoxState: true, position: 0),
        FilterChange(checkBoxState: true, position: 1),
      ]),
    );
  });

  testWidgets('confirming a native dropdown updates the source filter draft', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    late MethodChannel toolbar;
    late Map<Object?, Object?> configuration;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method != 'create') return null;
      final args = call.arguments as Map;
      toolbar = MethodChannel('${args['viewType']}/${args['id']}');
      messenger.setMockMethodCallHandler(toolbar, (call) async {
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

    List<FilterChange>? submitted;
    await tester.pumpWidget(
      _harness(
        useGlassSheet: true,
        filters: [
          Filter.fromJson({
            '__typename': 'SelectFilter',
            'name': 'Status',
            'selectState': 0,
            'displayValues': ['All', 'Completed'],
          }),
        ],
        appliedChanges: [],
        onSubmitted: (value) => submitted = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UiKitView), findsOneWidget);
    Map field() => (configuration['actions'] as List).single as Map;
    expect(field()['accessibilityValue'], 'All');
    expect((field()['menu'] as List).first['selected'], true);

    await messenger.handlePlatformMessage(
      toolbar.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('menuSelect', {
          'action': 'source-filter-0',
          'item': '1',
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(field()['accessibilityValue'], 'Completed');
    expect((field()['menu'] as List).last['selected'], true);
    expect(submitted, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Apply filters'));
    expect(submitted, [FilterChange(selectState: 1, position: 0)]);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
