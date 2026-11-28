import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_catalog.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/sync_journal.dart';
import '../data/sync_state_store.dart';
import '../domain/sync_change.dart';
import 'sync_engine.dart';

/// Why a series in the Local library is not on the server (design 3.4,
/// Needs attention).
enum UnsyncedReason {
  /// A file import: the server has no source for it.
  importedFile,

  /// From a Kuchie repo, which Suwayomi cannot read.
  kuchieRepo,

  /// From the built-in Shinigami source.
  builtIn,

  /// The server could not add it: its extension may be missing there.
  notOnServer,

  /// A request for it failed; the next cycle tries again.
  requestFailed,

  /// Added since the last cycle.
  waiting;

  /// Whether another sync can fix it.
  bool get retryable =>
      this == notOnServer || this == requestFailed || this == waiting;
}

class UnsyncedSeries {
  const UnsyncedSeries(this.series, this.reason);

  final LocalSyncSeries series;
  final UnsyncedReason reason;
}

/// Library series with no server link, or that failed in the last cycle,
/// with why.
List<UnsyncedSeries> unsyncedSeries({
  required List<LocalSyncSeries> library,
  required Set<String> linked,
  required Map<String, String> errors,
}) => [
  for (final series in library)
    if (series.inLibrary)
      if (_reason(series, linked, errors) case final reason?)
        UnsyncedSeries(series, reason),
];

UnsyncedReason? _reason(
  LocalSyncSeries series,
  Set<String> linked,
  Map<String, String> errors,
) {
  // Read through the server, so it is synced.
  if (isServerOnlySeriesId(series.id)) return null;
  final source = series.source;
  if (source == null) return UnsyncedReason.importedFile;
  if (parseLocalSource(source.sourceId) == null) {
    return source.sourceId == builtInShinigamiPackage
        ? UnsyncedReason.builtIn
        : UnsyncedReason.kuchieRepo;
  }
  if (errors[series.id] == SyncSeriesError.requestFailed.name) {
    return UnsyncedReason.requestFailed;
  }
  if (linked.contains(series.id)) return null;
  if (errors[series.id] == SyncSeriesError.notOnServer.name) {
    return UnsyncedReason.notOnServer;
  }
  return UnsyncedReason.waiting;
}

final unsyncedSeriesProvider = FutureProvider.autoDispose<List<UnsyncedSeries>>(
  (ref) async {
    final services = await ref.watch(localCollectionServicesProvider.future);
    final journal = SyncJournal(services.catalog);
    final links = await journal.links('suwayomi');
    return unsyncedSeries(
      library: await services.catalog.syncSeries(),
      linked: {
        for (final link in links)
          if (link.kind == SyncLinkKind.series) link.localKey,
      },
      errors: ref.watch(syncStateStoreProvider).seriesErrors,
    );
  },
);
