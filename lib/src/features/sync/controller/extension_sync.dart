import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../local_collection/data/local_collection_providers.dart';
import '../../local_collection/data/local_sources.dart';
import '../data/suwayomi/suwayomi_backend.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/suwayomi/suwayomi_sync_client.dart';
import 'sync_engine.dart';
import 'sync_engine_provider.dart';

/// Extensions that differ between this iPhone and the server (design 3.5).
class ExtensionSuggestions {
  const ExtensionSuggestions({
    required this.onlyOnServer,
    required this.onlyHere,
    required this.notInServerStores,
    this.storesToAdd = const [],
    this.seriesByPackage = const {},
    this.serverOnly = const [],
  });

  /// Installed on the server, not here: their series can't be read here,
  /// so sync leaves them out. Most series first.
  final List<ServerExtension> onlyOnServer;

  /// Installed here, and the server's stores have it: one tap installs it
  /// there, so its series sync.
  final List<ServerExtension> onlyHere;

  /// Installed here, but no store on the server lists it.
  final List<String> notInServerStores;

  /// Server stores this iPhone doesn't have yet, matched by signing key.
  final List<ServerStore> storesToAdd;

  /// Package → how many series of the server library it reads.
  final Map<String, int> seriesByPackage;

  /// On the server, but not installable here: Kuchie has its own built-in
  /// Shinigami source, and Keiyoushi lists Shinigami without an APK for
  /// iPhone. Their series stay on the server.
  final List<ServerExtension> serverOnly;

  /// Server library series waiting for an extension here.
  int get seriesWaiting => onlyOnServer.fold(
    0,
    (sum, extension) => sum + (seriesByPackage[extension.package] ?? 0),
  );

  /// Server library series only the server can read.
  int get seriesServerOnly => serverOnly.fold(
    0,
    (sum, extension) => sum + (seriesByPackage[extension.package] ?? 0),
  );

  bool get isEmpty =>
      onlyOnServer.isEmpty &&
      onlyHere.isEmpty &&
      notInServerStores.isEmpty &&
      serverOnly.isEmpty;
}

ExtensionSuggestions compareExtensions({
  required List<ServerExtension> server,
  required Set<String> here,
  List<ServerStore> serverStores = const [],
  Set<String> storeKeysHere = const {},
  Map<String, int> seriesByPackage = const {},
}) {
  final listed = {for (final extension in server) extension.package: extension};
  bool installable(ServerExtension extension) =>
      extension.package != builtInShinigamiPackage;
  final missing = [
    for (final extension in server)
      if (extension.installed && !here.contains(extension.package)) extension,
  ];
  final onlyOnServer = missing.where(installable).toList();
  onlyOnServer.sort(
    (a, b) => (seriesByPackage[b.package] ?? 0).compareTo(
      seriesByPackage[a.package] ?? 0,
    ),
  );
  final neededStores = {
    for (final extension in onlyOnServer) ?extension.storeIndexUrl,
  };
  return ExtensionSuggestions(
    onlyOnServer: onlyOnServer,
    onlyHere: [
      for (final package in here)
        if (listed[package] case final extension? when !extension.installed)
          extension,
    ],
    notInServerStores: [
      for (final package in here)
        if (!listed.containsKey(package)) package,
    ]..sort(),
    storesToAdd: [
      for (final store in serverStores)
        if (!storeKeysHere.contains(store.signingKey) &&
            neededStores.contains(store.indexUrl))
          store,
    ],
    seriesByPackage: seriesByPackage,
    serverOnly: missing.whereNot(installable).toList(),
  );
}

/// What "Install from the server" did.
class ServerExtensionsReport {
  const ServerExtensionsReport({
    this.storesAdded = const [],
    this.installed = const [],
    this.failed = const {},
  });

  final List<String> storesAdded;
  final List<String> installed;

  /// Extension name → why it didn't install here.
  final Map<String, String> failed;
}

/// Installs and compares extensions on the sync server.
class ExtensionSync {
  ExtensionSync({
    required this.engine,
    required this.probe,
    required this.backendAt,
    required this.localSources,
  });

