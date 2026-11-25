// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Regression tests for the v0.9.0 infinity-scroll boundary deadlocks:
// 1. Resume on page 0 → an upward drag is fully clamped, the position
//    listener never ticks, and the previous chapter could never load.
// 2. One failed/null page fetch latched "reached start/end" for the session.
// 3. A cold open read the next/prev pair once while the chapter list was
//    still loading, pinning both neighbours to null for the session.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart' as cache;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:image/image.dart' as img;
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
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/multichapter_continuous_reader_mode.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/tall_page_image.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';
import 'package:kuchie/src/features/tracking/data/tracker_repository.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/graphql/__generated__/schema.graphql.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:kuchie/src/utils/texture_limit.dart';
import 'package:kuchie/src/widgets/cover_cache/cover_cache.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;
  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _FakeTrackerRepository extends TrackerRepository {
  _FakeTrackerRepository() : super(_dummyClient());
  @override
  Future<void> trackProgress(int mangaId) async {}
}

class _QuietRepo extends Fake implements MangaBookRepository {
  final putChapterCalls = <({int chapterId, ChapterChange patch})>[];
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    putChapterCalls.add((chapterId: chapterId, patch: patch));
  }
}

class _PageCache extends Fake implements CacheManager {
  _PageCache(String path) : file = const LocalFileSystem().file(path);

  final cache.File file;
  final urls = <String>{};

  @override
  Future<cache.File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    urls.add(url);
    return file;
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    urls.add(url);
    yield FileInfo(file, FileSource.Cache, DateTime(2100), url);
  }
}

/// Whether the cold-open pair test has "resolved" its chapter list yet.
class _PairReady extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final _pairReadyProvider = NotifierProvider<_PairReady, bool>(_PairReady.new);

