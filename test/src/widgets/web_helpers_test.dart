// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/web_page_title.dart';
import 'package:kuchie/src/widgets/web_route_link.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/link.dart';

void main() {
  test('web page titles use the on-screen label', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(webRouteTitle(l10n, Uri.parse('/library/0')), 'Library - Kuchie');
    expect(webRouteTitle(l10n, Uri.parse('/updates')), 'Updates - Kuchie');
    expect(
      webRouteTitle(l10n, Uri.parse('/more/settings/reader')),
      'Reader - Kuchie',
    );
    expect(
      webRouteTitle(l10n, Uri.parse('/manga/1'), mangaTitle: 'One Piece'),
      'One Piece - Kuchie',
    );
    expect(
      webRouteTitle(
        l10n,
        Uri.parse('/manga/1/chapter/5'),
        mangaTitle: 'One Piece',
        chapterName: 'Chapter 5',
      ),
      'One Piece: Chapter 5 - Kuchie',
    );
    expect(webRouteTitle(l10n, Uri.parse('/nope')), 'Kuchie');
    expect(webRouteTitle(l10n, Uri()), 'Kuchie');
  });

  testWidgets('web route link passes its child through off the web', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WebRouteLink(
          location: '/manga/1',
          builder: (context, openInNewTab) {
            expect(openInNewTab, isNull);
            return const Text('tile');
          },
        ),
      ),
    );
    expect(find.text('tile'), findsOneWidget);
    expect(find.byType(Link), findsNothing);
  });
}
