import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_providers.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_services.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_collection_fakes.dart';

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-local-di');
  });

  tearDown(() async {
    await workspace.delete(recursive: true);
  });

  test('opens the Local collection only when first read', () async {
    final container = ProviderContainer(
      overrides: [
        localCollectionDirectoryProvider.overrideWith((ref) async => workspace),
      ],
    );
    addTearDown(container.dispose);

    // Live Activities can watch the queue without opening Local storage.
    expect(container.read(activeLocalDownloadQueueProvider), isNull);
    expect(Directory('${workspace.path}/catalog').existsSync(), isFalse);

    final services = await container.read(
      localCollectionServicesProvider.future,
    );
    expect(
      container.read(activeLocalDownloadQueueProvider),
      services.downloads,
    );
    expect(await services.catalog.list(), isEmpty);
    await services.catalog.close();
  });

  test('screens receive injected services and mocked sources', () async {
    final sources = MockLocalSources();
    const reference = LocalSeriesSource(
      sourceId: 'shinigami',
      mangaId: '42',
      locator: 'https://example.test/42',
    );
    when(
      () => sources.legacySeriesReference('shinigami', '42'),
    ).thenReturn(reference);
    final injected = fakeLocalCollectionServices(workspace, sources: sources);
    final container = ProviderContainer(
      overrides: localCollectionOverrides(injected),
    );
    addTearDown(container.dispose);

    final services = await container.read(
      localCollectionServicesProvider.future,
    );
    expect(services, same(injected));
    final id = base64Url
        .encode(
          utf8.encode(jsonEncode(['https://example.test', 'shinigami', '42'])),
        )
        .replaceAll('=', '');
    final resolved = localSeriesReference(
      services.sources,
      LocalSeries(id: id, title: 'Series', chapters: const []),
    );
    expect(resolved, same(reference));
    verify(() => sources.legacySeriesReference('shinigami', '42')).called(1);
    await services.catalog.close();
  });
}
