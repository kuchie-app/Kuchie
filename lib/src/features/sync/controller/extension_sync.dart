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
    this.missingEverywhere = const [],
    this.unknownSources = const {},
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

  /// Extensions the server library's series need but neither side has: the
  /// server lost them (uninstalled), and a store here lists their source.
  /// Installing puts them on both.
  final List<ServerExtension> missingEverywhere;

  /// Server source id → series of a source no extension anywhere is known
  /// for; a store added later may list it.
  final Map<String, int> unknownSources;

  /// Server library series waiting for an extension here.
  int get seriesWaiting => [...onlyOnServer, ...missingEverywhere].fold(
    0,
    (sum, extension) => sum + (seriesByPackage[extension.package] ?? 0),
  );

  /// Everything one tap installs on this iPhone.
  List<ServerExtension> get toInstall => [
    ...onlyOnServer,
    ...missingEverywhere,
  ];

  /// Series no known extension reads, here or on the server.
  int get seriesUnknown => unknownSources.values.sum;

  bool get isEmpty =>
      onlyOnServer.isEmpty &&
      onlyHere.isEmpty &&
      notInServerStores.isEmpty &&
      missingEverywhere.isEmpty;
}

/// A store package on this iPhone, by the sources it serves.
typedef StorePackageRef = ({String package, String name, String language});

ExtensionSuggestions compareExtensions({
  required List<ServerExtension> server,
  required Set<String> here,
  List<ServerStore> serverStores = const [],
  Set<String> storeKeysHere = const {},
  Map<String, int> seriesByPackage = const {},
  Map<String, int> orphanSeries = const {},
  Map<String, StorePackageRef> packagesBySource = const {},
}) {
  final listed = {for (final extension in server) extension.package: extension};
  // Series whose source the server lost: a store here may still list it.
  final byPackage = {...seriesByPackage};
  final unknown = <String, int>{};
  final missing = <String, ServerExtension>{};
  for (final MapEntry(key: sourceId, value: count) in orphanSeries.entries) {
    final ref = packagesBySource[sourceId];
    if (ref == null) {
      unknown[sourceId] = count;
      continue;
    }
    byPackage[ref.package] = (byPackage[ref.package] ?? 0) + count;
    if (here.contains(ref.package)) continue;
    missing[ref.package] = ServerExtension(
      package: ref.package,
      name: listed[ref.package]?.name ?? ref.name,
      language: listed[ref.package]?.language ?? ref.language,
      installed: false,
      storeIndexUrl: listed[ref.package]?.storeIndexUrl,
    );
  }
  // Shinigami included: Keiyoushi lists it for Kuchie's built-in adapter,
  // which reads the same ids as the server's extension.
  final onlyOnServer = [
    for (final extension in server)
      if (extension.installed && !here.contains(extension.package)) extension,
  ];
  int bySeries(ServerExtension a, ServerExtension b) =>
      (byPackage[b.package] ?? 0).compareTo(byPackage[a.package] ?? 0);
  onlyOnServer.sort(bySeries);
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
    missingEverywhere: missing.values.toList()..sort(bySeries),
    unknownSources: unknown,
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
    seriesByPackage: byPackage,
  );
}

