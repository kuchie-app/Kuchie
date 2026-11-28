import 'package:graphql/client.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../domain/sync_records.dart';
import '../sync_backend.dart';
import 'graphql/__generated__/sync.graphql.dart';

/// Sync against one Suwayomi server address, through the operations in
/// `graphql/sync.graphql`.
class SuwayomiBackend implements SyncBackend {
  SuwayomiBackend(this._client, {this.pageSize = 200});

  final GraphQLClient _client;
  final int pageSize;

  /// Chapters per cycle that may be opened on the server so a dropped page
  /// can be sent again; opening one asks the source for its pages.
  static const maxPageRetries = 10;

  @override
  String get key => 'suwayomi';

  @override
  Future<List<RemoteSeries>> library() async {
    final series = <RemoteSeries>[];
    final cursors = <int>{};
    int? after;
    while (true) {
      final page = await _client
          .query$SyncLibraryPage(
            Options$Query$SyncLibraryPage(
              variables: Variables$Query$SyncLibraryPage(
                first: pageSize,
                after: after,
              ),
            ),
          )
          .getData((data) => data.mangas);
      if (page == null) throw StateError('The server sent no library page.');
      for (final manga in page.nodes) {
        if (manga.user.inLibrary) series.add(_series(manga));
      }
      if (!page.pageInfo.hasNextPage) return series;
      after = page.pageInfo.endCursor;
      if (after == null || !cursors.add(after)) {
        throw StateError('The server repeated a library page.');
      }
    }
  }

  @override
  Future<List<RemoteCategory>> categories() async {
    final nodes = await _client.query$SyncCategories().getData(
      (data) => data.categories.nodes,
    );
    if (nodes == null) throw StateError('The server sent no categories.');
    return [
      for (final category in nodes)
        // Category 0 is Suwayomi's built-in "Default": no category at all.
        if (!category.$default && category.id != 0)
          RemoteCategory(id: '${category.id}', name: category.name),
    ];
  }

  @override
  Future<List<RemoteChapter>> chaptersOf(String seriesId) async {
    final nodes = await _client
        .query$SyncChaptersOfManga(
          Options$Query$SyncChaptersOfManga(
            variables: Variables$Query$SyncChaptersOfManga(
              mangaId: _id(seriesId),
            ),
          ),
        )
        .getData((data) => data.chapters.nodes);
    if (nodes == null) throw StateError('The server sent no chapters.');
    return nodes.map(_chapter).toList();
  }

  @override
  Future<List<RemoteChapter>> chaptersReadSince(
    Set<String> seriesIds,
    DateTime since,
  ) async {
    if (seriesIds.isEmpty) return const [];
    final chapters = <RemoteChapter>[];
    final cursors = <int>{};
    int? after;
    while (true) {
      final page = await _client
          .query$SyncChaptersSince(
            Options$Query$SyncChaptersSince(
              variables: Variables$Query$SyncChaptersSince(
                mangaIds: seriesIds.map(_id).toList(),
                lastReadAfter: '${since.millisecondsSinceEpoch ~/ 1000}',
                first: pageSize,
                after: after,
              ),
            ),
          )
          .getData((data) => data.chapters);
      if (page == null) throw StateError('The server sent no chapters.');
      chapters.addAll(page.nodes.map(_chapter));
      if (!page.pageInfo.hasNextPage) return chapters;
      after = page.pageInfo.endCursor;
      if (after == null || !cursors.add(after)) {
        throw StateError('The server repeated a chapter page.');
      }
    }
  }

  @override
  Future<RemoteSeries?> findSeries(String sourceId, String url) async {
    final nodes = await _client
        .query$SyncMangaBySourceUrl(
          Options$Query$SyncMangaBySourceUrl(
            variables: Variables$Query$SyncMangaBySourceUrl(
              sourceId: sourceId,
              url: url,
            ),
          ),
        )
        .getData((data) => data.mangas.nodes);
    final id = nodes?.firstOrNull?.id;
    if (id == null) return null;
    // Only the id is asked for; a series found this way is not in the
    // library, or the library pull would have had it.
    return RemoteSeries(
      id: '$id',
      sourceId: sourceId,
      url: url,
      title: url,
      inLibrary: false,
    );
  }

  @override
  Future<List<RemoteChapter>> refreshChapters(String seriesId) async {
    try {
      final result = await _client
          .mutate$SyncFetchMangaAndChapters(
            Options$Mutation$SyncFetchMangaAndChapters(
              variables: Variables$Mutation$SyncFetchMangaAndChapters(
                input: Input$FetchMangaAndChaptersInput(
                  id: _id(seriesId),
                  fetchManga: true,
                  fetchChapters: true,
                ),
              ),
            ),
          )
          .getData((data) => data.fetchMangaAndChapters);
      return result?.chapters.map(_chapter).toList() ?? const [];
    } catch (error) {
      // A source with no chapters yet answers with an error (design 4.3).
      if ('$error'.contains('No chapters found')) return const [];
      rethrow;
    }
  }

  @override
  Future<void> setInLibrary(
    List<String> seriesIds, {
    required bool inLibrary,
  }) async {
    if (seriesIds.isEmpty) return;
    await _client
        .mutate$SyncUpdateMangas(
          Options$Mutation$SyncUpdateMangas(
            variables: Variables$Mutation$SyncUpdateMangas(
              input: Input$UpdateMangasInput(
                ids: seriesIds.map(_id).toList(),
                patch: Input$UpdateMangaPatchInput(inLibrary: inLibrary),
              ),
            ),
          ),
        )
        .getData((data) => data.updateMangas);
  }

