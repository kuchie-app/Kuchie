import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/constants/db_keys.dart';
import 'package:kuchie/src/constants/enum.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/presentation/local_reader.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/controller/reader_settings_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/reader_bottom_controls.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/reader_chrome.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/reader_top_bar.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_navigation_layout/reader_navigation_layout.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reading mode, tap zones and padding set while reading apply everywhere',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = readerSettingsModelProvider(0, localSeriesId: 'first');
      final second = readerSettingsModelProvider(0, localSeriesId: 'second');
      final server = readerSettingsModelProvider(7);
      ProviderContainer launch() => ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

      final running = launch();
      final lock = running.listen(first, (_, _) {});
      running
          .read(first.notifier)
          .setReaderMode(ReaderMode.singleHorizontalLTR);
      running
          .read(first.notifier)
          .setNavigationLayout(ReaderNavigationLayout.lShaped, longStrip: true);
      running
          .read(first.notifier)
          .setTapInvert(TapInvert.both, longStrip: true);
      running.read(first.notifier).setSidePadding(0.2);
      lock.close();
      running.dispose();

      final restarted = launch();
      addTearDown(restarted.dispose);
      // Saved where Settings reads them, so other series and readers follow.
      expect(
        restarted.read(readerModeKeyProvider),
        ReaderMode.singleHorizontalLTR,
      );
      for (final series in [first, second, server]) {
        // Every series follows the app-wide mode.
        expect(restarted.read(series).readerMode, ReaderMode.defaultReader);
      }
      expect(
        restarted.read(longStripNavigationLayoutKeyProvider),
        ReaderNavigationLayout.lShaped,
      );
      expect(restarted.read(longStripTapInvertKeyProvider), TapInvert.both);
      expect(
        restarted.read(pagedNavigationLayoutKeyProvider),
        ReaderNavigationLayout.disabled,
      );
      for (final series in [first, second, server]) {
        expect(restarted.read(series).sidePadding, 0.2);
      }
    },
  );

  test(
    'per-series reader values saved by an older version are ignored',
    () async {
      SharedPreferences.setMockInitialValues({
        'local.reader.manga.old': jsonEncode({
          MangaMetaKeys.readerMode.key: 'singleVertical',
          MangaMetaKeys.readerNavigationLayout.key: 'kindlish',
          MangaMetaKeys.readerPadding.key: '0.4',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final settings = container.read(
        readerSettingsModelProvider(0, localSeriesId: 'old'),
      );
      expect(settings.readerMode, ReaderMode.defaultReader);
      expect(
        settings.navigationLayout,
        ReaderNavigationLayout.defaultNavigation,
      );
      expect(settings.sidePadding, DBKeys.readerPadding.initial);
    },
  );

  test('tap zones are off until chosen, and Disabled stays an option', () {
    expect(
      DBKeys.pagedNavigationLayout.initial,
      ReaderNavigationLayout.disabled,
    );
    expect(
      DBKeys.longStripNavigationLayout.initial,
      ReaderNavigationLayout.disabled,
    );
    expect(
      ReaderNavigationLayout.displayOrder,
      contains(ReaderNavigationLayout.disabled),
    );
  });

  testWidgets('tagged local manhwa uses auto Webtoon until a mode is picked', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync(
      'kuchie-local-format-test-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final page = File('${dir.path}/page.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
        ),
      );
    final chapter = LocalChapter(id: 'ch', title: 'Chapter', pages: [page]);
    final old = LocalSeriesSource.fromJson({
      'sourceId': 'shinigami',
      'mangaId': 'id',
      'locator': 'https://fixture.test/manga',
    })!;
    expect(old.genres, isEmpty);
    expect(old.sourceName, isNull);
    const original = LocalSeriesSource(
      sourceId: 'shinigami',
      mangaId: 'id',
      locator: 'https://fixture.test/manga',
      genres: ['Action', 'Manhwa'],
      sourceName: 'Shinigami',
    );
    final stored = LocalSeriesSource.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    )!;
    expect(stored.genres, original.genres);
    expect(stored.sourceName, original.sourceName);
    final series = LocalSeries(
      id: 'format',
      title: 'Local Manga',
      chapters: [chapter],
      source: stored,
    );
    final settings = readerSettingsModelProvider(0, localSeriesId: series.id);
    SharedPreferences.setMockInitialValues({
      DBKeys.readerMode.name: ReaderMode.singleHorizontalRTL.index,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalReader(
            series: series,
            chapter: chapter,
            catalog: LocalCatalog(dir),
            ephemeral: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ScrollablePositionedList), findsOneWidget);
    expect(find.byType(PagedReaderViewport), findsNothing);
    // Same chrome, bars and tap zones as the server reader.
    expect(find.byType(ReaderChromeView), findsOneWidget);
    expect(find.byType(ReaderTopBarView), findsOneWidget);
    expect(find.byType(ReaderBottomControlsView), findsOneWidget);
    expect(find.byType(ReaderNavigationLayoutWidget), findsOneWidget);
    // Picking a mode while auto detection chose this series' mode wins:
    // it is saved app-wide and auto detection is switched off.
    container
        .read(settings.notifier)
        .setReaderMode(ReaderMode.singleHorizontalLTR, overrideAuto: true);
    await tester.pump();
    expect(container.read(autoWebtoonModeProvider), isFalse);
    expect(
      container.read(readerModeKeyProvider),
      ReaderMode.singleHorizontalLTR,
    );
    expect(
      tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .reverse,
      isFalse,
    );
    container.read(autoWebtoonModeProvider.notifier).update(true);
    await tester.pump();
    expect(find.byType(ScrollablePositionedList), findsOneWidget);
    container.read(autoWebtoonModeProvider.notifier).update(false);
    container
        .read(readerModeKeyProvider.notifier)
        .update(ReaderMode.singleHorizontalRTL);
    await tester.pump();
    expect(
      tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .reverse,
      isTrue,
    );
  });
}
