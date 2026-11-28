import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../local_collection/data/local_catalog.dart';

import '../../local_collection/data/local_collection_providers.dart';
import '../../local_collection/data/local_collection_services.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import '../data/sync_state_store.dart';
import 'sync_engine.dart';

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final client = ref.watch(suwayomiSyncClientProvider);
  Future<LocalCollectionServices> services() =>
      ref.read(localCollectionServicesProvider.future);
  final engine = SyncEngine(
    catalog: () async => (await services()).catalog,
    store: ref.watch(syncStateStoreProvider),
    probe: () => ref.read(suwayomiReachabilityProvider).probe(),
    backendAt: (baseUrl) => SuwayomiBackend(client.at(baseUrl)),
    localSources: () async {
      final sources = await (await services()).sources.sources();
      return {
        for (final source in sources)
          if (source.enabled)
            if (parseLocalSource(source.id) case (:final sourceId, package: _))
              sourceId: SyncLocalSource(
                id: source.id,
                catalogOrigin: source.catalogOrigin,
                name: source.name,
              ),
      };
    },
    ensureServerIdentity: (baseUrl) =>
        OfflineServerIdentityRepository(client.at(baseUrl)).resolve(),
    readerMeta: ref.watch(localSeriesReaderMetaProvider),
    onNewSeries: (baseUrl, series) => unawaited(
      fetchServerCovers(
        baseUrl: baseUrl,
        series: series,
        headers: () => client.headers(baseUrl),
        catalog: () async => (await services()).catalog,
      ),
    ),
  );
  ref.onDispose(engine.cancel);
  return engine;
});

/// Keeps the server's covers for series sync just added, as opening a
/// series would; the library shows them from then on. Covers already kept
/// stay.
Future<void> fetchServerCovers({
  required String baseUrl,
  required List<({String seriesId, String thumbnailUrl})> series,
  required Future<Map<String, String>> Function() headers,
  required Future<LocalCatalog> Function() catalog,
}) async {
  final local = await catalog();
  await local.loadKeptCovers();
  final client = http.Client();
  try {
    final sent = await headers();
    final base = Uri.parse(baseUrl);
    for (final entry in series) {
      if (local.keptCover(entry.seriesId) != null) continue;
      try {
        final response = await client
            .get(base.resolve(entry.thumbnailUrl), headers: sent)
            .timeout(const Duration(seconds: 20));
        final type = response.headers['content-type'] ?? '';
        if (response.statusCode == 200 && type.startsWith('image/')) {
          await local.saveSourceCover(entry.seriesId, response.bodyBytes);
        }
      } catch (_) {
        // The library shows the placeholder; opening the series fetches it.
      }
    }
  } finally {
    client.close();
  }
}