  @override
  Future<RemoteCategory> createCategory(String name) async {
    final category = await _client
        .mutate$SyncCreateCategory(
          Options$Mutation$SyncCreateCategory(
            variables: Variables$Mutation$SyncCreateCategory(
              input: Input$CreateCategoryInput(name: name),
            ),
          ),
        )
        .getData((data) => data.createCategory?.category);
    if (category == null) throw StateError('The server made no category.');
    return RemoteCategory(id: '${category.id}', name: category.name);
  }

  @override
  Future<void> changeCategories(
    List<String> seriesIds, {
    Set<String> add = const {},
    Set<String> remove = const {},
  }) async {
    if (seriesIds.isEmpty || (add.isEmpty && remove.isEmpty)) return;
    await _client
        .mutate$SyncUpdateMangasCategories(
          Options$Mutation$SyncUpdateMangasCategories(
            variables: Variables$Mutation$SyncUpdateMangasCategories(
              input: Input$UpdateMangasCategoriesInput(
                ids: seriesIds.map(_id).toList(),
                patch: Input$UpdateMangaCategoriesPatchInput(
                  addToCategories: add.isEmpty ? null : add.map(_id).toList(),
                  removeFromCategories: remove.isEmpty
                      ? null
                      : remove.map(_id).toList(),
                ),
              ),
            ),
          ),
        )
        .getData((data) => data.updateMangasCategories);
  }

  @override
  Future<List<RemoteChapter>> updateChapters(
    List<String> chapterIds,
    ChapterPatch patch,
  ) async {
    if (chapterIds.isEmpty || patch.isEmpty) return const [];
    final updated = await _updateChapters(chapterIds, patch);
    final page = patch.page;
    if (page == null || page == 0) return updated;
    // The server drops `lastPageRead` for a chapter it never opened (spike
    // S2). Opening it makes the next update stick.
    final dropped = [
      for (final chapter in updated)
        if (chapter.state.page != page) chapter.id,
    ].take(maxPageRetries).toList();
    if (dropped.isEmpty) return updated;
    for (final id in dropped) {
      try {
        await _client
            .mutate$SyncFetchChapterPages(
              Options$Mutation$SyncFetchChapterPages(
                variables: Variables$Mutation$SyncFetchChapterPages(
                  input: Input$FetchChapterPagesInput(chapterId: _id(id)),
                ),
              ),
            )
            .getData((data) => data.fetchChapterPages);
      } catch (_) {
        // The source is down; the page goes again next cycle.
      }
    }
    final retried = {
      for (final chapter in await _updateChapters(
        dropped,
        ChapterPatch(page: page),
      ))
        chapter.id: chapter,
    };
    return [for (final chapter in updated) retried[chapter.id] ?? chapter];
  }

  Future<List<RemoteChapter>> _updateChapters(
    List<String> chapterIds,
    ChapterPatch patch,
  ) async {
    final chapters = await _client
        .mutate$SyncUpdateChapters(
          Options$Mutation$SyncUpdateChapters(
            variables: Variables$Mutation$SyncUpdateChapters(
              input: Input$UpdateChaptersInput(
                ids: chapterIds.map(_id).toList(),
                patch: Input$UpdateChapterPatchInput(
                  isRead: patch.read,
                  isBookmarked: patch.bookmarked,
                  lastPageRead: patch.page,
                ),
              ),
            ),
          ),
        )
        .getData((data) => data.updateChapters?.chapters);
    if (chapters == null) throw StateError('The server sent no chapters.');
    return chapters.map(_chapter).toList();
  }
}

int _id(String id) =>
    int.tryParse(id) ?? (throw FormatException('Not a Suwayomi id', id));

/// Suwayomi keeps times in seconds; zero means never (spike S2).
DateTime? suwayomiTime(String seconds) => switch (int.tryParse(seconds)) {
  final int value when value > 0 => DateTime.fromMillisecondsSinceEpoch(
    value * 1000,
    isUtc: true,
  ),
  _ => null,
};

RemoteSeries _series(Fragment$SyncMangaDto manga) => RemoteSeries(
  id: '${manga.id}',
  sourceId: manga.sourceId,
  url: manga.url,
  title: manga.title,
  thumbnailUrl: manga.thumbnailUrl,
  inLibrary: manga.user.inLibrary,
  inLibraryAt: suwayomiTime(manga.user.inLibraryAt),
  categoryIds: {
    for (final category in manga.categories.nodes)
      if (category.id != 0) '${category.id}',
  },
);

RemoteChapter _chapter(Fragment$SyncChapterDto chapter) => RemoteChapter(
  id: '${chapter.id}',
  seriesId: '${chapter.mangaId}',
  url: chapter.url,
  name: chapter.name,
  state: ChapterState(
    read: chapter.user.isRead,
    page: chapter.user.lastPageRead < 0 ? 0 : chapter.user.lastPageRead,
    bookmarked: chapter.user.isBookmarked,
    readAt: suwayomiTime(chapter.user.lastReadAt),
  ),
);
