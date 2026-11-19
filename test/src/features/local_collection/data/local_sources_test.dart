import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_services.dart';
import 'package:kuchie/src/features/local_collection/data/local_mihon_runtime.dart';
import 'package:kuchie/src/features/local_collection/data/local_sources.dart';
import 'package:kuchie/src/features/local_collection/data/local_updates.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../../../helpers/signed_apk_fixture.dart';

const host = 'https://fixture.example';
final index = Uri.parse('$host/index.json');

String _hash(String content) => SHA256Digest()
    .process(Uint8List.fromList(utf8.encode(content)))
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

String _extension({
  String version = '1.0.0',
  String catalog = '/catalog.json',
}) => jsonEncode({
  'format': 'kuchie.extension.v1',
  'id': 'qa.sample',
  'name': 'QA Sample',
  'version': version,
  'language': 'id',
  'catalog': catalog,
});

String _index({
  String version = '1.0.0',
  String? digest,
  String package = 'extension.json',
  String? catalogOrigin,
}) => jsonEncode({
  'format': 'kuchie.repository.v1',
  'name': 'QA Sources',
  'extensions': [
    {
      'id': 'qa.sample',
      'name': 'QA Sample',
      'version': version,
      'language': 'id',
      'url': package,
      'sha256': digest ?? _hash(_extension(version: version)),
      'catalogOrigin': ?catalogOrigin,
    },
  ],
});

