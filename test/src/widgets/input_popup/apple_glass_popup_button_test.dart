// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_popup_button.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_surface.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Glass popups preserve the typed result and cancel separately', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    int? value;
    var cancels = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppleGlassScope(available: true, child: child!),
        home: Scaffold(
          body: AppleGlassPopupButton<int>(
            tooltip: 'Open options',
            onSelected: (selected) => value = selected,
            onCanceled: () => cancels++,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 42, child: Text('Pick 42')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Open options'));
    await tester.pumpAndSettle();
    expect(find.byType(AppleGlassSurface), findsOneWidget);
    await tester.tap(find.text('Pick 42'));
    await tester.pumpAndSettle();
    expect(value, 42);
    expect(cancels, 0);

    await tester.tap(find.byTooltip('Open options'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(750, 550));
    await tester.pumpAndSettle();
    expect(find.text('Pick 42'), findsNothing);
    expect(value, 42);
    expect(cancels, 1);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
