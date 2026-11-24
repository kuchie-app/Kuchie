// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Reading-mode tab: everything set here is app-wide, the same preferences
// Settings edits, and nothing is written to the series.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/constants/enum.dart';
import 'package:kuchie/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/widgets/chrome/tabs/reading_mode_tab.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_auto_webtoon_mode/reader_auto_webtoon_mode.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_mode_tile/reader_mode_tile.dart';
import 'package:kuchie/src/features/settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:kuchie/src/graphql/__generated__/schema.graphql.dart';
import 'package:kuchie/src/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMangaWithId extends MangaWithId {
  _FakeMangaWithId(this.manga);
  final MangaDto? manga;

  @override
  Future<MangaDto?> build({required int mangaId}) async => manga;
}

/// Records meta writes/deletes instead of hitting a server.
class _RecordingRepo implements MangaBookRepository {
  final patches = <(String, dynamic)>[];
  final deletes = <String>[];

  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    patches.add((key, value));
  }

  @override
  Future<void> deleteMangaMeta({
    required int mangaId,
    required String key,
  }) async {
    deletes.add(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

MangaDto _manga({
  Map<String, String> meta = const {},
  List<String> genre = const [],
}) => Fragment$MangaDto(
  id: 1,
  title: 'Test Manga',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: genre,
  initialized: true,
  meta: [
    for (final e in meta.entries)
      Fragment$MangaDto$meta(key: e.key, value: e.value),
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

void main() {
  late _RecordingRepo repo;

  Future<ProviderContainer> pumpTab(
    WidgetTester tester, {
    Map<String, String> meta = const {},
    List<String> genre = const [],
  }) async {
    // Tall viewport so the common rows fit without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _RecordingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mangaBookRepositoryProvider.overrideWithValue(repo),
          mangaWithIdProvider(mangaId: 1).overrideWith(
            () => _FakeMangaWithId(_manga(meta: meta, genre: genre)),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReadingModeTab(mangaId: 1, readerPadding: ValueNotifier(0.0)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ReadingModeTab)),
    );
  }

  testWidgets('reading mode picked in the reader is saved app-wide', (
    tester,
  ) async {
    // An older per-series mode is ignored rather than kept as an override.
    final container = await pumpTab(
      tester,
      meta: {'flutter_readerMode': 'singleVertical'},
    );

    await tester.tap(find.text('Paged (left to right)'));
    await tester.pumpAndSettle();

    expect(
      container.read(readerModeKeyProvider),
      ReaderMode.singleHorizontalLTR,
    );
    expect(repo.patches, isEmpty);
    expect(repo.deletes, isEmpty);
  });

  testWidgets('tap zones are saved for the viewer on screen', (tester) async {
    // The app-wide default mode is Webtoon, so this edits the long strip.
    final container = await pumpTab(tester);

    await tester.tap(find.text('L shaped'));
    await tester.pumpAndSettle();

    expect(
      container.read(longStripNavigationLayoutKeyProvider),
      ReaderNavigationLayout.lShaped,
    );
    expect(
      container.read(pagedNavigationLayoutKeyProvider),
      ReaderNavigationLayout.disabled,
    );
    expect(repo.patches, isEmpty);
  });

  testWidgets('picking a mode for an auto-detected webtoon turns auto off', (
    tester,
  ) async {
    final container = await pumpTab(tester, genre: const ['Manhwa']);
    expect(container.read(autoWebtoonModeProvider), isNot(false));

    await tester.tap(find.text('Paged (left to right)'));
    await tester.pumpAndSettle();

    expect(container.read(autoWebtoonModeProvider), isFalse);
    expect(
      container.read(readerModeKeyProvider),
      ReaderMode.singleHorizontalLTR,
    );
  });
}
