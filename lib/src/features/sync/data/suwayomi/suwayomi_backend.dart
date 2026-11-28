import 'package:graphql/client.dart';

import '../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/scalars.dart' show MultipartFile;
import '../../domain/sync_records.dart';
import '../sync_backend.dart';
import 'graphql/__generated__/sync.graphql.dart';
import 'mihon_backup.dart';
import 'suwayomi_reachability.dart' show isSyncAuthFailure;

/// Sync against one Suwayomi server address, through the operations in
/// `graphql/sync.graphql`.
class SuwayomiBackend implements SyncBackend {
  SuwayomiBackend(this._client, {this.pageSize = 200});

  final GraphQLClient _client;
  final int pageSize;

  /// Chapters per cycle that may be opened on the server so a dropped page
  /// can be sent again; opening one asks the source for its pages.
  static const maxPageRetries = 10;

  /// How long a restore may take before its result is checked anyway.
  static const restoreTimeout = Duration(seconds: 60);

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
    final manga = nodes?.firstOrNull;
    return manga == null ? null : _series(manga);
  }

  @override
  Future<List<RemoteSeries>> createSeries(List<NewRemoteSeries> series) async {
    if (series.isEmpty) return const [];
    // 1. A minimal backup: every manga in one restore, no source access
    //    (spike S3). A regular user's restore changes nothing (S4b).
    try {
      await _restore(series);
    } catch (error) {
      if (isSyncAuthFailure(error)) rethrow;
      // Not allowed or not supported: the search below still tries.
    }
    final found = <RemoteSeries>[];
    final missing = <NewRemoteSeries>[];
    for (final entry in series) {
      final manga = await findSeries(entry.sourceId, entry.url);
      manga == null ? missing.add(entry) : found.add(manga);
    }
    // 2. Searching the source by title creates the row when the source
    //    lists it (94% in S3); the engine then adds it to the library.
    for (final entry in missing) {
      try {
        await _client
            .mutate$SyncFetchSourceManga(
              Options$Mutation$SyncFetchSourceManga(
                variables: Variables$Mutation$SyncFetchSourceManga(
                  input: Input$FetchSourceMangaInput(
                    source: entry.sourceId,
                    type: Enum$FetchSourceMangaType.SEARCH,
                    page: 1,
                    query: entry.title,
                  ),
                ),
              ),
            )
            .getData((data) => data.fetchSourceManga);
      } catch (error) {
        if (isSyncAuthFailure(error)) rethrow;
        continue;
      }
      if (await findSeries(entry.sourceId, entry.url) case final manga?) {
        found.add(manga);
      }
    }
    return found;
  }

  /// Restores a backup of [series] and waits for the server to finish.
  Future<void> _restore(List<NewRemoteSeries> series) async {
    final backup = encodeMihonBackup([
      for (final entry in series)
        BackupSeries(
          sourceId: entry.sourceId,
          url: entry.url,
          title: entry.title,
          sourceName: entry.sourceName,
          addedAt: DateTime.now(),
        ),
    ]);
    final started = await _client
        .mutate$SyncRestoreBackup(
          Options$Mutation$SyncRestoreBackup(
            variables: Variables$Mutation$SyncRestoreBackup(
              backup: MultipartFile.fromBytes(
                'backup',
                backup,
                filename: 'kuchie-sync.tachibk',
              ),
            ),
          ),
        )
        .getData((data) => data.restoreBackup);
    if (started == null) return;
    final deadline = DateTime.now().add(restoreTimeout);
    var state = started.status?.state;
    while (state != Enum$BackupRestoreState.SUCCESS &&
        state != Enum$BackupRestoreState.FAILURE &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      state =
          (await _client
                  .query$SyncRestoreStatus(
                    Options$Query$SyncRestoreStatus(
                      variables: Variables$Query$SyncRestoreStatus(
                        id: started.id,
                      ),
                    ),
                  )
                  .getData((data) => data.restoreStatus))
              ?.state;
    }
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
  Future<void> setMetas(Map<String, Map<String, String>> metas) async {
    final items = [
      for (final MapEntry(key: id, value: values) in metas.entries)
        if (values.isNotEmpty)
          Input$SetMangaMetasItemInput(
            mangaIds: [_id(id)],
            metas: [
              for (final MapEntry(:key, :value) in values.entries)
                Input$MetaInput(key: key, value: value),
            ],
          ),
    ];
    if (items.isEmpty) return;
    await _client
        .mutate$SyncSetMangaMetas(
          Options$Mutation$SyncSetMangaMetas(
            variables: Variables$Mutation$SyncSetMangaMetas(
              input: Input$SetMangaMetasInput(items: items),
            ),
          ),
        )
        .getData((data) => data.setMangaMetas);
  }

  @override
  Future<void> deleteMetas(Map<String, Set<String>> keys) async {
    final items = [
      for (final MapEntry(key: id, value: names) in keys.entries)
        if (names.isNotEmpty)
          Input$DeleteMangaMetasItemInput(
            mangaIds: [_id(id)],
            keys: names.toList(),
          ),
    ];
    if (items.isEmpty) return;
    await _client
        .mutate$SyncDeleteMangaMetas(
          Options$Mutation$SyncDeleteMangaMetas(
            variables: Variables$Mutation$SyncDeleteMangaMetas(
              input: Input$DeleteMangaMetasInput(items: items),
            ),
          ),
        )
        .getData((data) => data.deleteMangaMetas);
  }

  /// Downloads [chapterIds] on the server, from their sources.
  Future<void> enqueueDownloads(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return;
    await _client
        .mutate$SyncEnqueueChapterDownloads(
          Options$Mutation$SyncEnqueueChapterDownloads(
            variables: Variables$Mutation$SyncEnqueueChapterDownloads(
              input: Input$EnqueueChapterDownloadsInput(ids: chapterIds),
            ),
          ),
        )
        .getData((data) => data.enqueueChapterDownloads);
  }

  /// Deletes the server's downloads of [chapterIds].
  Future<void> deleteDownloads(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return;
    await _client
        .mutate$SyncDeleteDownloadedChapters(
          Options$Mutation$SyncDeleteDownloadedChapters(
            variables: Variables$Mutation$SyncDeleteDownloadedChapters(
              input: Input$DeleteDownloadedChaptersInput(ids: chapterIds),
            ),
          ),
        )
        .getData((data) => data.deleteDownloadedChapters);
  }

  /// Server chapter id → (downloaded, page count) for [chapterIds].
  Future<Map<int, ({bool downloaded, int pageCount})>> downloadStates(
    List<int> chapterIds,
  ) async {
    if (chapterIds.isEmpty) return const {};
    final nodes = await _client
        .query$SyncChapterDownloadState(
          Options$Query$SyncChapterDownloadState(
            variables: Variables$Query$SyncChapterDownloadState(
              ids: chapterIds,
            ),
          ),
        )
        .getData((data) => data.chapters.nodes);
    if (nodes == null) throw StateError('The server sent no chapters.');
    return {
      for (final chapter in nodes)
        chapter.id: (
          downloaded: chapter.user.isDownloaded,
          pageCount: chapter.pageCount,
        ),
    };
  }

  /// Extensions the server lists from its stores, installed or not.
  Future<List<ServerExtension>> extensions() async {
    final nodes = await _client.query$SyncExtensions().getData(
      (data) => data.extensions.nodes,
    );
    if (nodes == null) throw StateError('The server sent no extensions.');
    return [
      for (final extension in nodes)
        ServerExtension(
          package: extension.pkgName,
          name: extension.name,
          language: extension.lang,
          installed: extension.isInstalled,
        ),
    ];
  }

  /// Installs [package] from the server's own stores.
  Future<void> installExtension(String package) => _client
      .mutate$SyncUpdateExtension(
        Options$Mutation$SyncUpdateExtension(
          variables: Variables$Mutation$SyncUpdateExtension(
            input: Input$UpdateExtensionInput(
              id: package,
              patch: Input$UpdateExtensionPatchInput(install: true),
            ),
          ),
        ),
      )
      .getData((data) => data.updateExtension);

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
  meta: {for (final entry in manga.meta) entry.key: entry.value},
);

RemoteChapter _chapter(Fragment$SyncChapterDto chapter) => RemoteChapter(
  id: '${chapter.id}',
  seriesId: '${chapter.mangaId}',
  url: chapter.url,
  name: chapter.name,
  downloaded: chapter.user.isDownloaded,
  pageCount: chapter.pageCount,
  state: ChapterState(
    read: chapter.user.isRead,
    page: chapter.user.lastPageRead < 0 ? 0 : chapter.user.lastPageRead,
    bookmarked: chapter.user.isBookmarked,
    readAt: suwayomiTime(chapter.user.lastReadAt),
  ),
);

/// An extension a Suwayomi server lists.
class ServerExtension {
  const ServerExtension({
    required this.package,
    required this.name,
    required this.language,
    required this.installed,
  });

  final String package;
  final String name;
  final String language;
  final bool installed;
}
