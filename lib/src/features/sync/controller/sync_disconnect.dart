import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_collection_providers.dart';
import '../../local_collection/data/local_collection_services.dart';
import '../../local_collection/data/local_download_queue.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import '../data/sync_journal.dart';
import '../data/sync_state_store.dart';
import '../domain/sync_change.dart';
import 'server_chapter_pages.dart';
import 'sync_background.dart';
import 'sync_engine_provider.dart';

/// A chapter the server keeps for a Local series.
typedef ServerKeptChapter = ({
  String seriesId,
  String seriesTitle,
  String chapterId,
  String chapterTitle,
});

/// Disconnect (design 3.6, PR 17): the server keeps its chapters, and the
/// library here stays as it is. Only links, agreed state and queues go.
class SyncDisconnect {
  SyncDisconnect(this._ref);

  final Ref _ref;

  Future<LocalCollectionServices> _services() =>
      _ref.read(localCollectionServicesProvider.future);

  /// Chapters the server has downloaded for series here; null when it
  /// can't be reached.
  Future<List<ServerKeptChapter>?> serverChapters() async {
    final pages = _ref.read(serverChapterPagesProvider);
    final baseUrl = await pages.baseUrl();
    if (baseUrl == null) return null;
    final services = await _services();
    final titles = {
      for (final series in await services.catalog.syncSeries())
        series.id: series.title,
    };
    final saved = {
      for (final series in await services.catalog.list())
        for (final chapter in series.chapters) (series.id, chapter.id),
    };
    final backend = SuwayomiBackend(
      _ref.read(suwayomiSyncClientProvider).at(baseUrl),
    );
    final kept = <ServerKeptChapter>[];
    for (final link in await SyncJournal(services.catalog).links('suwayomi')) {
      if (link.kind != SyncLinkKind.series) continue;
      for (final chapter in await backend.chaptersOf(link.remoteId)) {
        final id = localChapterIdFor(link.localKey, chapter.url);
        if (!chapter.downloaded || saved.contains((link.localKey, id))) {
          continue;
        }
        kept.add((
          seriesId: link.localKey,
          seriesTitle: titles[link.localKey] ?? link.localKey,
          chapterId: id,
          chapterTitle: chapter.name.trim().isEmpty ? id : chapter.name,
        ));
      }
    }
    return kept;
  }

  /// Turns sync off and forgets the server.
  Future<void> disconnect() async {
    final services = await _services();
    final journal = SyncJournal(services.catalog);
    _ref.read(syncEngineProvider).cancel();
    await journal.clearBackend('suwayomi');
    await journal.clearChanges();
    for (final transfer in await journal.transfers()) {
      await journal.removeTransfer(transfer.seriesId, transfer.chapterId);
    }
    services.catalog.journalEnabled = false;
    services.downloads.serverPages = null;
    await _ref.read(syncStateStoreProvider).forgetServer();
    try {
      await scheduleBackgroundSync(false);
    } catch (_) {
      // Nothing was scheduled.
    }
    _ref.invalidate(syncEngineProvider);
  }

  /// Queues [chapters] for saving here from the server, then disconnects
  /// once the queue has finished them; a relaunch resumes the wait.
  Future<void> saveThenDisconnect(List<ServerKeptChapter> chapters) async {
    final services = await _services();
    for (final chapter in chapters) {
      final series = await services.catalog.find(chapter.seriesId);
      await services.downloads.enqueue(
        LocalDownloadRequest(
          seriesId: chapter.seriesId,
          title: chapter.seriesTitle,
          chapterId: chapter.chapterId,
          chapterTitle: chapter.chapterTitle,
          pages: const [],
          source: series?.source,
        ),
      );
    }
    await _ref.read(syncStateStoreProvider).setDisconnectAfterSaving();
    await finishPendingDisconnect();
  }

  /// Disconnects once Save everything has left the queue.
  Future<void> finishPendingDisconnect() async {
    if (!_ref.read(syncStateStoreProvider).disconnectAfterSaving) return;
    final queue = (await _services()).downloads;
    if (!queue.running) return disconnect();
    final done = Completer<void>();
    void check() {
      if (!queue.running && !done.isCompleted) done.complete();
    }

    queue.addListener(check);
    try {
      await done.future;
    } finally {
      queue.removeListener(check);
    }
    await disconnect();
  }
}

final syncDisconnectProvider = Provider<SyncDisconnect>(SyncDisconnect.new);
