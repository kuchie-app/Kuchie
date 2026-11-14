// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/apple_glass_reader_slider.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:material_ui/material_ui.dart';

const _viewType = 'kuchie/apple_liquid_glass/reader_slider';

void main() {
  testWidgets(
    'native Reader slider sends zero-based seeks and syncs progress',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final messenger = tester.binding.defaultBinaryMessenger;
      late MethodChannel slider;
      late Map<Object?, Object?> configuration;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method != 'create') return null;
        final args = call.arguments as Map;
        expect(args['viewType'], _viewType);
        expect(args['gestureBlockingPolicy'], 'doNotBlockGesture');
        configuration =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map<Object?, Object?>;
        slider = MethodChannel('$_viewType/${args['id']}');
        messenger.setMockMethodCallHandler(slider, (call) async {
          expect(call.method, 'update');
          configuration = call.arguments as Map<Object?, Object?>;
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(slider, null));
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });

      final currentPage = ValueNotifier(2);
      addTearDown(currentPage.dispose);
      final seeks = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppleGlassScope(
            available: true,
            child: Scaffold(
              body: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: currentPage,
                  builder: (context, index, _) => SizedBox(
                    width: 250,
                    child: AppleGlassReaderSlider(
                      currentIndex: index,
                      pageCount: 23,
                      reversed: true,
                      onChanged: seeks.add,
                      fallback: const Text('Fallback'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(UiKitView), findsOneWidget);
      expect(configuration['index'], 2);
      expect(configuration['count'], 23);
      expect(configuration['reversed'], true);
      expect(configuration['pageLabel'], 'Page: %@');

      for (final index in [19, 23, -1]) {
        await messenger.handlePlatformMessage(
          slider.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('seek', index),
          ),
          (_) {},
        );
      }
      expect(seeks, [19]);

      currentPage.value = 19;
      await tester.pump();
      expect(configuration['index'], 19);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
