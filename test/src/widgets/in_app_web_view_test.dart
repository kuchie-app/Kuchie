// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/in_app_web_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('WebView stays in the app until the browser action is tapped', (
    tester,
  ) async {
    const initialPage = 'https://source.example/series';
    const landedPage = 'https://source.example/series/chapter';
    const viewType = 'kuchie/in_app_web_view';
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    final navigationRequests = <String>[];
    final launches = <String>[];
    final nativeUrls = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launches.add((call.arguments as Map)['url'] as String);
      return true;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method != 'create') return null;
      final arguments = call.arguments as Map;
      expect(arguments['viewType'], viewType);
      final parameters =
          const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(arguments['params'] as Uint8List),
              )
              as Map;
      nativeUrls.add(parameters['url'] as String);
      final channel = MethodChannel('$viewType/${arguments['id']}');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'state') {
          return {
            'title': 'Chapter 1',
            'url': landedPage,
            'canGoBack': true,
            'canGoForward': false,
          };
        }
        navigationRequests.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      messenger.setMockMethodCallHandler(launcher, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openInAppWebView(context, initialPage),
              child: const Text('Preview'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(nativeUrls, [initialPage]);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('source.example'), findsOneWidget);
    expect(launches, isEmpty);

    await tester.tap(find.byTooltip('Back'));
    expect(navigationRequests, ['back']);
    await tester.tap(find.byTooltip('Open in browser').first);
    expect(launches, [landedPage]);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
