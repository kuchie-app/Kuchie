import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'local_catalog.dart';
import 'local_download_queue.dart';
import 'local_sources.dart';

class LocalCollectionServices {
  LocalCollectionServices(
    Directory directory, {
    bool allowInsecureLoopback = false,
  }) : catalog = LocalCatalog(Directory('${directory.path}/catalog')),
       sources = LocalSources(
         directory,
         allowInsecureLoopback: allowInsecureLoopback,
       ),
       _queueFile = File('${directory.path}/downloads.json');

  final LocalCatalog catalog;
  final LocalSources sources;
  final File _queueFile;
  late final LocalDownloadQueue downloads = LocalDownloadQueue(
    catalog,
    _queueFile,
    resolveRuntimeChapter: sources.refreshChapterPages,
  );

  static Future<LocalCollectionServices>? _current;
  static final ValueNotifier<LocalDownloadQueue?> activeQueue = ValueNotifier(
    null,
  );

  static Future<LocalCollectionServices> open() => _current ??= _open();

  static Future<LocalCollectionServices> _open() async {
    try {
      final support = await getApplicationSupportDirectory();
      final service = LocalCollectionServices(
        Directory('${support.path}/local-collection'),
        allowInsecureLoopback: kDebugMode,
      );
      await service.downloads.load();
      activeQueue.value = service.downloads;
      return service;
    } catch (_) {
      _current = null;
      rethrow;
    }
  }
}

String localSourceSeriesId(LocalExtension source, String mangaId) => base64Url
    .encode(
      utf8.encode(
        jsonEncode([source.catalogOrigin.toString(), source.id, mangaId]),
      ),
    )
    .replaceAll('=', '');

typedef LocalSeriesIdentity = ({
  String origin,
  String sourceId,
  String mangaId,
});

LocalSeriesSource? localSeriesReference(
  LocalSources sources,
  LocalSeries series,
) {
  final identity = parseLocalSourceSeriesId(series.id);
  if (identity == null) return null;
  final reference = series.source;
  if (reference != null &&
      reference.sourceId == identity.sourceId &&
      reference.mangaId == identity.mangaId) {
    return reference;
  }
  return sources.legacySeriesReference(identity.sourceId, identity.mangaId);
}

LocalSeriesIdentity? parseLocalSourceSeriesId(String value) {
  if (value.length > 2048) return null;
  try {
    return switch (jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(value))),
    )) {
      [final String origin, final String sourceId, final String mangaId] => (
        origin: origin,
        sourceId: sourceId,
        mangaId: mangaId,
      ),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}
