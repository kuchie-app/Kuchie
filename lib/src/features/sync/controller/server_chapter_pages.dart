import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../local_collection/data/chapter_page_resolver.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../../local_collection/data/local_sources.dart';
import '../data/suwayomi/graphql/__generated__/sync.graphql.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import '../data/sync_journal.dart';
import '../domain/sync_change.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// Reads Local chapters through the Suwayomi server while sync is on: the
/// server fetches pages from its source, or serves its download.
class SuwayomiChapterPages implements ServerChapterPages {
  SuwayomiChapterPages({
    required this.engine,
    required this.client,
    required this.probe,
    required this.journal,
  });

  final SyncEngine engine;
  final SuwayomiSyncClient client;
  final Future<SuwayomiReachability> Function() probe;
  final Future<SyncJournal> Function() journal;

  /// Server manga id → Kuchie chapter id → server chapter id.
  final _chapterIds = <String, Map<String, int>>{};
  ({String baseUrl, DateTime at})? _reachable;

  /// The answering address, probed at most once a minute.
  Future<String?> baseUrl() async {
    final known = _reachable;
    if (known != null &&
        DateTime.now().difference(known.at) < const Duration(minutes: 1)) {
      return known.baseUrl;
    }
    final reachability = await probe();
    if (reachability is! SuwayomiReachable) return null;
    _reachable = (baseUrl: reachability.baseUrl, at: DateTime.now());
    return reachability.baseUrl;
  }

  /// The server's chapter id for [chapterId] of server manga [mangaId],
  /// Local series [seriesId].
  Future<int?> chapterId(
    String baseUrl,
    String mangaId,
    String chapterId, {
    required String seriesId,
  }) async {
    var ids = _chapterIds[mangaId];
    if (ids == null || !ids.containsKey(chapterId)) {
      final chapters = await SuwayomiBackend(
        client.at(baseUrl),
      ).chaptersOf(mangaId);
      ids = _chapterIds[mangaId] = {
        for (final chapter in chapters)
          localChapterIdFor(seriesId, chapter.url): int.parse(chapter.id),
      };
    }
    return ids[chapterId];
  }

  /// Kuchie ids of the chapters of server manga [mangaId] the server has
  /// downloaded. Always asks the server.
  Future<Set<String>> downloadedChapters(
    String baseUrl,
    String mangaId, {
    required String seriesId,
  }) async {
    final chapters = await SuwayomiBackend(
      client.at(baseUrl),
    ).chaptersOf(mangaId);
    _chapterIds[mangaId] = {
      for (final chapter in chapters)
        localChapterIdFor(seriesId, chapter.url): int.parse(chapter.id),
    };
    return {
      for (final chapter in chapters)
        if (chapter.downloaded) localChapterIdFor(seriesId, chapter.url),
    };
  }

  /// Drops the chapter ids kept for [mangaId].
  void forget(String mangaId) => _chapterIds.remove(mangaId);

  /// The server manga id of Local series [seriesId], if linked.
  Future<String?> mangaId(String seriesId) async =>
      (await journal()).remoteIdFor('suwayomi', SyncLinkKind.series, seriesId);

  @override
  Future<List<LocalSourcePage>?> pages(
    String seriesId,
    String chapterId,
  ) async {
    if (!engine.enabled) return null;
    final manga = await mangaId(seriesId);
    if (manga == null) return null;
    final baseUrl = await this.baseUrl();
    if (baseUrl == null) return null;
    final id = await this.chapterId(
      baseUrl,
      manga,
      chapterId,
      seriesId: seriesId,
    );
    if (id == null) return null;
    final result = await client
        .at(baseUrl)
        .mutate$SyncFetchChapterPages(
          Options$Mutation$SyncFetchChapterPages(
            variables: Variables$Mutation$SyncFetchChapterPages(
              input: Input$FetchChapterPagesInput(chapterId: id),
            ),
          ),
        )
        .getData((data) => data.fetchChapterPages?.pages);
    if (result == null || result.isEmpty) return null;
    final headers = await client.headers(baseUrl);
    final base = Uri.parse(baseUrl);
    return [
      for (final page in result) (url: base.resolve(page), headers: headers),
    ];
  }
}

final serverChapterPagesProvider = Provider<SuwayomiChapterPages>(
  (ref) => SuwayomiChapterPages(
    engine: ref.watch(syncEngineProvider),
    client: ref.watch(suwayomiSyncClientProvider),
    probe: () => ref.read(suwayomiReachabilityProvider).probe(),
    journal: () async => SyncJournal(
      (await ref.read(localCollectionServicesProvider.future)).catalog,
    ),
  ),
);
