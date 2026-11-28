import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_catalog.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import '../data/sync_journal.dart';
import 'server_chapter_pages.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// Where a chapter is kept, for its badge (design 3.6).
enum ChapterLocation {
  /// On this iPhone only.
  iphone,

  /// On the server only.
  server,

  /// An offline copy of a chapter the server also has.
  both,
}

/// A chapter's server download, as far as this iPhone knows.
typedef ServerChapterState = ({bool downloaded, SyncTransferState? transfer});

/// Downloads on the server (design 3.6): the Download button while sync is
/// on, and Move to server for chapters already saved here.
///
/// Each chapter goes `queued` → `requested` (enqueueChapterDownloads) →
/// `verified` (the server reports it downloaded, with as many pages as the
/// copy here) → `done`, deleting the copy here only when it is not kept.
/// Any step can end in `failed`, and nothing here is ever deleted before
/// `verified` (PR 16's main property). State lives in `sync_transfers`, so a
/// closed app picks up where it was.
class ServerTransfers {
  ServerTransfers({
    required this.engine,
    required this.catalog,
    required this.pages,
    required this.backendAt,
    DateTime Function()? clock,
    this.pollEvery = const Duration(seconds: 10),
    this.giveUpAfter = const Duration(hours: 6),
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final SyncEngine engine;
  final Future<LocalCatalog> Function() catalog;
  final SuwayomiChapterPages pages;
  final SuwayomiBackend Function(String baseUrl) backendAt;
  final DateTime Function() _clock;
  final Duration pollEvery;

  /// A request the server hasn't finished by then failed: its source may
  /// have dropped the chapter, or the disk is full (design 8, 11c).
  final Duration giveUpAfter;

  Future<void>? _running;
  bool _again = false;
  Timer? _poll;

  /// Called whenever the transfers change, for the Downloads page.
  void Function()? onChanged;

  Future<SyncJournal> _journal() async => SyncJournal(await catalog());

  /// Downloads a chapter on the server. Nothing is saved here.
  Future<void> download(String seriesId, String chapterId) =>
      _queue([(seriesId, chapterId)], keepLocal: true);

  /// Moves chapters saved here to the server; [keepLocal] keeps the copy
  /// here once the server has it.
  Future<void> moveToServer(
    Iterable<(String seriesId, String chapterId)> chapters, {
    required bool keepLocal,
  }) => _queue(chapters, keepLocal: keepLocal);

  Future<void> _queue(
    Iterable<(String, String)> chapters, {
    required bool keepLocal,
  }) async {
    final journal = await _journal();
    final now = _clock();
    for (final (seriesId, chapterId) in chapters) {
      await journal.putTransfer(
        SyncTransfer(
          seriesId: seriesId,
          chapterId: chapterId,
          keepLocal: keepLocal,
          state: SyncTransferState.queued,
          updatedAt: now,
        ),
      );
    }
    onChanged?.call();
    await run();
  }

  /// Forgets a transfer, unless the server is already downloading it.
  Future<void> cancel(String seriesId, String chapterId) async {
    await (await _journal()).removeTransfer(seriesId, chapterId);
    onChanged?.call();
  }

  /// Advances every transfer once; runs again if asked meanwhile.
  Future<void> run() {
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = () async {
      try {
        do {
          _again = false;
          await _step();
        } while (_again);
      } finally {
        _running = null;
      }
    }();
  }

  /// Checks the server every [pollEvery] while it is downloading.
  void watch() {
    _poll ??= Timer.periodic(pollEvery, (_) => unawaited(run()));
  }

  void stopWatching() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _step() async {
    if (!engine.enabled) return;
    final journal = await _journal();
    final open = await journal.transfers(
      states: {SyncTransferState.queued, SyncTransferState.requested},
    );
    if (open.isEmpty) {
      stopWatching();
      return;
    }
    final baseUrl = await pages.baseUrl();
    // Away from home: the queue waits, and the iPhone's copies stay.
    if (baseUrl == null) return;
    final backend = backendAt(baseUrl);
    final now = _clock();
    var changed = false;

    Future<void> put(SyncTransfer transfer) async {
      await journal.putTransfer(transfer);
      changed = true;
    }

    SyncTransfer next(
      SyncTransfer transfer,
      SyncTransferState state, {
      int? remoteChapterId,
      String? error,
    }) => SyncTransfer(
      seriesId: transfer.seriesId,
      chapterId: transfer.chapterId,
      remoteChapterId: remoteChapterId ?? transfer.remoteChapterId,
      keepLocal: transfer.keepLocal,
      state: state,
      error: error,
      updatedAt: now,
    );

    // queued → requested.
    final toRequest = <SyncTransfer>[];
    for (final transfer in open) {
      if (transfer.state != SyncTransferState.queued) continue;
      final manga = await pages.mangaId(transfer.seriesId);
      final id = manga == null
          ? null
          : await pages.chapterId(baseUrl, manga, transfer.chapterId);
      if (id == null) {
        await put(
          next(
            transfer,
            SyncTransferState.failed,
            error: manga == null
                ? 'The series is not on the server.'
                : 'The server has no such chapter.',
          ),
        );
        continue;
      }
      toRequest.add(
        next(transfer, SyncTransferState.queued, remoteChapterId: id),
      );
    }
    if (toRequest.isNotEmpty) {
      try {
        await backend.enqueueDownloads([
          for (final transfer in toRequest) transfer.remoteChapterId!,
        ]);
        for (final transfer in toRequest) {
          await put(next(transfer, SyncTransferState.requested));
        }
      } catch (error) {
        // Stays queued: the next run asks again.
        if (isSyncAuthFailure(error)) rethrow;
      }
    }

    // requested → verified → done.
    final requested = await journal.transfers(
      states: {SyncTransferState.requested},
    );
    if (requested.isNotEmpty) {
      final states = await backend.downloadStates([
        for (final transfer in requested) transfer.remoteChapterId!,
      ]);
      final local = await catalog();
      for (final transfer in requested) {
        final state = states[transfer.remoteChapterId];
        final expected = transfer.keepLocal
            ? null
            : await _localPages(local, transfer);
        final proven =
            state != null &&
            state.downloaded &&
            state.pageCount > 0 &&
            (expected == null || state.pageCount == expected);
        if (!proven) {
          if (now.difference(transfer.updatedAt) > giveUpAfter) {
            await put(
              next(
                transfer,
                SyncTransferState.failed,
                error: state?.downloaded ?? false
                    ? 'The server has ${state!.pageCount} of $expected pages.'
                    : "The server didn't finish the download.",
              ),
            );
          }
          continue;
        }
        await put(next(transfer, SyncTransferState.verified));
        if (!transfer.keepLocal) {
          await local.removeChapter(transfer.seriesId, transfer.chapterId);
        }
        await put(next(transfer, SyncTransferState.done));
      }
    }
    if (changed) onChanged?.call();
    final waiting = await journal.transfers(
      states: {SyncTransferState.queued, SyncTransferState.requested},
    );
    waiting.isEmpty ? stopWatching() : watch();
  }

  Future<int?> _localPages(LocalCatalog catalog, SyncTransfer transfer) async {
    final series = await catalog.find(transfer.seriesId);
    for (final chapter in series?.chapters ?? const <LocalChapter>[]) {
      if (chapter.id == transfer.chapterId) return chapter.pages.length;
    }
    // Nothing saved here (any more): only the server's report counts.
    return null;
  }

  /// Every transfer this iPhone keeps, for the Downloads page.
  Future<List<SyncTransfer>> all() async => (await _journal()).transfers();

  /// Queues failed transfers again.
  Future<void> retryFailed() async {
    final journal = await _journal();
    final failed = await journal.transfers(states: {SyncTransferState.failed});
    for (final transfer in failed) {
      await journal.putTransfer(
        SyncTransfer(
          seriesId: transfer.seriesId,
          chapterId: transfer.chapterId,
          keepLocal: transfer.keepLocal,
          state: SyncTransferState.queued,
          updatedAt: _clock(),
        ),
      );
    }
    onChanged?.call();
    await run();
  }

  /// Forgets finished and failed transfers; copies here are untouched.
  Future<void> clearFinished() async {
    final journal = await _journal();
    for (final transfer in await journal.transfers(
      states: {SyncTransferState.done, SyncTransferState.failed},
    )) {
      await journal.removeTransfer(transfer.seriesId, transfer.chapterId);
    }
    onChanged?.call();
  }

  /// The server state of every chapter of [seriesId]: downloaded there, and
  /// any transfer here. Empty when the series isn't on a reachable server.
  Future<Map<String, ServerChapterState>> states(String seriesId) async {
    final journal = await _journal();
    final transfers = {
      for (final transfer in await journal.transfers())
        if (transfer.seriesId == seriesId) transfer.chapterId: transfer.state,
    };
    final downloaded = <String>{};
    try {
      final manga = await pages.mangaId(seriesId);
      final baseUrl = manga == null ? null : await pages.baseUrl();
      if (manga != null && baseUrl != null) {
        downloaded.addAll(await pages.downloadedChapters(baseUrl, manga));
      }
    } catch (_) {
      // Away from home: only what this iPhone knows.
    }
    return {
      for (final id in {...downloaded, ...transfers.keys})
        id: (downloaded: downloaded.contains(id), transfer: transfers[id]),
    };
  }

  /// Deletes the server's download of [chapterIds] of [seriesId].
  Future<void> deleteFromServer(
    String seriesId,
    Iterable<String> chapterIds,
  ) async {
    final manga = await pages.mangaId(seriesId);
    final baseUrl = await pages.baseUrl();
    if (manga == null || baseUrl == null) {
      throw StateError('The server is not reachable.');
    }
    final ids = <int>[];
    for (final chapterId in chapterIds) {
      if (await pages.chapterId(baseUrl, manga, chapterId) case final id?) {
        ids.add(id);
      }
    }
    await backendAt(baseUrl).deleteDownloads(ids);
    final journal = await _journal();
    for (final chapterId in chapterIds) {
      await journal.removeTransfer(seriesId, chapterId);
    }
    pages.forget(manga);
    onChanged?.call();
  }

  void dispose() => stopWatching();
}

final serverTransfersProvider = Provider<ServerTransfers>((ref) {
  final client = ref.watch(suwayomiSyncClientProvider);
  final transfers = ServerTransfers(
    engine: ref.watch(syncEngineProvider),
    catalog: () async =>
        (await ref.read(localCollectionServicesProvider.future)).catalog,
    pages: ref.watch(serverChapterPagesProvider),
    backendAt: (baseUrl) => SuwayomiBackend(client.at(baseUrl)),
  );
  ref.onDispose(transfers.dispose);
  return transfers;
});
