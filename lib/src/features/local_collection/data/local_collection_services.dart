import 'dart:convert';
import 'dart:io';

import 'local_catalog.dart';
import 'local_download_queue.dart';
import 'local_sources.dart';

/// The Local collection's storage, sources and download queue.
///
/// Obtain it from `localCollectionServicesProvider`; widgets receive it by
/// constructor so tests can pass [LocalCollectionServices.custom].
class LocalCollectionServices {
  factory LocalCollectionServices(
    Directory directory, {
    bool allowInsecureLoopback = false,
  }) {
    final catalog = LocalCatalog(Directory('${directory.path}/catalog'));
    final sources = LocalSources(
      directory,
      allowInsecureLoopback: allowInsecureLoopback,
    );
    return LocalCollectionServices.custom(
      catalog: catalog,
      sources: sources,
      downloads: LocalDownloadQueue(
        catalog,
        File('${directory.path}/downloads.json'),
        resolveRuntimeChapter: sources.refreshChapterPages,
      ),
    );
  }

  /// Wires already-built dependencies, such as fakes or mocks in tests.
  const LocalCollectionServices.custom({
    required this.catalog,
    required this.sources,
    required this.downloads,
  });

  final LocalCatalog catalog;
  final LocalSources sources;
  final LocalDownloadQueue downloads;
}

String localSourceSeriesId(LocalExtension source, String mangaId) =>
    localSeriesIdFor(
      origin: source.catalogOrigin,
      sourceId: source.id,
      mangaId: mangaId,
    );

/// [localSourceSeriesId] from its parts, for series sync adds from a server.
String localSeriesIdFor({
  required Uri origin,
  required String sourceId,
  required String mangaId,
}) => base64Url
    .encode(utf8.encode(jsonEncode([origin.toString(), sourceId, mangaId])))
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
