import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_catalog.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/sync_journal.dart';
import '../domain/sync_change.dart';
import 'sync_engine_provider.dart';

/// Why a Local series has no server counterpart to track or read through.
enum ServerSeriesGap {
  /// Sync with a Suwayomi server is off.
  syncOff,

  /// From a file import or a Kuchie repo: the server has no source for it.
  noServerSource,

  /// Syncable, but no cycle has linked it yet.
  notSynced,
}

/// A Local series' manga id on the sync server, or why there is none.
typedef ServerSeries = ({int? mangaId, ServerSeriesGap? gap});

final serverSeriesProvider = FutureProvider.autoDispose
    .family<ServerSeries, LocalSeries>((ref, series) async {
      if (!ref.watch(syncEngineProvider).enabled) {
        return (mangaId: null, gap: ServerSeriesGap.syncOff);
      }
      final source = series.source;
      if (source == null || suwayomiSourceIdOf(source.sourceId) == null) {
        return (mangaId: null, gap: ServerSeriesGap.noServerSource);
      }
      final services = await ref.watch(localCollectionServicesProvider.future);
      final remoteId = await SyncJournal(
        services.catalog,
      ).remoteIdFor('suwayomi', SyncLinkKind.series, series.id);
      return switch (int.tryParse(remoteId ?? '')) {
        final int id => (mangaId: id, gap: null),
        null => (mangaId: null, gap: ServerSeriesGap.notSynced),
      };
    });
