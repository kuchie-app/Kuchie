import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_catalog.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../data/sync_journal.dart';
import '../domain/sync_change.dart';
import 'server_transfers.dart';
import 'sync_engine_provider.dart';

/// What Move to server would move (design 3.6).
class MovePlan {
  const MovePlan({
    required this.chapters,
    required this.bytes,
    required this.excluded,
  });

  /// Saved chapters of series on the server.
  final List<({String seriesId, String chapterId})> chapters;

  /// Their size here: what deleting them frees.
  final int bytes;

  /// Saved chapters the server can't have: imports and Kuchie repo series.
  final int excluded;

  bool get isEmpty => chapters.isEmpty;
}

/// Plans Move to server over every saved chapter, one series', or some
/// chapters of it.
Future<MovePlan> planMoveToServer(
  LocalCatalog catalog, {
  String? seriesId,
  Set<String>? chapterIds,
}) async {
  final linked = {
    for (final link in await SyncJournal(catalog).links('suwayomi'))
      if (link.kind == SyncLinkKind.series) link.localKey,
  };
  final moving = await SyncJournal(catalog).transfers(
    states: {
      SyncTransferState.queued,
      SyncTransferState.requested,
      SyncTransferState.verified,
    },
  );
  final busy = {
    for (final transfer in moving) (transfer.seriesId, transfer.chapterId),
  };
  final chapters = <({String seriesId, String chapterId})>[];
  var bytes = 0;
  var excluded = 0;
  for (final series in await catalog.list()) {
    if (seriesId != null && series.id != seriesId) continue;
    for (final chapter in series.chapters) {
      if (chapterIds != null && !chapterIds.contains(chapter.id)) continue;
      if (busy.contains((series.id, chapter.id))) continue;
      if (!linked.contains(series.id)) {
        excluded++;
        continue;
      }
      chapters.add((seriesId: series.id, chapterId: chapter.id));
      for (final page in chapter.pages) {
        try {
          bytes += await page.length();
        } on FileSystemException {
          // A missing page counts as nothing.
        }
      }
    }
  }
  return MovePlan(chapters: chapters, bytes: bytes, excluded: excluded);
}

/// Plans and starts moves, for the sheet.
class MoveToServer {
  MoveToServer(this._ref);

  final Ref _ref;

  bool get enabled => _ref.read(syncEngineProvider).enabled;

  Future<MovePlan> plan({String? seriesId, Set<String>? chapterIds}) async =>
      planMoveToServer(
        (await _ref.read(localCollectionServicesProvider.future)).catalog,
        seriesId: seriesId,
        chapterIds: chapterIds,
      );

  Future<void> start(MovePlan plan, {required bool keepLocal}) =>
      _ref.read(serverTransfersProvider).moveToServer([
        for (final chapter in plan.chapters)
          (chapter.seriesId, chapter.chapterId),
      ], keepLocal: keepLocal);
}

final moveToServerProvider = Provider<MoveToServer>(MoveToServer.new);