  final SyncEngine engine;
  final Future<SuwayomiReachability> Function() probe;
  final SuwayomiBackend Function(String baseUrl) backendAt;
  final Future<LocalSources> Function() localSources;

  Future<SuwayomiBackend?> _backend() async {
    if (!engine.enabled) return null;
    final reachability = await probe();
    return reachability is SuwayomiReachable
        ? backendAt(reachability.baseUrl)
        : null;
  }

  Future<Set<String>> _packagesHere(LocalSources sources) async => {
    for (final source in await sources.sources())
      if (parseLocalSource(source.id) case (:final package, sourceId: _))
        package,
  };

  /// Null while sync is off or the server can't be reached.
  Future<ExtensionSuggestions?> suggestions() async {
    final backend = await _backend();
    if (backend == null) return null;
    final sources = await localSources();
    final (server, stores, packages, library) = await (
      backend.extensions(),
      backend.extensionStores(),
      backend.sourcePackages(),
      backend.library(),
    ).wait;
    final seriesByPackage = <String, int>{};
    for (final series in library) {
      if (packages[series.sourceId] case final package?) {
        seriesByPackage[package] = (seriesByPackage[package] ?? 0) + 1;
      }
    }
    return compareExtensions(
      server: server,
      here: await _packagesHere(sources),
      serverStores: stores,
      storeKeysHere: {
        for (final repository in await sources.repositories())
          ?repository.signingKey?.toLowerCase(),
      },
      seriesByPackage: seriesByPackage,
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

  /// Makes this iPhone read what the server reads (design 3.5): adds the
  /// server's stores it lacks, then installs every extension the server
  /// has, then syncs so their series arrive. Each APK is still checked
  /// against its store's key; one a store didn't sign is left out.
  Future<ServerExtensionsReport> installFromServer(
    ExtensionSuggestions suggestions, {
    void Function(String step)? onStep,
  }) async {
    final sources = await localSources();
    final added = <String>[];
    final failed = <String, String>{};
    for (final store in suggestions.storesToAdd) {
      onStep?.call(store.name);
      try {
        await sources.addRepository(_storeIndex(store));
        added.add(store.name);
      } catch (error) {
        failed[store.name] = '$error';
      }
    }
    final byPackage = <String, LocalSourcePackage>{};
    for (final repository in await sources.repositories()) {
      for (final package in repository.packages) {
        byPackage.putIfAbsent(package.id, () => package);
      }
    }
    final installed = <String>[];
    final here = await _packagesHere(sources);
    for (final extension in suggestions.onlyOnServer) {
      if (here.contains(extension.package)) continue;
      final package = byPackage[extension.package];
      if (package == null) {
        failed[extension.name] = 'Not in the stores on this iPhone.';
        continue;
      }
      onStep?.call(extension.name);
      try {
        await sources.install(package);
        installed.add(extension.name);
      } on LocalSourceUntrustedException {
        failed[extension.name] = "Its store didn't sign it.";
      } catch (error) {
        failed[extension.name] = '$error';
      }
    }
    // A large library takes a while; the Library fills in when it's done.
    if (installed.isNotEmpty) unawaited(engine.sync(manual: true));
    return ServerExtensionsReport(
      storesAdded: added,
      installed: installed,
      failed: failed,
    );
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

/// Keiyoushi is saved under Kuchie's own address, as everywhere else in
/// Kuchie; other stores under the server's.
Uri _storeIndex(ServerStore store) => store.signingKey == keiyoushiSigningKey
    ? LocalSources.keiyoushiIndex
    : Uri.parse(store.indexUrl);

final extensionSyncProvider = Provider<ExtensionSync>((ref) {
  final client = ref.watch(suwayomiSyncClientProvider);
  return ExtensionSync(
    engine: ref.watch(syncEngineProvider),
    probe: () => ref.read(suwayomiReachabilityProvider).probe(),
    backendAt: (baseUrl) => SuwayomiBackend(client.at(baseUrl)),
    localSources: () async =>
        (await ref.read(localCollectionServicesProvider.future)).sources,
  );
});

final extensionSuggestionsProvider =
    FutureProvider.autoDispose<ExtensionSuggestions?>(
      (ref) => ref.watch(extensionSyncProvider).suggestions(),
    );
