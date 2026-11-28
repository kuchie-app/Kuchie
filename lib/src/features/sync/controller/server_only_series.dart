import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/chapter_page_resolver.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import '../data/sync_backend.dart';
import 'server_chapter_pages.dart';

/// A chapter of a "Needs server" series, as its page lists it.
class ServerOnlySeriesChapter {
  const ServerOnlySeriesChapter({required this.id, required this.remote});

  /// Kuchie's chapter id, as sync stores its marks and History.
  final String id;
  final RemoteChapter remote;

  String get title => remote.name.trim().isEmpty ? id : remote.name.trim();
}

/// Reads series only the sync server can read (design 3.5): no extension
/// on this iPhone has their source.
class ServerOnlySeries {
  ServerOnlySeries({required this.pages, required this.client});

  final SuwayomiChapterPages pages;
  final SuwayomiSyncClient client;

  /// The chapters of [seriesId], oldest first. Throws [ChapterNeedsServer]
  /// while the server can't be reached.
  Future<List<ServerOnlySeriesChapter>> chapters(String seriesId) async {
    final remoteId = serverOnlyRemoteId(seriesId);
    if (remoteId == null) throw ArgumentError.value(seriesId, 'seriesId');
    final baseUrl = await pages.baseUrl();
    if (baseUrl == null) throw const ChapterNeedsServer();
    final backend = SuwayomiBackend(client.at(baseUrl));
    var chapters = await backend.chaptersOf(remoteId);
    // A manga the server never opened has no chapters yet (spike S3).
    if (chapters.isEmpty) chapters = await backend.refreshChapters(remoteId);
    pages.forget(remoteId);
    return [
      for (final chapter in chapters)
        ServerOnlySeriesChapter(
          id: localChapterIdFor(seriesId, chapter.url),
          remote: chapter,
        ),
    ];
  }

  /// Asks the server's source for new chapters.
  Future<void> refresh(String seriesId) async {
    final remoteId = serverOnlyRemoteId(seriesId);
    final baseUrl = await pages.baseUrl();
    if (remoteId == null || baseUrl == null) throw const ChapterNeedsServer();
    await SuwayomiBackend(client.at(baseUrl)).refreshChapters(remoteId);
  }
}

final serverOnlySeriesProvider = Provider<ServerOnlySeries>(
  (ref) => ServerOnlySeries(
    pages: ref.watch(serverChapterPagesProvider),
    client: ref.watch(suwayomiSyncClientProvider),
  ),
);
