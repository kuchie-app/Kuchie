// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/constants/db_keys.dart';
import 'package:kuchie/src/constants/enum.dart';
import 'package:kuchie/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:kuchie/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/reader_screen.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/reader_bottom_controls.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/reader_side_seekbar.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import 'package:kuchie/src/features/offline/data/offline_database.dart';
import 'package:kuchie/src/features/offline/data/offline_download_providers.dart';
import 'package:kuchie/src/features/offline/data/offline_repository.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/graphql/__generated__/schema.graphql.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/widgets/ios/apple_glass_capability.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

class _RecordingRepo extends Fake implements MangaBookRepository {
  final putChapterCalls = <({int chapterId, ChapterChange patch})>[];

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    putChapterCalls.add((chapterId: chapterId, patch: patch));
  }
}

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('kuchie-reader-screen-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _manga([ReaderMode mode = ReaderMode.singleHorizontalLTR]) =>
    Fragment$MangaDto(
      id: 1,
      title: 'Test Manga',
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      genre: const [],
      initialized: true,
      meta: [
        Fragment$MangaDto$meta(
          key: MangaMetaKeys.readerMode.key,
          value: mode.name,
        ),
      ],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/1',
      user: Fragment$MangaDto$user(
        bookmarkCount: 0,
        downloadCount: 0,
        inLibrary: true,
        inLibraryAt: '0',
        unreadCount: 0,
      ),
    );

ChapterDto _chapter() => Fragment$ChapterDto(
  chapterNumber: 1,
  fetchedAt: '0',
  id: 1,
  mangaId: 1,
  name: 'Chapter 1',
  pageCount: 3,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/chapter/1',
  meta: const [],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: false,
    lastPageRead: 0,
    lastReadAt: '0',
  ),
);

ChapterDto _partReadChapter() {
  final base = _chapter();
  return base.copyWith(user: base.user.copyWith(lastPageRead: 1));
}

ChapterPagesDto _chapterPages() => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
  pages: _localPages(3),
);

// What a source hands back for a paid chapter that is still locked.
ChapterPagesDto _emptyChapterPages() => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: 1, pageCount: 0),
  pages: const [],
);