List<String> _localPages(int count, String tag) {
  final dir = Directory.systemTemp.createTempSync('kuchie-scrollback-$tag-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

MangaDto _webtoonManga() => Fragment$MangaDto(
  id: 1,
  title: 'Test Webtoon',
  chapters: Fragment$MangaDto$chapters(totalCount: 2),
  genre: const [],
  initialized: true,
  meta: [
    Fragment$MangaDto$meta(
      key: MangaMetaKeys.readerMode.key,
      value: ReaderMode.webtoon.name,
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
    unreadCount: 2,
  ),
);

ChapterDto _chapter({required int id, required int sourceOrder}) =>
    Fragment$ChapterDto(
      chapterNumber: sourceOrder.toDouble(),
      fetchedAt: '0',
      id: id,
      mangaId: 1,
      name: 'Chapter $id',
      pageCount: 3,
      sourceOrder: sourceOrder,
      uploadDate: '0',
      url: '/chapter/$id',
      meta: const [],
      user: Fragment$ChapterDto$user(
        isBookmarked: false,
        isDownloaded: false,
        isRead: false,
        lastPageRead: 0,
        lastReadAt: '0',
      ),
    );

ChapterPagesDto _pages(int id, int count) => ChapterPagesDto(
  chapter: ChapterPagesChapterDto(id: id, pageCount: count),
  pages: _localPages(count, 'c$id'),
);

/// Pumps the reader open on chapter 2 page 0 (chapter 1 is its previous).
/// [prevPages] controls what chapterPagesProvider(1) produces per fetch.
/// [coldOpenPair] gates ch2's next/prev pair behind [_pairReadyProvider].
Future<void> _pumpReaderOnChapter2(
  WidgetTester tester, {
  required FutureOr<ChapterPagesDto?> Function() prevPages,
  bool coldOpenPair = false,
  _QuietRepo? repo,
  ChapterPagesDto? chapterPages,
  _PageCache? pageCache,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();

  final ch1 = _chapter(id: 1, sourceOrder: 1);
  final ch2 = _chapter(id: 2, sourceOrder: 2);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (pageCache != null) ...[
          textureLimitProvider.overrideWith((ref) async => 256),
          serverPageCacheManagerProvider.overrideWithValue(pageCache),
        ],
        mangaBookRepositoryProvider.overrideWithValue(repo ?? _QuietRepo()),
        mangaWithIdProvider(
          mangaId: 1,
        ).overrideWith(() => _FakeMangaWithId(_webtoonManga())),
        chapterProvider(chapterId: 1).overrideWithBuild((ref, _) => ch1),
        chapterProvider(chapterId: 2).overrideWithBuild((ref, _) => ch2),
        chapterPagesProvider(chapterId: 1).overrideWith((ref) => prevPages()),
        chapterPagesProvider(
          chapterId: 2,
        ).overrideWith((ref) => chapterPages ?? _pages(2, 3)),
        if (coldOpenPair)
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 2,
            readerScanlatorGroup: '',
          ).overrideWith(
            (ref) => ref.watch(_pairReadyProvider)
                ? (first: null, second: ch1)
                : null,
          )
        else
          getNextAndPreviousChaptersProvider(
            mangaId: 1,
            chapterId: 2,
            readerScanlatorGroup: '',
          ).overrideWithValue((first: null, second: ch1)),
        getNextAndPreviousChaptersProvider(
          mangaId: 1,
          chapterId: 1,
          readerScanlatorGroup: '',
        ).overrideWithValue((first: ch2, second: null)),
        trackerRepositoryProvider.overrideWithValue(_FakeTrackerRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReaderScreen(mangaId: 1, chapterId: 2),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// An upward scroll gesture (drag the content downward) on the reader body.
Future<void> _dragUp(WidgetTester tester) async {
  await tester.timedDrag(
    find.byType(Scrollable).first,
    const Offset(0, 300),
    const Duration(milliseconds: 120),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    // Wall-clock time doesn't advance in widget tests; drop the gesture
    // cooldown so successive drags count as separate attempts.
    MultiChapterContinuousReaderMode.edgeAttemptCooldown = Duration.zero;
  });
  tearDown(() {
    MultiChapterContinuousReaderMode.edgeAttemptCooldown = const Duration(
      seconds: 4,
    );
  });

  test('cached page dimensions follow replacement and deletion', () async {
    final path = Uri.parse(_localPages(1, 'dimension-cache').single);
    final file = File.fromUri(path);
    final dimensions = TallPageDimensionCache();
    const key = 'account/page';

    expect(await dimensions.read(key, file.path), const Size(1, 1));
    file.writeAsBytesSync(img.encodePng(img.Image(width: 128, height: 100)));
    expect(await dimensions.read(key, file.path), const Size(128, 100));
    await file.delete();
    await expectLater(dimensions.read(key, file.path), throwsA(anything));
  });

  testWidgets('Webtoon aligns a visible seek without rebasing the list', (
    tester,
  ) async {
    final pages = ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: 2, pageCount: 24),
      pages: _localPages(24, 'visible-seek'),
    );
    for (final uri in pages.pages) {
      File.fromUri(
        Uri.parse(uri),
      ).writeAsBytesSync(img.encodePng(img.Image(width: 128, height: 100)));
    }
    await _pumpReaderOnChapter2(
      tester,
      prevPages: () => null,
      chapterPages: pages,
    );
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Let the resize correction finish before choosing a mounted target.
    await tester.pump(const Duration(milliseconds: 400));

    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    final position = list.scrollOffsetController!.position;
    final target = list.itemPositionsNotifier!.itemPositions.value
        .where((item) => item.index > 0 && item.itemLeadingEdge > 0.1)
        .first;
    final expectedPixels =
        position.pixels + target.itemLeadingEdge * position.viewportDimension;
    final wrapper = tester.widget<ReaderWrapper>(find.byType(ReaderWrapper));
    wrapper.onChanged(target.index);
    await tester.pump();

    // The jump scrolls the same list instead of rebuilding it.
    expect(position.pixels, closeTo(expectedPixels, 1));
    // Pages that mount during the jump can still be measuring; on a slow
    // machine one may settle a frame later, and the resize correction then
    // keeps the target in place. Judge alignment once that has happened.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
    final aligned = list.itemPositionsNotifier!.itemPositions.value.firstWhere(
      (item) => item.index == target.index,
    );
    expect(aligned.itemLeadingEdge, closeTo(0, 0.002));
    expect(
      tester.widget<ReaderWrapper>(find.byType(ReaderWrapper)).currentIndex,
      target.index,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Webtoon idle fetches nearby pages and warms after a seek', (
    tester,
  ) async {
    const count = 48;
    final pages = ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: 2, pageCount: count),
      pages: [for (var i = 0; i < count; i++) '/page/$i.png'],
    );
    final path = Uri.parse(_localPages(1, 'prefetch').single).toFilePath();
    File(
      path,
    ).writeAsBytesSync(img.encodePng(img.Image(width: 128, height: 512)));
    final pageCache = _PageCache(path);
    await _pumpReaderOnChapter2(
      tester,
      prevPages: () => null,
      chapterPages: pages,
      pageCache: pageCache,
    );

    Future<void> settleFileReads() async {
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    bool requested(int index) =>
        pageCache.urls.any((url) => Uri.parse(url).path == '/page/$index.png');

    await settleFileReads();
    expect(requested(0), isTrue);
    expect(requested(5), isTrue);
    final idle = pageCache.urls.length;
    expect(
      requested(12),
      isFalse,
      reason: '$idle of $count pages requested while idle',
    );

    final wrapper = tester.widget<ReaderWrapper>(find.byType(ReaderWrapper));
    wrapper.onChanged(30);
    await tester.pump();
    final afterSeek = tester.widget<ReaderWrapper>(find.byType(ReaderWrapper));
    expect(afterSeek.currentIndex, 30);
    expect(identical(afterSeek.child, wrapper.child), isTrue);
    await settleFileReads();
    expect(requested(30), isTrue);
    expect(requested(35), isTrue);
    expect(requested(47), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('prepending a previous chapter records no progress for it', (
    tester,
  ) async {
    final repo = _QuietRepo();
    var prevFetches = 0;
    await _pumpReaderOnChapter2(
      tester,
      repo: repo,
      prevPages: () async {
        prevFetches++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return _pages(1, 3);
      },
    );

    await tester.timedDrag(
      find.byType(Scrollable).first,
      const Offset(0, 300),
      const Duration(milliseconds: 120),
    );
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(prevFetches, 1);
    expect(
      repo.putChapterCalls
          .where((c) => c.chapterId == 1)
          .map((c) => (c.patch.lastPageRead, c.patch.isRead)),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'resume at page 0: an upward drag at the clamp loads the previous chapter',
    (tester) async {
      var prevFetches = 0;
      await _pumpReaderOnChapter2(
        tester,
        // Async with a real delay: an unheld autoDispose fetch gets disposed
        // mid-flight and never completes (the "loading… that never loads").
        prevPages: () async {
          prevFetches++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _pages(1, 3);
        },
      );

      // No downward movement first — the deadlock precondition.
      await _dragUp(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));

      expect(
        prevFetches,
        greaterThanOrEqualTo(1),
        reason:
            'blocked upward drag at page 0 never asked for the previous '
            'chapter (the resume deadlock)',
      );

      // A second pull must be a no-op: the chapter LOADED, so the engine's
      // already-loaded guard stops a refetch. If the fetch had been disposed
      // mid-flight (never completing), this drag would fetch again.
      await _dragUp(tester);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      expect(
        prevFetches,
        1,
        reason:
            'previous chapter never finished loading; the fetch was '
            'disposed mid-flight and the gesture refetched',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
