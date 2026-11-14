// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/browse_center/presentation/source_manga_list/widgets/source_manga_filter.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/app_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('sheet covers the tab shell and closes without leaving the tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: const Text('Library dock'),
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAppBottomSheet<void>(
                    context: context,
                    builder: (_) => const AppSheetHeader(title: 'Filters'),
                  ),
                  child: const Text('Open filters'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open filters'));
    await tester.pumpAndSettle();
    final sheetContext = tester.element(find.byType(AppSheetHeader));
    expect(
      Navigator.of(sheetContext),
      Navigator.of(sheetContext, rootNavigator: true),
    );
    expect(find.text('Filters'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsNothing);
    expect(find.text('Open filters'), findsOneWidget);
    expect(find.text('Library dock'), findsOneWidget);
  });

  testWidgets('source filter actions still work with little vertical space', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 140,
            child: SourceMangaFilter(
              inSheet: true,
              filters: const [],
              sourceId: 'test',
              appliedChanges: const [],
              onReset: () {},
              onSubmitted: (_) => submitted = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    expect(submitted, isTrue);
  });
}