/// Source id → package, from the stores saved on this iPhone.
Map<String, StorePackageRef> storePackagesBySource(
  Iterable<LocalSourceRepository> repositories,
) => {
  for (final repository in repositories)
    for (final package in repository.packages)
      for (final sourceId in package.sourceIds)
        sourceId: (
          package: package.id,
          name: package.name,
          language: package.language,
        ),
  // Built-in Shinigami serves the Mihon extension's source id.
  shinigamiSuwayomiSourceId: (
    package: builtInShinigamiPackage,
    name: 'Shinigami',
    language: 'id',
  ),
};

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
  bool _storesRefreshed = false;

  Future<SuwayomiBackend?> _backend() async {
    if (!engine.enabled) return null;
    final reachability = await probe();
    return reachability is SuwayomiReachable
        ? backendAt(reachability.baseUrl)
        : null;
  }

  Future<Set<String>> _packagesHere(LocalSources sources) async => {
    for (final source in await sources.sources()) ?suwayomiPackageOf(source.id),
  };

  /// Null while sync is off or the server can't be reached.
  Future<ExtensionSuggestions?> suggestions() async {
    final backend = await _backend();
    return backend == null ? null : suggestionsFrom(backend);
  }

  /// Compares with the server behind [backend], sync on or not: connecting
  /// asks before the first sync.
  Future<ExtensionSuggestions> suggestionsFrom(SuwayomiBackend backend) async {
    final sources = await localSources();
    final (server, stores, packages, library) = await (
      backend.extensions(),
      backend.extensionStores(),
      backend.sourcePackages(),
      backend.library(),
    ).wait;
    final readHere = {
      for (final source in await sources.sources())
        ?suwayomiSourceIdOf(source.id),
    };
    final seriesByPackage = <String, int>{};
    final orphanSeries = <String, int>{};
    for (final series in library) {
      if (packages[series.sourceId] case final package?) {
        seriesByPackage[package] = (seriesByPackage[package] ?? 0) + 1;
      } else if (!readHere.contains(series.sourceId)) {
        // The server lost its extension, and none here reads it.
        orphanSeries[series.sourceId] =
            (orphanSeries[series.sourceId] ?? 0) + 1;
      }
    }
    var repositories = await sources.repositories();
    // Stores saved before Kuchie kept source ids lack them: read them once.
    if (!_storesRefreshed &&
        orphanSeries.keys.any(
          (id) => !storePackagesBySource(repositories).containsKey(id),
        )) {
      _storesRefreshed = true;
      for (final repository in repositories) {
        try {
          await sources.refreshRepository(repository.url);
        } catch (_) {
          // Offline or retired: what was saved still counts.
        }
      }
      repositories = await sources.repositories();
    }
    return compareExtensions(
      server: server,
      here: await _packagesHere(sources),
      serverStores: stores,
      storeKeysHere: {
        for (final repository in repositories)
          ?repository.signingKey?.toLowerCase(),
      },
      seriesByPackage: seriesByPackage,
      orphanSeries: orphanSeries,
      packagesBySource: storePackagesBySource(repositories),
    );
  }

  /// Extensions installed on the server, for location badges; null while
  /// sync is off or the server can't be reached.
  Future<Set<String>?> serverInstalled() async {
    final backend = await _backend();
    if (backend == null) return null;
    return {
      for (final extension in await backend.extensions())
        if (extension.installed) extension.package,
    };
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
    bool syncAfter = true,
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
    final repositories = await sources.repositories();
    final byPackage = <String, LocalSourcePackage>{};
    for (final repository in repositories) {
      for (final package in repository.packages) {
        byPackage.putIfAbsent(package.id, () => package);
      }
    }
    // Sources the server lost that a store added just now lists.
    final bySource = storePackagesBySource(repositories);
    final lost = {
      for (final extension in suggestions.missingEverywhere)
        extension.package: extension,
      for (final sourceId in suggestions.unknownSources.keys)
        if (bySource[sourceId] case final ref?)
          ref.package: ServerExtension(
            package: ref.package,
            name: ref.name,
            language: ref.language,
            installed: false,
          ),
    };
    final installed = <String>[];
    final here = await _packagesHere(sources);
    for (final extension in [...suggestions.onlyOnServer, ...lost.values]) {
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
    // The server lost these; it reads their series again once it has them.
    if (lost.isNotEmpty) {
      try {
        final backend = await _backend();
        for (final package in lost.keys) {
          try {
            await backend?.installExtension(package);
          } catch (_) {
            // Not in the server's stores: the Sync page says so.
          }
        }
      } catch (_) {
        // Server unreachable: the iPhone still reads them.
      }
    }
    // A large library takes a while; the Library fills in when it's done.
    if (syncAfter && installed.isNotEmpty) {
      unawaited(engine.sync(manual: true));
    }
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

final serverExtensionPackagesProvider =
    FutureProvider.autoDispose<Set<String>?>(
      (ref) => ref.watch(extensionSyncProvider).serverInstalled(),
    );
