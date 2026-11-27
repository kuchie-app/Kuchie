import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_collection_providers.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_library_reader.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import '../data/sync_state_store.dart';

/// Which way the first sync goes (design 3.3).
enum ConnectBranch {
  /// Nothing on this iPhone yet: copy the server's library.
  localEmpty,

  /// Nothing on the server yet: send this iPhone's library.
  remoteEmpty,

  /// Both have the same library: just sync.
  allMatched,

  /// Both have series the other doesn't: the reader chooses.
  differs,
}

/// The connect report. Nothing has been written when it exists.
class ConnectAnalysis {
  const ConnectAnalysis({
    required this.serverAddress,
    required this.localCount,
    required this.remoteCount,
    required this.match,
  });

  final String serverAddress;
  final int localCount;
  final int remoteCount;
  final SeriesMatch match;

  int get matched => match.links.length;
  int get onlyLocal => match.onlyLocal.length;
  int get onlyRemote => match.onlyRemote.length;

  /// Only on this iPhone, but the server has the extension to add them.
  int get sendable =>
      match.onlyLocal.where((entry) => entry.$2.sendable).length;

  /// Only on this iPhone and can't go to the server: imports, Kuchie repo
  /// and built-in sources, or extensions the server lacks.
  int get unsendable => onlyLocal - sendable;

  /// Only on the server, and this iPhone has the extension to read them.
  int get readableHere => match.onlyRemote.where((entry) => entry.$2).length;
  int get notReadableHere => onlyRemote - readableHere;

  ConnectBranch get branch {
    if (localCount == 0) return ConnectBranch.localEmpty;
    if (remoteCount == 0) return ConnectBranch.remoteEmpty;
    if (onlyLocal == 0 && onlyRemote == 0) return ConnectBranch.allMatched;
    return ConnectBranch.differs;
  }

  /// What the first sync does without asking, for the other branches.
  ConnectChoice? get impliedChoice => switch (branch) {
    ConnectBranch.localEmpty => ConnectChoice.useServer,
    ConnectBranch.remoteEmpty => ConnectChoice.useLocal,
    ConnectBranch.allMatched => ConnectChoice.merge,
    ConnectBranch.differs => null,
  };
}

ConnectAnalysis analyzeConnection({
  required String serverAddress,
  required List<LocalSeriesRef> local,
  required ServerLibrary server,
  required Set<String> localSourceIds,
}) => ConnectAnalysis(
  serverAddress: serverAddress,
  localCount: local.length,
  remoteCount: server.series.length,
  match: matchSeries(
    local: local,
    remote: server.series,
    serverPackages: server.packages,
    localSourceIds: localSourceIds,
  ),
);

/// The server could not be read while analysing.
class ConnectFailure implements Exception {
  const ConnectFailure(this.reachability);

  final SuwayomiReachability reachability;

  bool get signInNeeded => reachability is SuwayomiAuthFailed;
}

/// Reads both libraries and pairs them. Writes nothing.
final connectAnalysisProvider = FutureProvider.autoDispose<ConnectAnalysis>((
  ref,
) async {
  final reachability = await ref.read(suwayomiReachabilityProvider).probe();
  if (reachability is! SuwayomiReachable) throw ConnectFailure(reachability);
  final client = ref.read(suwayomiSyncClientProvider).at(reachability.baseUrl);
  final services = await ref.read(localCollectionServicesProvider.future);
  final (server, library, sources) = await (
    readServerLibrary(client),
    services.catalog.list(),
    services.sources.sources(),
  ).wait;
  return analyzeConnection(
    serverAddress: reachability.baseUrl,
    local: [
      for (final series in library)
        if (series.inLibrary)
          LocalSeriesRef(
            id: series.id,
            title: series.title,
            sourceId: series.source?.sourceId,
            locator: series.source?.locator,
          ),
    ],
    server: server,
    localSourceIds: {
      for (final source in sources)
        if (parseLocalSource(source.id) case (:final sourceId, package: _))
          sourceId,
    },
  );
});