// The reader pushed over a home page, so it has a route to go back to.
Future<void> _openReader(
  WidgetTester tester, {
  required FutureOr<ChapterPagesDto?> Function(Ref ref) chapterPages,
  bool settle = true,
  bool floating = false,
  int floatingChapterCount = 2,
  bool? forceHorizontal,
  ReaderMode mode = ReaderMode.singleHorizontalLTR,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    if (floating) DBKeys.readerOverlay.name: true,
    DBKeys.forceHorizontalSeekbar.name: ?forceHorizontal,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mangaBookRepositoryProvider.overrideWithValue(_RecordingRepo()),
        mangaWithIdProvider(
          mangaId: 1,
        ).overrideWith(() => _FakeMangaWithId(_manga(mode))),
        chapterProvider(chapterId: 1).overrideWithBuild((ref, _) => _chapter()),
        chapterPagesProvider(chapterId: 1).overrideWith(chapterPages),
        if (floating)
          mangaChapterListWithFilterProvider(
            mangaId: 1,
            keepChapterId: 1,
            readerScanlatorGroup: '',
          ).overrideWithValue(
            AsyncData([
              for (var id = floatingChapterCount; id > 1; id--)
                _chapter().copyWith(id: id, name: 'Chapter $id'),
              _chapter(),
            ]),
          ),
        getNextAndPreviousChaptersProvider(
          mangaId: 1,
          chapterId: 1,
        ).overrideWithValue(null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) =>
            AppleGlassScope(available: floating, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReaderScreen(mangaId: 1, chapterId: 1),
                ),
              ),
              child: const Text('Open reader'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open reader'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.byType(ReaderScreen), findsNothing);
  expect(find.text('Open reader'), findsOneWidget);
}

void main() {
  for (final forceHorizontal in <bool?>[null, false]) {
    testWidgets(
      'compact Reader honors horizontal preference $forceHorizontal',
      (tester) async {
        await _openReader(
          tester,
          chapterPages: (_) => _chapterPages(),
          settle: false,
          floating: true,
          forceHorizontal: forceHorizontal,
          mode: ReaderMode.webtoon,
        );
        expect(
          find.byType(CupertinoSlider),
          forceHorizontal == false ? findsNothing : findsOneWidget,
        );
        expect(
          find.byType(ReaderSideSeekBar),
          forceHorizontal == false ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('floating Reader chapter pill opens and dismisses the picker', (
    tester,
  ) async {
    await _openReader(
      tester,
      chapterPages: (_) => _chapterPages(),
      floating: true,
    );

    final pill = find.widgetWithText(TextButton, 'Chapter 1');
    expect(pill, findsOneWidget);
    expect(find.byTooltip('Bookmark'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('1 / 3'), findsNothing);

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2'), findsOneWidget);
    final picker = find.ancestor(
      of: find.text('Chapter 2'),
      matching: find.byType(Scrollable),
    );
    expect(tester.getSize(picker).height, lessThan(180));

    await tester.tap(find.text('Chapter 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2'), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('floating chapter picker fits five rows with larger text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _openReader(
      tester,
      chapterPages: (_) => _chapterPages(),
      floating: true,
      floatingChapterCount: 5,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Chapter 1'));
    await tester.pumpAndSettle();

    final firstRow = find.text('Chapter 5');
    final lastRow = find.text('Chapter 1').last;
    expect(firstRow.hitTestable(), findsOneWidget);
    expect(lastRow.hitTestable(), findsOneWidget);
    final picker = find.ancestor(
      of: firstRow,
      matching: find.byType(Scrollable),
    );
    final bounds = tester.getRect(picker);
    expect(bounds.bottom - tester.getBottomRight(lastRow).dy, lessThan(60));
  });

  testWidgets(
    'chapter picker opens near the current chapter and watches nearby rows',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final watchedChapters = <int>{};

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineEnabledProvider.overrideWithValue(true),
            offlineChapterStateProvider.overrideWith((ref, chapterId) {
              watchedChapters.add(chapterId);
              return Stream.value(OfflineDeviceState.none);
            }),
            mangaChapterListWithFilterProvider(
              mangaId: 1,
              keepChapterId: 35,
              readerScanlatorGroup: '',
            ).overrideWithValue(
              AsyncData([
                for (var id = 1; id <= 72; id++)
                  _chapter().copyWith(id: id, name: 'Chapter $id'),
              ]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showReaderChapterPicker(
                    context: context,
                    mangaId: 1,
                    currentChapterId: 35,
                    readerScanlatorGroup: '',
                    transVertical: true,
                    floating: true,
                  ),
                  child: const Text('Open chapter picker'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open chapter picker'));
      await tester.pumpAndSettle();

      expect(find.text('Chapter 35').hitTestable(), findsOneWidget);
      expect(watchedChapters, contains(35));
      expect(watchedChapters.length, lessThanOrEqualTo(17));
      expect(watchedChapters, isNot(contains(20)));
      expect(watchedChapters, isNot(contains(55)));

      await tester.drag(find.text('Chapter 35'), const Offset(0, 230));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 32').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(10, 750));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 35'), findsNothing);
    },
  );

  testWidgets(
    'chapter picker shows earlier chapters at the end of a long list',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 518,
              width: 286,
              child: ReaderChapterPickerList(
                count: 72,
                currentIndex: 71,
                floating: true,
                itemBuilder: (context, index) =>
                    SizedBox(height: 44, child: Text('Chapter ${index + 1}')),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Chapter 72').hitTestable(), findsOneWidget);
      expect(find.text('Chapter 68').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'flushes debounced progress when the reader unmounts without a pop',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final repo = _RecordingRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mangaBookRepositoryProvider.overrideWithValue(repo),
            mangaWithIdProvider(
              mangaId: 1,
            ).overrideWith(() => _FakeMangaWithId(_manga())),
            chapterProvider(
              chapterId: 1,
            ).overrideWithBuild((ref, _) => _chapter()),
            chapterPagesProvider(
              chapterId: 1,
            ).overrideWith((ref) => _chapterPages()),
            getNextAndPreviousChaptersProvider(
              mangaId: 1,
              chapterId: 1,
            ).overrideWithValue(null),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReaderScreen(mangaId: 1, chapterId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.timedDrag(
        find.byType(PagedReaderViewport),
        const Offset(-320, 0),
        const Duration(milliseconds: 80),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 / 3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
      // Chapter-skip transitions dispose the reader via pushReplacement, without
      // a PopScope pop — the pending page must be flushed here, not dropped.
      expect(repo.putChapterCalls, hasLength(1));
      expect(repo.putChapterCalls.single.chapterId, 1);
      expect(repo.putChapterCalls.single.patch.lastPageRead, 1);
      // A partial read records position but sends NO read-state — reading
      // forward must never be able to un-read a chapter another client finished.
      expect(repo.putChapterCalls.single.patch.isRead, isNull);
    },
  );

  testWidgets('opening at the end does not mark an unread chapter read', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(
            mangaId: 1,
          ).overrideWith(() => _FakeMangaWithId(_manga())),
          chapterProvider(
            chapterId: 1,
          ).overrideWithBuild((ref, _) => _partReadChapter()),
          chapterPagesProvider(
            chapterId: 1,
          ).overrideWith((ref) => _chapterPages()),
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 1,
          ).overrideWithValue(null),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderScreen(mangaId: 1, chapterId: 1, openAtEnd: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Paging back into a chapter opens it on its last page. The on-mount emit
    // must not count as reading — otherwise the chapter is marked read and its
    // resume position wiped just by navigating to it.
    expect(find.text('3 / 3'), findsOneWidget);
    expect(repo.putChapterCalls, isEmpty);
  });

  testWidgets('a chapter with no pages can be backed out of', (tester) async {
    await _openReader(tester, chapterPages: (ref) => _emptyChapterPages());

    // A locked chapter has no pages, so the reader (and the back button in its
    // top bar) is never mounted. The no-pages view must offer its own way out.
    expect(tester.takeException(), isNull);
    expect(find.byType(PagedReaderViewport), findsNothing);
    expect(find.text('No pages found'), findsOneWidget);
    await _goBack(tester);
  });

  testWidgets(
    'page loading keeps back visible and a failed fetch can be retried',
    (tester) async {
      final firstFetch = Completer<ChapterPagesDto?>();
      var fetchCount = 0;
      await _openReader(
        tester,
        chapterPages: (ref) {
          fetchCount++;
          return fetchCount == 1 ? firstFetch.future : _chapterPages();
        },
        settle: false,
      );

      expect(fetchCount, 1);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(PagedReaderViewport), findsNothing);

      firstFetch.completeError(Exception('Chapter is locked'));
      await tester.pumpAndSettle();
      expect(find.text('Exception: Chapter is locked'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(find.text('Exception: Chapter is locked'), findsNothing);
      expect(find.text('Refresh'), findsNothing);
      expect(find.byType(PagedReaderViewport), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('back leaves the reader while the page request is pending', (
    tester,
  ) async {
    final fetch = Completer<ChapterPagesDto?>();
    await _openReader(tester, chapterPages: (_) => fetch.future, settle: false);

    await _goBack(tester);
    expect(fetch.isCompleted, isFalse);
    fetch.complete(_emptyChapterPages());
    await tester.pumpAndSettle();
    expect(find.text('Open reader'), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel leaves the reader without waiting for page data', (
    tester,
  ) async {
    final fetch = Completer<ChapterPagesDto?>();
    await _openReader(tester, chapterPages: (_) => fetch.future, settle: false);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(fetch.isCompleted, isFalse);
    expect(find.text('Open reader'), findsOneWidget);
  });

  testWidgets('a null page response leaves a way back', (tester) async {
    await _openReader(tester, chapterPages: (_) => null);

    expect(find.text('No pages found'), findsOneWidget);
    await _goBack(tester);
  });
}
