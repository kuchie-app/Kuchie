import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_collection_providers.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// Extensions that differ between this iPhone and the server (design 3.5).
/// Sync only suggests; installing stays the reader's tap.
class ExtensionSuggestions {
  const ExtensionSuggestions({
    required this.onlyOnServer,
    required this.onlyHere,
    required this.notInServerStores,
  });

  /// Installed on the server, not here: its series can't be read here.
  final List<ServerExtension> onlyOnServer;

  /// Installed here, and the server's stores have it: one tap installs it
  /// there, so its series sync.
  final List<ServerExtension> onlyHere;

  /// Installed here, but no store on the server lists it.
  final List<String> notInServerStores;

  bool get isEmpty =>
      onlyOnServer.isEmpty && onlyHere.isEmpty && notInServerStores.isEmpty;
}

ExtensionSuggestions compareExtensions({
  required List<ServerExtension> server,
  required Set<String> here,
}) {
  final listed = {for (final extension in server) extension.package: extension};
  return ExtensionSuggestions(
    onlyOnServer: [
      for (final extension in server)
        if (extension.installed && !here.contains(extension.package)) extension,
    ],
    onlyHere: [
      for (final package in here)
        if (listed[package] case final extension? when !extension.installed)
          extension,
    ],
    notInServerStores: [
      for (final package in here)
        if (!listed.containsKey(package)) package,
    ]..sort(),
  );
}

/// Installs and compares extensions on the sync server.
class ExtensionSync {
  ExtensionSync({
    required this.engine,
    required this.probe,
    required this.backendAt,
    required this.packagesHere,
  });

  final SyncEngine engine;
  final Future<SuwayomiReachability> Function() probe;
  final SuwayomiBackend Function(String baseUrl) backendAt;

  /// Mihon packages installed on this iPhone.
  final Future<Set<String>> Function() packagesHere;

  Future<SuwayomiBackend?> _backend() async {
    if (!engine.enabled) return null;
    final reachability = await probe();
    return reachability is SuwayomiReachable
        ? backendAt(reachability.baseUrl)
        : null;
  }

  /// Null while sync is off or the server can't be reached.
  Future<ExtensionSuggestions?> suggestions() async {
    final backend = await _backend();
    if (backend == null) return null;
    return compareExtensions(
      server: await backend.extensions(),
      here: await packagesHere(),
    );
  }

  /// Installs [packages] on the server; returns those that failed.
  Future<List<String>> installOnServer(Iterable<String> packages) async {
    final backend = await _backend();
    if (backend == null) return packages.toList();
    final failed = <String>[];
    for (final package in packages) {
      try {
        await backend.installExtension(package);
      } catch (_) {
        failed.add(package);
      }
    }
    if (failed.length < packages.length) {
      // Series of the new extension can sync now.
      await engine.sync();
    }
    return failed;
  }

  /// One Install button (design 3.5): an extension installed here goes on
  /// the server too when its stores list it. A failure there never fails
  /// the install here.
  Future<void> installedHere(String package) async {
    try {
      final backend = await _backend();
      if (backend == null) return;
      final listed = (await backend.extensions())
          .where((extension) => extension.package == package)
          .firstOrNull;
      if (listed == null || listed.installed) return;
      await backend.installExtension(package);
      await engine.sync();
    } catch (_) {
      // Shown as a suggestion on the Sync page next time.
    }
  }
}

final extensionSyncProvider = Provider<ExtensionSync>((ref) {
  final client = ref.watch(suwayomiSyncClientProvider);
  return ExtensionSync(
    engine: ref.watch(syncEngineProvider),
    probe: () => ref.read(suwayomiReachabilityProvider).probe(),
    backendAt: (baseUrl) => SuwayomiBackend(client.at(baseUrl)),
    packagesHere: () async {
      final services = await ref.read(localCollectionServicesProvider.future);
      return {
        for (final source in await services.sources.sources())
          if (parseLocalSource(source.id) case (:final package, sourceId: _))
            package,
      };
    },
  );
});

final extensionSuggestionsProvider =
    FutureProvider.autoDispose<ExtensionSuggestions?>(
      (ref) => ref.watch(extensionSyncProvider).suggestions(),
    );
