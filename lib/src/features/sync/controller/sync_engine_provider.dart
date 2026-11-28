import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  );
  ref.onDispose(engine.cancel);
  return engine;
});
