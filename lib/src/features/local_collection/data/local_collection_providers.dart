// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../global_providers/global_providers.dart';
import 'local_catalog.dart';
import 'local_collection_services.dart';
import 'local_download_queue.dart';
import 'local_series_reader_meta.dart';

part 'local_collection_providers.g.dart';

/// Where the Local profile lives. Tests override this with a temporary folder.
@Riverpod(keepAlive: true)
Future<Directory> localCollectionDirectory(Ref ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/local-collection');
}

/// Opened on first use so the Server collection never touches Local storage.
///
/// Override with [LocalCollectionServices.custom] to inject fakes or mocks.
@Riverpod(keepAlive: true)
Future<LocalCollectionServices> localCollectionServices(Ref ref) async {
  final directory = await ref.watch(localCollectionDirectoryProvider.future);
  final services = LocalCollectionServices(
    directory,
    allowInsecureLoopback: kDebugMode,
  );
  await services.downloads.load();
  // A reopened collection attaches its own queue in place of this one.
  ref
      .read(activeLocalDownloadQueueProvider.notifier)
      .attach(services.downloads);
  ref.read(activeLocalCatalogProvider.notifier).attach(services.catalog);
  return services;
}

/// The catalog of the Local collection once it has opened. Watching this
/// never opens the collection by itself.
@Riverpod(keepAlive: true)
class ActiveLocalCatalog extends _$ActiveLocalCatalog {
  @override
  LocalCatalog? build() => null;

  void attach(LocalCatalog catalog) => state = catalog;
}

/// Per-series reader settings of the Local collection. Changes reach the sync
/// outbox through the open catalog; saving them never opens it.
@Riverpod(keepAlive: true)
LocalSeriesReaderMeta localSeriesReaderMeta(Ref ref) => LocalSeriesReaderMeta(
  ref.watch(sharedPreferencesProvider),
  onChanged: (seriesId) =>
      ref.read(activeLocalCatalogProvider)?.recordReaderMetaChange(seriesId),
);

/// The queue Live Activities follow once the Local collection has opened.
///
/// Watching this never opens the Local collection by itself.
@Riverpod(keepAlive: true)
class ActiveLocalDownloadQueue extends _$ActiveLocalDownloadQueue {
  @override
  LocalDownloadQueue? build() => null;

  void attach(LocalDownloadQueue queue) => state = queue;
}