void main() {
  late Directory root;
  late Map<String, String> server;
  late LocalSources sources;
  late http.Client client;
  late List<http.BaseRequest> requests;
  late Map<String, int> responseStatuses;
  late bool online;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kuchie-sources-test-');
    server = {
      '/index.json': _index(),
      '/extension.json': _extension(),
      '/catalog.json': jsonEncode({
        'manga': [
          {
            'id': 'series-1',
            'title': 'Lantern Station',
            'description': 'Original QA pages',
            'cover': 'cover.png',
            'chapters': 'chapters.json',
          },
          {
            'id': 'series-2',
            'title': 'Night Ferry',
            'chapters': 'chapters.json',
          },
        ],
      }),
      '/chapters.json': jsonEncode({
        'chapters': [
          {'id': 'chapter-1', 'title': 'Chapter 1', 'pages': 'pages.json'},
        ],
      }),
      '/pages.json': jsonEncode({
        'pages': ['1.png', '2.png'],
      }),
    };
    requests = [];
    responseStatuses = {};
    online = true;
    client = MockClient((request) async {
      requests.add(request);
      if (!online) throw const SocketException('Offline');
      if (responseStatuses[request.url.path] case final status?) {
        return http.Response('Unavailable', status);
      }
      final response = server[request.url.path];
      return response == null
          ? http.Response('Not found', 404)
          : http.Response(response, 200);
    });
    sources = LocalSources(root, client: client);
  });

  tearDown(() async {
    client.close();
    await root.delete(recursive: true);
  });

  test('updates use saved locators and isolate a failed title', () async {
    final index = await sources.addRepository(Uri.parse('$host/index.json'));
    final source = await sources.install(index.packages.single);
    final manga = await sources.browse(source.id);
    final books = [
      for (final selection in manga)
        LocalSeries(
          id: localSourceSeriesId(source, selection.id),
          title: selection.title,
          chapters: const [],
          source: sources.seriesReference(selection),
        ),
    ];
    // The second title has a different feed, which is now unavailable.
    final broken = books[1];
    books[1] = LocalSeries(
      id: broken.id,
      title: broken.title,
      chapters: const [],
      source: LocalSeriesSource(
        sourceId: source.id,
        mangaId: manga[1].id,
        locator: '$host/broken.json',
      ),
    );
    server.remove('/catalog.json');
    requests.clear();

    final result = await loadLocalUpdates(sources, books);
    expect(result.items.single.manga.title, 'Lantern Station');
    expect(result.items.single.count, 1);
    expect(result.failed, 1);
    expect(
      requests.map((request) => request.url.path),
      isNot(contains('/catalog.json')),
    );
  });

  test(
    'updates count only chapters a source added since the last check',
    () async {
      final index = await sources.addRepository(Uri.parse('$host/index.json'));
      final source = await sources.install(index.packages.single);
      final manga = (await sources.browse(source.id)).first;
      final books = [
        LocalSeries(
          id: localSourceSeriesId(source, manga.id),
          title: manga.title,
          chapters: const [],
          source: sources.seriesReference(manga),
        ),
      ];
      final baseline = _MemoryBaseline();
      var read = <String>{};

      Future<List<LocalMangaUpdate>> check() async => (await loadLocalUpdates(
        sources,
        books,
        baseline: baseline,
        readChapters: (_) async => read,
      )).items;

      // The first check only learns the chapters the title already had.
      expect(await check(), isEmpty);
      expect(baseline.known[books.single.id], {'chapter-1'});

      server['/chapters.json'] = jsonEncode({
        'chapters': [
          {'id': 'chapter-2', 'title': 'Chapter 2', 'pages': 'pages.json'},
          {'id': 'chapter-1', 'title': 'Chapter 1', 'pages': 'pages.json'},
        ],
      });
      final updates = await check();
      expect(updates.single.count, 1);
      expect(updates.single.chapterIds, ['chapter-2', 'chapter-1']);

      // A chapter read online is no longer new.
      read = {'chapter-2'};
      expect(await check(), isEmpty);
    },
  );

  test(
    'installs a Keiyoushi APK, reopens its sources, and preserves page headers',
    () async {
      const package = 'eu.kanade.tachiyomi.extension.all.example';
      final index = Uri.parse(
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json',
      );
      final apkUrl = Uri.parse(
        'https://github.com/keiyoushi/extensions/releases/download/fixture/tachiyomi-all.example-v1.6.5.apk',
      );
      final assetUrl = Uri.parse(
        'https://release-assets.githubusercontent.com/example/fixture.apk?token=fixture',
      );
      final signer = ApkTestSigner(1);
      final apk = signedApk(signer);
      final responses = MockClient((request) async {
        if (request.url == index) {
          return http.Response(
            jsonEncode({
              'name': 'Keiyoushi',
              'signingKey': signer.fingerprint,
              'extensionList': {
                'extensions': [
                  {
                    'name': 'Example Package',
                    'packageName': package,
                    'extensionLib': '1.6',
                    'versionName': '1.6.5',
                    'resources': {'apkUrl': apkUrl.toString()},
                    'contentWarning': 'CONTENT_WARNING_NSFW',
                    'sources': [
                      {'id': '1234', 'name': 'Example', 'language': 'en'},
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }
        if (request.url == apkUrl) {
          return http.Response(
            '',
            302,
            headers: {'location': assetUrl.toString()},
          );
        }
        if (request.url == assetUrl) return http.Response.bytes(apk, 200);
        return http.Response('', 404);
      });
      addTearDown(responses.close);
      final runtime = _FixtureRuntime(package, apk);
      addTearDown(runtime.close);
      final catalog = LocalSources(root, client: responses, runtime: runtime);
      final repository = await catalog.addRepository(index);
      expect(repository.packages.single.isNsfw, isTrue);
      final installed = await catalog.install(repository.packages.single);
      expect(installed.packageId, package);
      expect(installed.packageName, 'Example Package');
      expect(installed.name, 'Example EN');

      final reopened = LocalSources(root, client: responses, runtime: runtime);
      final variants = await reopened.sources();
      expect(variants.map((item) => item.id), [
        '$package:1234',
        '$package:5678',
      ]);
      expect((await reopened.extensions()).single.packageId, package);
      final second = variants.last;
      expect(second.language, 'id');
      expect(second.isNsfw, isTrue);
      final manga = (await reopened.browsePage(
        second.id,
        query: 'kuchie',
        page: 2,
      )).items.single;
      expect(manga.title, 'Manga Lokal');
      final detail = await reopened.mangaDetails(second.id, manga);
      expect(detail.id, manga.id);
      expect(detail.title, 'Manga Lokal Lengkap');
      expect(detail.description, 'Synopsis from the extension');
      expect(detail.cover.toString(), '$host/cover.png');
      expect(detail.coverHeaders, {'Referer': '$host/'});
      final chapter = (await reopened.chapters(second.id, detail)).single;
      expect(chapter.runtimeLocator, '/chapter/1|mangayomi-memo|memo1');
      final pages = await reopened.chapterPages(second.id, chapter);
      expect(pages.single.url, Uri.parse('https://fixture.example/1.png'));
      expect(pages.single.headers, {'Referer': 'https://fixture.example/'});
      final refreshed = await reopened.refreshChapterPages(
        second.id,
        chapter.runtimeLocator!,
      );
      expect(refreshed.single.url, pages.single.url);
      expect(refreshed.single.headers, pages.single.headers);
      await reopened.setEnabled(second.id, false);
      await expectLater(reopened.browse(second.id), throwsStateError);
      await reopened.uninstall(package);
      expect(await reopened.extensions(), isEmpty);
      expect(
        await Directory('${root.path}/sources/mihon/$package').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'clean install can add, install, browse, and read chapter page URLs',
    () async {
      expect(await sources.repositories(), isEmpty);
      expect(await sources.extensions(), isEmpty);
      expect(requests, isEmpty);
      final repo = await sources.addRepository(index);
      expect(repo.name, 'QA Sources');
      expect(repo.packages.single.name, 'QA Sample');
      final installed = await sources.install(repo.packages.single);
      expect(installed.enabled, isTrue);
      final restored = LocalSources(root, client: client);
      expect((await restored.extensions()).single.id, 'qa.sample');
      expect((await restored.repositories()).single.url, index);
      final manga = (await restored.browse(
        'qa.sample',
        query: 'lantern',
      )).single;
      expect(manga.title, 'Lantern Station');
      expect(manga.cover, Uri.parse('$host/cover.png'));
      final chapters = await restored.chapters('qa.sample', manga);
      expect(chapters.single.title, 'Chapter 1');
      expect(await restored.pages('qa.sample', chapters.single), [
        Uri.parse('$host/1.png'),
        Uri.parse('$host/2.png'),
      ]);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  test(
    'update preserves enablement and bad downloads preserve the old package',
    () async {
      final repo = await sources.addRepository(index);
      await sources.install(repo.packages.single);
      await sources.setEnabled('qa.sample', false);
      await expectLater(sources.browse('qa.sample'), throwsStateError);
      server['/index.json'] = _index(version: '2.0.0');
      final next = await sources.refreshRepository(index);
      await expectLater(
        sources.install(next.packages.single),
        throwsFormatException,
      );
      expect((await sources.extensions()).single.version, '1.0.0');
      server['/extension.json'] = _extension(version: '2.0.0');
      final updated = await sources.install(next.packages.single);
      expect(updated.version, '2.0.0');
      expect(updated.enabled, isFalse);
      await sources.uninstall('qa.sample');
      expect(await sources.extensions(), isEmpty);
      expect(await sources.repositories(), hasLength(1));
    },
  );

  test(
    'imports a declarative package from Files and rejects unsupported files',
    () async {
      final file = File('${root.path}/fixture.json');
      await file.writeAsString(_extension(catalog: '$host/catalog.json'));
      expect((await sources.importFile(file)).id, 'qa.sample');
      expect(await sources.repositories(), isEmpty);
      final apk = File('${root.path}/fixture.apk');
      await apk.writeAsString(_extension(catalog: '$host/catalog.json'));
      await expectLater(sources.importFile(apk), throwsFormatException);
    },
  );

  test(
    'rejects uncontrolled origin changes and remote executable package formats',
    () async {
      server['/index.json'] = _index(
        package: 'https://elsewhere.example/extension.json',
      );
      await expectLater(sources.addRepository(index), throwsFormatException);
      server['/index.json'] = _index(package: 'extension.apk');
      await expectLater(sources.addRepository(index), throwsFormatException);
      await expectLater(
        sources.addRepository(Uri.parse('http://fixture.example/index.json')),
        throwsFormatException,
      );
      expect(await sources.repositories(), isEmpty);
    },
  );

  test('refuses tampered, unhashed and mislabelled packages as security '
      'failures', () async {
    Matcher security({bool insecureUrl = false}) => throwsA(
      isA<LocalSourceSecurityException>().having(
        (error) => error.insecureUrl,
        'insecureUrl',
        insecureUrl,
      ),
    );

    // Plain HTTP off loopback and URLs with credentials are refused up front.
    await expectLater(
      sources.addRepository(Uri.parse('http://fixture.example/index.json')),
      security(insecureUrl: true),
    );
    await expectLater(
      sources.addRepository(
        Uri.parse('https://user:pw@fixture.example/i.json'),
      ),
      security(insecureUrl: true),
    );

    // An index entry without a checksum is not trusted.
    final unhashed = jsonDecode(_index()) as Map<String, dynamic>;
    (unhashed['extensions'] as List).cast<Map<String, dynamic>>().single.remove(
      'sha256',
    );
    server['/index.json'] = jsonEncode(unhashed);
    await expectLater(sources.addRepository(index), security());

    // Bytes that differ from the published checksum are never installed.
    server['/index.json'] = _index();
    final repo = await sources.addRepository(index);
    server['/extension.json'] = _extension().replaceAll('QA Sample', 'Hijack');
    await expectLater(sources.install(repo.packages.single), security());

    // A package that matches its checksum but claims another version.
    server['/extension.json'] = _extension(version: '9.9.9');
    server['/index.json'] = _index(digest: _hash(server['/extension.json']!));
    final lying = await sources.refreshRepository(index);
    await expectLater(sources.install(lying.packages.single), security());

    expect(await sources.extensions(), isEmpty);
  });

  group('Mihon extension stores', () {
    const package = 'eu.kanade.tachiyomi.extension.all.example';
    final signer = ApkTestSigner(1);
    final stranger = ApkTestSigner(2);

    test('adds a protobuf v2 store from its repo.json and installs a signed '
        'APK', () async {
      final repoJson = Uri.parse(
        'https://raw.githubusercontent.com/acme/cursed/repo/repo.json',
      );
      final indexV2 = Uri.parse(
        'https://github.com/acme/cursed/raw/repo/index.pb',
      );
      final rawIndex = Uri.parse(
        'https://raw.githubusercontent.com/acme/cursed/repo/index.pb',
      );
      final apkUrl = Uri.parse(
        'https://github.com/acme/cursed/releases/download/v1/example.apk',
      );
      final apk = signedApk(signer);
      final store = gzip.encode(
        _storeProto(
          name: 'Cursed QA',
          signingKey: signer.fingerprint.toUpperCase(),
          extensions: [
            (id: package, name: 'Example', version: '1.6.1', apk: '$apkUrl'),
            (
              id: 'eu.kanade.tachiyomi.extension.all.plain',
              name: 'Plain HTTP',
              version: '1.6.1',
              apk: 'http://cdn.example/plain.apk',
            ),
          ],
        ),
      );
      final client = MockClient((request) async {
        if (request.url == repoJson) {
          return http.Response(
            jsonEncode({
              'index_v2': '$indexV2',
              'meta': {
                'name': 'Cursed QA',
                'website': 'https://store.example',
                'signingKeyFingerprint': signer.fingerprint,
              },
            }),
            200,
          );
        }
        if (request.url == indexV2) {
          return http.Response('', 302, headers: {'location': '$rawIndex'});
        }
        if (request.url == rawIndex) return http.Response.bytes(store, 200);
        if (request.url == apkUrl) return http.Response.bytes(apk, 200);
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final runtime = _FixtureRuntime(package, apk);
      addTearDown(runtime.close);
      final catalog = LocalSources(root, client: client, runtime: runtime);

      final repo = await catalog.addRepository(repoJson);
      expect(repo.url, indexV2);
      expect(repo.name, 'Cursed QA');
      expect(repo.signingKey, signer.fingerprint);
      expect(repo.packages.map((item) => item.id), [package]);
      expect(repo.packages.single.isNsfw, isTrue);
      expect(repo.packages.single.language, 'en');

      final installed = await catalog.install(repo.packages.single);
      expect(installed.packageId, package);
      expect((await catalog.refreshRepository(repo.url)).url, indexV2);
    });

    test('reads a legacy index.min.json store and refuses APKs signed by '
        'anyone else', () async {
      final index = Uri.parse('https://legacy.example/repo/index.min.json');
      var key = signer.fingerprint;
      var apk = signedApk(stranger);
      final client = MockClient((request) async {
        switch (request.url.toString()) {
          case 'https://legacy.example/repo/index.min.json':
            return http.Response(
              jsonEncode([
                {
                  'name': 'Tachiyomi: Example',
                  'pkg': package,
                  'apk': 'tachiyomi-all.example-v1.4.2.apk',
                  'lang': 'all',
                  'code': 2,
                  'version': '1.4.2',
                  'nsfw': 0,
                },
                {'name': 'Broken', 'pkg': '../escape', 'apk': 'x.apk'},
                // Mihon loads neither anime extensions nor other libs.
                for (final (pkg, version) in [
                  ('eu.kanade.tachiyomi.animeextension.all.anime', '1.4.2'),
                  ('eu.kanade.tachiyomi.extension.all.old', '1.2.5'),
                ])
                  {
                    'name': 'Skipped',
                    'pkg': pkg,
                    'apk': 'skipped.apk',
                    'lang': 'all',
                    'code': 1,
                    'version': version,
                    'nsfw': 0,
                  },
              ]),
              200,
            );
          case 'https://legacy.example/repo/repo.json':
            return http.Response(
              jsonEncode({
                'meta': {
                  'name': 'Legacy QA',
                  'website': 'https://legacy.example',
                  'signingKeyFingerprint': key,
                },
              }),
              200,
            );
          case 'https://legacy.example/repo/apk/tachiyomi-all.example-v1.4.2.apk':
            return http.Response.bytes(apk, 200);
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final runtime = _FixtureRuntime(package, signedApk(signer));
      addTearDown(runtime.close);
      final catalog = LocalSources(root, client: client, runtime: runtime);

      final link = Uri(
        scheme: 'tachiyomi',
        host: 'add-repo',
        queryParameters: {'url': '$index'},
      );
      final repo = await catalog.addRepository(link);
      expect(repo.url, index);
      final example = repo.packages.single;
      expect(example.name, 'Example');
      expect(
        example.url,
        Uri.parse(
          'https://legacy.example/repo/apk/tachiyomi-all.example-v1.4.2.apk',
        ),
      );
      expect(
        example.icon,
        Uri.parse('https://legacy.example/repo/icon/$package.png'),
      );

      await expectLater(
        catalog.install(example),
        throwsA(isA<LocalSourceSecurityException>()),
      );
      expect(await catalog.extensions(), isEmpty);

      apk = signedApk(signer);
      expect((await catalog.install(example)).packageId, package);

      // A store that starts signing with another key is not an update.
      key = stranger.fingerprint;
      await expectLater(
        catalog.refreshRepository(index),
        throwsA(isA<LocalSourceSecurityException>()),
      );
      expect(
        (await catalog.repositories()).single.signingKey,
        signer.fingerprint,
      );
    });

    test('keeps source settings, sends them on every call and forgets them '
        'on uninstall', () async {
      final index = Uri.parse('https://legacy.example/repo/index.min.json');
      final apk = signedApk(signer);
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/repo/index.min.json':
            return http.Response(
              jsonEncode([
                {
                  'name': 'Tachiyomi: Example',
                  'pkg': package,
                  'apk': 'example.apk',
                  'lang': 'all',
                  'code': 1,
                  'version': '1.4.1',
                  'nsfw': 0,
                },
              ]),
              200,
            );
          case '/repo/repo.json':
            return http.Response(
              jsonEncode({
                'meta': {
                  'name': 'Legacy QA',
                  'website': 'https://legacy.example',
                  'signingKeyFingerprint': signer.fingerprint,
                },
              }),
              200,
            );
          case '/repo/apk/example.apk':
            return http.Response.bytes(apk, 200);
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final runtime = _SettingsRuntime(package, apk);
      addTearDown(runtime.close);
      final catalog = LocalSources(root, client: client, runtime: runtime);
      final repo = await catalog.addRepository(index);
      await catalog.install(repo.packages.single);
      final source = (await catalog.sources()).first;
      expect(source.canHaveSettings, isTrue);

      final settings = await catalog.sourcePreferences(source.id);
      expect(settings.single.selectedIndex, 0);
      final changed = await catalog.setSourcePreference(
        source.id,
        settings.single.withSelectedIndex(1),
      );
      expect(changed.single.selectedIndex, 1);

      // A new LocalSources (the next app launch) still sends the setting.
      final reopened = LocalSources(root, client: client, runtime: runtime);
      await reopened.browsePage(source.id);
      expect(runtime.seen.single.single, changed.single.toJson());

      await reopened.uninstall(package);
      await reopened.install(repo.packages.single);
      await reopened.browsePage(source.id);
      expect(runtime.seen.last, isEmpty);
    });

    test('refuses a retired store whose only entries are notices', () async {
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/repo/index.min.json':
            return http.Response(
              jsonEncode([
                {
                  'name': 'Outdated App',
                  'pkg': 'eu.kanade.tachiyomi.extension.all.keiyoushi',
                  'apk': 'tachiyomi-all.keiyoushi-v1.4.1.apk',
                  'lang': 'all',
                  'code': 1,
                  'version': '1.4.1',
                  'nsfw': 0,
                  'sources': [
                    {
                      'name': 'Outdated App',
                      'lang': 'all',
                      'id': '1',
                      'baseUrl': 'https://keiyoushi.github.io',
                    },
                  ],
                },
              ]),
              200,
            );
          case '/repo/repo.json':
            return http.Response(
              jsonEncode({
                'meta': {
                  'name': 'Retired QA',
                  'signingKeyFingerprint': signer.fingerprint,
                },
              }),
              200,
            );
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final catalog = LocalSources(root, client: client);
      await expectLater(
        catalog.addRepository(
          Uri.parse('https://retired.example/repo/index.min.json'),
        ),
        throwsA(
          isA<LocalSourceRetiredStoreException>()
              .having((error) => error.storeName, 'storeName', 'Retired QA')
              .having((error) => error.movedToKeiyoushi, 'Keiyoushi', isTrue),
        ),
      );
      expect(await catalog.repositories(), isEmpty);
    });

    test('follows the add-store link on a store web page and drops notice '
        'entries beside real extensions', () async {
      final client = MockClient((request) async {
        switch (request.url.toString()) {
          case 'https://stores.example/extensions/':
            return http.Response(
              '<!doctype html><a href="mihon://extension-store?url='
              'https%3A%2F%2Fstores.example%2Frepo%2Findex.min.json">Add</a>',
              200,
            );
          case 'https://stores.example/repo/index.min.json':
            return http.Response(
              jsonEncode([
                {
                  'name': 'Update to Mihon 0.20.1+',
                  'pkg': 'eu.kanade.tachiyomi.extension.all.mihon',
                  'apk': 'tachiyomi-all.mihon-v1.4.1.apk',
                  'lang': 'all',
                  'code': 1,
                  'version': '1.4.1',
                  'nsfw': 0,
                  'sources': [
                    {'id': '1', 'baseUrl': 'https://mihon.app'},
                  ],
                },
                {
                  'name': 'Tachiyomi: Example',
                  'pkg': package,
                  'apk': 'example.apk',
                  'lang': 'en',
                  'code': 1,
                  'version': '1.4.1',
                  'nsfw': 0,
                  'sources': [
                    {'id': '7', 'baseUrl': 'https://example.com'},
                  ],
                },
              ]),
              200,
            );
          case 'https://stores.example/repo/repo.json':
            return http.Response(
              jsonEncode({
                'meta': {
                  'name': 'Page QA',
                  'signingKeyFingerprint': signer.fingerprint,
                },
              }),
              200,
            );
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final catalog = LocalSources(root, client: client);
      final repo = await catalog.addRepository(
        Uri.parse('https://stores.example/extensions/'),
      );
      expect(repo.name, 'Page QA');
      expect(repo.url, Uri.parse('https://stores.example/repo/index.min.json'));
      expect(repo.packages.map((package) => package.name), ['Example']);
    });

    test('adds a store whose key is not a SHA-256 and installs its APKs only '
        'once the reader trusts the signer', () async {
      final index = Uri.parse('https://nokey.example/repo/index.min.json');
      final apk = signedApk(stranger);
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/repo/index.min.json':
            return http.Response(
              jsonEncode([
                {
                  'name': 'Tachiyomi: Example',
                  'pkg': package,
                  'apk': 'example.apk',
                  'lang': 'en',
                  'code': 1,
                  'version': '1.4.1',
                  'nsfw': 0,
                },
              ]),
              200,
            );
          case '/repo/repo.json':
            // A SHA-1 with colons, as some stores publish.
            return http.Response(
              jsonEncode({
                'meta': {
                  'name': 'No key',
                  'website': 'https://nokey.example',
                  'signingKeyFingerprint': 'CE:B1:D6:DE:86:CA:8C:9E:40:27',
                },
              }),
              200,
            );
          case '/repo/apk/example.apk':
            return http.Response.bytes(apk, 200);
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final runtime = _FixtureRuntime(package, apk);
      addTearDown(runtime.close);
      final catalog = LocalSources(root, client: client, runtime: runtime);
      final repo = await catalog.addRepository(index);
      final example = repo.packages.single;

      final untrusted = await catalog
          .install(example)
          .then<LocalSourceUntrustedException?>((_) => null)
          .catchError((Object error) => error as LocalSourceUntrustedException);
      expect(untrusted?.signer, stranger.fingerprint);
      expect(await catalog.extensions(), isEmpty);

      // Trusting a different signer does not help.
      await expectLater(
        catalog.install(example, trustSigner: signer.fingerprint),
        throwsA(isA<LocalSourceUntrustedException>()),
      );
      await catalog.install(example, trustSigner: stranger.fingerprint);
      expect((await catalog.extensions()).single.packageId, package);

      // The trust is remembered for this version.
      await catalog.uninstall(package);
      expect((await catalog.install(example)).packageId, package);
    });
  });

  test('disallows cross-origin catalog and chapter links', () async {
    server['/extension.json'] = _extension(
      catalog: 'https://elsewhere.example/catalog.json',
    );
    server['/index.json'] = _index(digest: _hash(server['/extension.json']!));
    final repo = await sources.addRepository(index);
    await expectLater(
      sources.install(repo.packages.single),
      throwsFormatException,
    );
    server['/extension.json'] = _extension();
    server['/index.json'] = _index();
    await sources.install(
      (await sources.refreshRepository(index)).packages.single,
    );
    server['/catalog.json'] = jsonEncode({
      'manga': [
        {
          'id': 'series-1',
          'title': 'Bad',
          'chapters': 'https://elsewhere.example/chapters.json',
        },
      ],
    });
    await expectLater(sources.browse('qa.sample'), throwsFormatException);
    expect(
      requests.any((request) => request.url.host == 'elsewhere.example'),
      isFalse,
    );
  });

  test(
    'explicit catalog origins allow repositories to serve independent sources',
    () async {
      const catalogOrigin = 'https://source.example';
      server['/extension.json'] = _extension(
        catalog: '$catalogOrigin/catalog.json',
      );
      server['/index.json'] = _index(
        digest: _hash(server['/extension.json']!),
        catalogOrigin: catalogOrigin,
      );
      final repo = await sources.addRepository(index);
      expect(repo.packages.single.catalogOrigin, Uri.parse(catalogOrigin));
      final extension = await sources.install(repo.packages.single);
      expect(extension.catalogOrigin, Uri.parse(catalogOrigin));
      final manga = (await sources.browse(
        'qa.sample',
        query: 'lantern',
      )).single;
      expect(manga.cover?.origin, catalogOrigin);
      expect(requests.last.url.origin, catalogOrigin);
    },
  );

  test(
    'airplane mode keeps the last valid catalog after an invalid refresh',
    () async {
      final repo = await sources.addRepository(index);
      await sources.install(repo.packages.single);
      expect(await sources.browse('qa.sample'), hasLength(2));
      server['/catalog.json'] = jsonEncode({
        'manga': ['invalid row'],
      });
      await expectLater(sources.browse('qa.sample'), throwsFormatException);
      online = false;
      final restored = LocalSources(root, client: client);
      expect(await restored.repositories(), hasLength(1));
      expect(
        (await restored.browse('qa.sample', query: 'lantern')).single.title,
        'Lantern Station',
      );
    },
  );

  test(
    'upgrades the previously saved Keiyoushi store and lists runtime packages',
    () async {
      const canonical =
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json';
      final path = File('${root.path}/sources/sources.json');
      await path.parent.create(recursive: true);
      await path.writeAsString(
        jsonEncode({
          'repositories': {
            canonical: {
              'format': 'kuchie.keiyoushi.v1',
              'shinigami': {'version': '1.6.85'},
            },
          },
          'extensions': {},
        }),
      );
      const package = 'eu.kanade.tachiyomi.extension.en.example';
      const validApk =
          'https://github.com/keiyoushi/extensions/releases/download/example/tachiyomi-en.example-v1.6.5.apk';
      Map<String, Object> entry(String packageName, String apk) => {
        'name': 'Example',
        'packageName': packageName,
        'extensionLib': '1.6',
        'versionName': '1.6.5',
        'contentWarning': 'CONTENT_WARNING_NSFW',
        'resources': {'apkUrl': apk},
        'sources': [
          {'id': '12345', 'name': 'Example', 'language': 'en'},
        ],
      };
      server['/keiyoushi/extensions/repo/index.json'] = jsonEncode({
        'name': 'Keiyoushi',
        'signingKey': ApkTestSigner(1).fingerprint,
        'extensionList': {
          'extensions': [
            entry(package, validApk),
            // APKs may live on any host, but never behind plain HTTP.
            entry(
              'eu.kanade.tachiyomi.extension.en.invalid',
              'http://other.example/example.apk',
            ),
          ],
        },
      });

      online = false;
      expect(
        (await sources.repositories()).single.packages.single.name,
        'Shinigami',
      );

      online = true;
      final connected = LocalSources(root, client: client);
      final repo = (await connected.repositories()).single;
      expect(repo.packages.map((item) => item.id), [package]);
      expect(repo.packages.single.url, Uri.parse(validApk));
      expect(await connected.extensions(), isEmpty);
      online = false;
      expect(
        (await LocalSources(
          root,
          client: client,
        ).repositories()).single.packages.single.id,
        package,
      );
    },
  );

  test(
    'installs Shinigami from an official store alias and reads local pages',
    () async {
      const extensionId = 'eu.kanade.tachiyomi.extension.id.shinigami';
      const canonical =
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json';
      final storeLink = Uri(
        scheme: 'mihon',
        host: 'extension-store',
        queryParameters: {
          'url': 'https://github.com/keiyoushi/extensions/raw/repo/index.pb',
        },
      );
      server['/keiyoushi/extensions/repo/index.json'] = jsonEncode({
        'name': 'Keiyoushi',
        'signingKey': ApkTestSigner(1).fingerprint,
        'extensionList': {
          'extensions': [
            {
              'packageName': extensionId,
              'extensionLib': '1.6',
              'versionName': '1.6.85',
              'sources': [
                {'id': '3411809758861089969'},
              ],
            },
            {
              'packageName': 'eu.kanade.tachiyomi.extension.en.example',
              'extensionLib': '1.6',
            },
          ],
        },
      });
      server['/v1/manga/list'] = jsonEncode({
        'retcode': 0,
        'meta': {'page': 1, 'total_page': 2},
        'data': [
          {
            'manga_id': 'villain',
            'title': 'The Villain Wants to Live',
            'description': 'QA synopsis',
            'cover_portrait_url': 'https://assets.shngm.id/thumbnail/cover.jpg',
          },
        ],
      });
      server['/v1/chapter/villain/list'] = jsonEncode({
        'retcode': 0,
        'data': [
          {
            'chapter_id': 'chapter-1',
            'chapter_number': 1.0,
            'chapter_title': '',
            'release_date': '2026-11-13T14:44:05Z',
          },
        ],
      });
      server['/v1/chapter/detail/chapter-1'] = jsonEncode({
        'retcode': 0,
        'data': {
          'base_url': 'https://assets.shngm.id',
          'chapter': {
            'path': '/chapter/villain/one/',
            'data': ['1.jpg', '2.jpg'],
          },
        },
      });

      final repo = await sources.addRepository(storeLink);
      expect(repo.url.toString(), canonical);
      expect(repo.hasNativeAdapters, isTrue);
      expect(repo.packages.single.id, extensionId);
      expect(await sources.extensions(), isEmpty);
      expect(requests.single.url, repo.url);
      await sources.install(repo.packages.single);
      expect(
        requests,
        hasLength(1),
        reason: 'Installing must not fetch the APK',
      );

      final reopened = LocalSources(root, client: client);
      final source = (await reopened.extensions()).single;
      expect(source.supportsLatest, isTrue);
      expect(source.chaptersNewestFirst, isTrue);
      expect(source.enabled, isTrue);
      expect(source.homepage.toString(), 'https://11.shinigami.asia');
      expect(source.icon, isNotNull);
      expect(
        (await reopened.repositories()).single.packages.single.id,
        extensionId,
      );

      final cacheStates = <bool>[];
      final first = await reopened.browsePage(
        source.id,
        latest: true,
        onFreshness: cacheStates.add,
      );
      expect(first.hasMore, isTrue);
      expect(requests.last.url.queryParameters['sort'], 'latest');
      expect(
        first.items.single.cover.toString(),
        'https://assets.shngm.id/thumbnail/cover.jpg',
      );
      responseStatuses['/v1/manga/list'] = 403;
      final cached = await reopened.browsePage(
        source.id,
        latest: true,
        onFreshness: cacheStates.add,
      );
      expect(cached.items.single.id, first.items.single.id);
      expect(cacheStates, [false, true]);
      await expectLater(
        reopened.browsePage(source.id, latest: true, page: 3),
        throwsA(
          isA<HttpException>().having((e) => e.message, 'status', 'HTTP 403'),
        ),
      );
      responseStatuses['/v1/manga/list'] = 404;
      await expectLater(
        reopened.browsePage(source.id, latest: true),
        throwsA(isA<HttpException>()),
      );
      responseStatuses.remove('/v1/manga/list');
      server['/v1/manga/list'] = jsonEncode({
        'retcode': 0,
        'meta': {'page': 2, 'total_page': 2},
        'data': [
          {
            'manga_id': 'villain',
            'title': 'The Villain Wants to Live',
            'cover_portrait_url': '',
            'cover_image_url': 'https://assets.shngm.id/thumbnail/banner.jpg',
            'description': 'QA synopsis',
          },
          {
            'manga_id': 'other-villain',
            'title': 'Another villain',
            'cover_portrait_url':
                'https://assets.shngm.id/thumbnail/poster.jpg',
            'cover_image_url': 'https://assets.shngm.id/thumbnail/other.jpg',
          },
          {
            'manga_id': 'bad-cover',
            'title': 'Untrusted cover',
            'cover_portrait_url': 'https://untrusted.example/poster.jpg',
            'cover_image_url': 'https://assets.shngm.id/thumbnail/safe.jpg',
          },
        ],
      });
      final search = await reopened.browsePage(
        source.id,
        query: 'The Villain',
        page: 2,
      );
      expect(requests.last.url.queryParameters['q'], 'The Villain');
      expect(requests.last.url.queryParameters['page'], '2');
      final manga = search.items.first;
      expect(manga.title, 'The Villain Wants to Live');
      expect(manga.description, 'QA synopsis');
      expect(
        manga.cover.toString(),
        'https://assets.shngm.id/thumbnail/banner.jpg',
      );
      expect(manga.coverFallback, isNull);
      expect(
        search.items[1].cover.toString(),
        'https://assets.shngm.id/thumbnail/poster.jpg',
      );
      expect(
        search.items[1].coverFallback.toString(),
        'https://assets.shngm.id/thumbnail/other.jpg',
      );
      expect(
        search.items[2].cover.toString(),
        'https://assets.shngm.id/thumbnail/safe.jpg',
      );
      server['/v1/manga/detail/villain'] = jsonEncode({
        'retcode': 0,
        'data': {
          'title': 'The Villain Wants to Live',
          'status': 3,
          'description': 'More about this title',
          'alternative_title': 'Alternate title',
          'taxonomy': {
            'Author': [
              {'name': 'Writer'},
            ],
            'Artist': [
              {'name': 'Artist'},
            ],
            'Genre': [
              {'name': 'Action'},
            ],
            'Format': [
              {'name': 'Manhwa'},
            ],
          },
        },
      });
      final details = await reopened.mangaDetails(source.id, manga);
      expect(details.author, 'Writer');
      expect(details.artist, 'Artist');
      expect(details.status, 6);
      expect(details.genres, ['Action', 'Manhwa']);
      expect(details.cover, manga.cover);
      expect(details.description, 'More about this title');
      expect(details.alternativeTitle, 'Alternate title');
      expect(
        details.webUrl.toString(),
        'https://11.shinigami.asia/series/villain',
      );
      final chapter = (await reopened.chapters(source.id, manga)).single;
      expect(chapter.title, 'Chapter 1');
      expect(chapter.number, 1.0);
      expect(chapter.uploadDate, DateTime.utc(2026, 11, 13, 14, 44, 5));
      expect(await reopened.pages(source.id, chapter), [
        Uri.parse('https://assets.shngm.id/chapter/villain/one/1.jpg'),
        Uri.parse('https://assets.shngm.id/chapter/villain/one/2.jpg'),
      ]);
      responseStatuses['/v1/chapter/detail/chapter-1'] = 503;
      expect(await reopened.pages(source.id, chapter), hasLength(2));
      responseStatuses.remove('/v1/chapter/detail/chapter-1');

      server['/v1/chapter/detail/chapter-1'] =
          server['/v1/chapter/detail/chapter-1']!.replaceFirst(
            'assets.shngm.id',
            'untrusted.example',
          );
      await expectLater(
        reopened.pages(source.id, chapter),
        throwsFormatException,
      );
      await reopened.setEnabled(source.id, false);
      await expectLater(reopened.browse(source.id), throwsStateError);
      final refreshed = await reopened.refreshRepository(
        Uri.parse(
          'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
        ),
      );
      expect(refreshed.url, repo.url);
      expect(await reopened.repositories(), hasLength(1));
      await reopened.removeRepository(storeLink);
      expect(await reopened.repositories(), isEmpty);
      expect((await reopened.extensions()).single.id, source.id);
    },
  );
}

/// Encodes a Mihon v2 `NetworkExtensionStore` the way protobuf does.
Uint8List _storeProto({
  required String name,
  required String signingKey,
  required List<({String id, String name, String version, String apk})>
  extensions,
}) {
  List<int> varint(int value) {
    final out = <int>[];
    while (value >= 0x80) {
      out.add((value & 0x7f) | 0x80);
      value >>= 7;
    }
    return out..add(value);
  }

  List<int> bytes(int field, List<int> value) => [
    ...varint(field << 3 | 2),
    ...varint(value.length),
    ...value,
  ];
  List<int> text(int field, String value) => bytes(field, utf8.encode(value));
  List<int> number(int field, int value) => [
    ...varint(field << 3),
    ...varint(value),
  ];

  return Uint8List.fromList([
    ...text(1, name),
    ...text(2, name),
    ...text(3, signingKey),
    ...bytes(4, text(1, 'https://store.example')),
    ...bytes(101, [
      for (final extension in extensions)
        ...bytes(1, [
          ...text(1, extension.name),
          ...text(2, extension.id),
          ...bytes(3, [
            ...text(1, extension.apk),
            ...text(2, 'https://cdn.example/icon.png'),
          ]),
          ...text(4, '1.6'),
          ...number(5, 106001),
          ...text(6, extension.version),
          ...number(7, 3),
          ...bytes(8, [
            ...number(1, 1234),
            ...text(2, 'Cursed'),
            ...text(3, 'en'),
          ]),
        ]),
    ]),
  ]);
}

/// Records the settings each runtime call receives.
class _SettingsRuntime extends _FixtureRuntime {
  _SettingsRuntime(super.package, super.expectedApk);

  final seen = <List<Map<String, Object?>>>[];
  var current = [
    MihonPreference.tryParse({
      'key': 'mirror',
      'listPreference': {
        'title': 'Mirror',
        'valueIndex': 0,
        'entries': ['Main', 'Backup'],
        'entryValues': ['main', 'backup'],
      },
    })!,
  ];

  @override
  Future<List<MihonPreference>> preferences(
    Uint8List apk,
    MihonRuntimeSource source,
  ) async => current;

  @override
  Future<List<MihonPreference>> setPreference(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonPreference changed,
  ) async => current = [changed];

  @override
  Future<({List<MihonRuntimeManga> items, bool hasMore})> browse(
    Uint8List apk,
    MihonRuntimeSource source, {
    required String query,
    required bool latest,
    required int page,
    List<Map<String, Object?>> filterList = const [],
  }) async {
    seen.add([for (final item in source.preferences) item.toJson()]);
    return (items: const <MihonRuntimeManga>[], hasMore: false);
  }
}

class _FixtureRuntime extends MihonRuntimeClient {
  _FixtureRuntime(this.package, this.expectedApk);

  final String package;
  final Uint8List expectedApk;

  @override
  Future<List<MihonRuntimeSource>> inspect(
    Uint8List apk, {
    required String packageName,
  }) async {
    expect(apk, expectedApk);
    expect(packageName, package);
    return const [
      MihonRuntimeSource(id: '1234', name: 'Example EN', language: 'en'),
      MihonRuntimeSource(id: '5678', name: 'Example ID', language: 'id'),
    ];
  }

  @override
  Future<({List<MihonRuntimeManga> items, bool hasMore})> browse(
    Uint8List apk,
    MihonRuntimeSource source, {
    required String query,
    required bool latest,
    required int page,
    List<Map<String, Object?>> filterList = const [],
  }) async {
    expect(apk, expectedApk);
    expect(source.id, '5678');
    expect(query, 'kuchie');
    expect(page, 2);
    return (
      items: const [
        MihonRuntimeManga(locator: '/manga/1', title: 'Manga Lokal'),
      ],
      hasMore: false,
    );
  }

  @override
  Future<MihonRuntimeManga> details(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonRuntimeManga manga,
  ) async {
    expect(apk, expectedApk);
    expect(source.id, '5678');
    expect(manga.locator, '/manga/1');
    return MihonRuntimeManga(
      locator: '/manga/alternate',
      title: 'Manga Lokal Lengkap',
      description: 'Synopsis from the extension',
      cover: Uri.parse('$host/cover.png'),
      coverHeaders: const {'Referer': '$host/'},
    );
  }

  @override
  Future<List<MihonRuntimeChapter>> chapters(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonRuntimeManga manga,
  ) async {
    expect(apk, expectedApk);
    expect(source.id, '5678');
    expect(manga.locator, '/manga/1');
    return const [
      MihonRuntimeChapter(
        locator: '/chapter/1|mangayomi-memo|memo1',
        title: '1',
      ),
    ];
  }

  @override
  Future<List<MihonRuntimePage>> pages(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonRuntimeChapter chapter,
  ) async {
    expect(apk, expectedApk);
    expect(source.id, '5678');
    expect(chapter.locator, '/chapter/1|mangayomi-memo|memo1');
    return [
      MihonRuntimePage(
        url: Uri.parse('https://fixture.example/1.png'),
        headers: const {'Referer': 'https://fixture.example/'},
      ),
    ];
  }
}

class _MemoryBaseline implements LocalUpdateBaseline {
  final known = <String, Set<String>>{};

  @override
  Future<Set<String>?> read(String seriesId) async => known[seriesId];

  @override
  Future<void> write(String seriesId, Iterable<String> chapterIds) async =>
      known[seriesId] = chapterIds.toSet();
}
