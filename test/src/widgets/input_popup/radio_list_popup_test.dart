// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/constants/db_keys.dart';
import 'package:kuchie/src/constants/enum.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('glass reading mode choices preserve legacy saved values', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final nativeViews = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        nativeViews.add((call.arguments as Map)['viewType'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      DBKeys.readerMode.name: ReaderMode.continuousHorizontalRTL.index,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          builder: (_, child) =>
              AppleGlassScope(available: true, child: child!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ReaderModeTile()),
        ),
      ),
    );

    Future<void> open() async {
      await tester.tap(find.text('Reading mode').first);
      await tester.pumpAndSettle();
    }

    await open();
    expect(nativeViews, ['kuchie/apple_liquid_glass/sheet']);
    final choices = tester.widgetList<RadioListTile<ReaderMode>>(
      find.byType(RadioListTile<ReaderMode>),
    );
    expect(choices.map((tile) => tile.value), ReaderMode.displayOrder.skip(1));
    expect(
      choices.singleWhere((tile) => tile.selected).value,
      ReaderMode.continuousHorizontalRTL,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      prefs.getInt(DBKeys.readerMode.name),
      ReaderMode.continuousHorizontalRTL.index,
    );

    await open();
    await tester.tap(find.text('Webtoon'));
    await tester.pumpAndSettle();
    expect(prefs.getInt(DBKeys.readerMode.name), ReaderMode.webtoon.index);
    expect(find.byType(UiKitView), findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
