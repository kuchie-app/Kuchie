import 'dart:io';

import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_providers.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_services.dart';
import 'package:kuchie/src/features/local_collection/data/local_download_queue.dart';
import 'package:kuchie/src/features/local_collection/data/local_sources.dart';
import 'package:mocktail/mocktail.dart';

/// Stub only what a test needs: `when(() => sources.method()).thenReturn(...)`.
class MockLocalSources extends Mock implements LocalSources {}

class MockLocalCatalog extends Mock implements LocalCatalog {}

/// A real catalog and queue in [directory], with injectable sources and HTTP.
LocalCollectionServices fakeLocalCollectionServices(
  Directory directory, {
  LocalSources? sources,
  http.Client Function()? clientFactory,
}) {
  final catalog = LocalCatalog(Directory('${directory.path}/catalog'));
  return LocalCollectionServices.custom(
    catalog: catalog,
    sources: sources ?? MockLocalSources(),
    downloads: LocalDownloadQueue(
      catalog,
      File('${directory.path}/downloads.json'),
      clientFactory: clientFactory,
    ),
  );
}

/// Provider overrides that point the Local collection at [services].
List<Override> localCollectionOverrides(LocalCollectionServices services) => [
  localCollectionServicesProvider.overrideWith((ref) async => services),
];
