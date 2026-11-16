import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuchie/src/features/local_collection/data/local_mihon_runtime.dart';

final _endpoint = Uri.parse('http://127.0.0.1:34879');
const _capabilities = '{"extensionInfo":true,"extensionHandles":true}';
const _source = MihonRuntimeSource(
  id: '9223372036854775807',
  name: 'Example',
  language: 'en',
);
const _manga = MihonRuntimeManga(
  locator: '/work|mangayomi-memo|eyJrIjoxfQ',
  title: 'Example comic',
);
const _chapter = MihonRuntimeChapter(
  locator: '|mangayomi-memo|eyJjIjoxfQ',
  title: 'Chapter 1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads an APK on the first cache miss and keeps its opaque source identifier',
    () async {
      final apk = Uint8List.fromList([1, 3, 7, 9]);
      var inspected = false;
      String? key;
      final client = MockClient((request) async {
        if (request.url.path == '/capabilities') {
          expect(request.method, 'GET');
          return http.Response(_capabilities, 200);
        }
        expect(request.url.path, '/dalvik');
        expect(request.method, 'POST');
        expect(request.followRedirects, false);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'extensionInfo') {
          if (body['extensionId'] case final String id) {
            key = id;
            expect(key, matches(r'^[0-9a-f]{64}$'));
            return http.Response(
              '{"error":"Extension not loaded","code":409}',
              409,
            );
          }
          expect(body['data'], base64Encode(apk));
          inspected = true;
          return http.Response(
            jsonEncode({
              'packageName': 'example.manga',
              'itemType': 'manga',
              'sources': [
                {
                  'id': _source.id,
                  'name': _source.name,
                  'lang': _source.language,
                  'baseUrl': 'https://manga.example.com',
                },
              ],
            }),
            200,
          );
        }
        expect(inspected, true);
        expect(body['extensionId'], key);
        expect(body.containsKey('data'), false);
        expect(body['sourceId'], _source.id);
        expect(body['method'], 'getSearchManga');
        expect(body['search'], 'example');
        expect(body['page'], 2);
        return http.Response(
          jsonEncode({
            'hasNextPage': true,
            'mangas': [
              {'url': _manga.locator, 'title': _manga.title},
            ],
          }),
          200,
        );
      });
      final runtime = MihonRuntimeClient(
        client: client,
        resolveEndpoint: () async => _endpoint,
      );
      final sources = await runtime.inspect(apk, packageName: 'example.manga');
      expect(sources.single.id, _source.id);
      expect(sources.single.homepage.toString(), 'https://manga.example.com');
      final search = await runtime.browse(
        apk,
        sources.single,
        query: 'example',
        latest: false,
        page: 2,
      );
      expect(search.hasMore, true);
      expect(search.items.single.locator, _manga.locator);
      expect(search.items.single.stableLocator, '/work');
    },
  );

  test(
    'passes memo-only locators unchanged and keeps only safe page headers',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/capabilities') {
          return http.Response(_capabilities, 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'getDetailsManga') {
          expect(body['mangaData']['url'], _manga.locator);
          return http.Response(
            jsonEncode({
              'url': _manga.locator,
              'title': _manga.title,
              'thumbnail_url': '$_endpoint/image/poster',
              'author': 'Example author',
              'artist': 'Example artist',
              'genre': 'Action, Manhwa',
              'status': 6,
            }),
            200,
          );
        }
        if (body['method'] == 'getChapterList') {
          expect(body['mangaData']['url'], _manga.locator);
          return http.Response(
            jsonEncode([
              {
                'url': _chapter.locator,
                'name': _chapter.title,
                'chapter_number': 1.5,
                'date_upload': 1794581045000,
              },
            ]),
            200,
          );
        }
        expect(body['method'], 'getPageList');
        expect(body['chapterData']['url'], _chapter.locator);
        return http.Response(
          jsonEncode([
            {
              'imageUrl': 'https://media.example.com/page.jpg',
              'headers': {
                'Referer': 'https://manga.example.com/',
                'Host': 'different.example.com',
                'X-Kuchie-Runtime-Token': 'attempted-bridge-header',
                'X-Injected': 'value\r\nBad: value',
              },
            },
            {
              'imageUrl': '$_endpoint/image/next-page',
              'headers': {'Referer': 'https://manga.example.com/'},
            },
          ]),
          200,
        );
      });
      final runtime = MihonRuntimeClient(
        client: client,
        resolveEndpoint: () async => _endpoint,
      );
      final apk = Uint8List.fromList([1, 3, 7, 9]);
      final manga = await runtime.details(apk, _source, _manga);
      expect(manga.cover.toString(), '$_endpoint/image/poster');
      expect(manga.author, 'Example author');
      expect(manga.artist, 'Example artist');
      expect(manga.genres, ['Action', 'Manhwa']);
      expect(manga.status, 6);
      final chapters = await runtime.chapters(apk, _source, manga);
      expect(chapters.single.stableLocator, _chapter.locator);
      expect(chapters.single.number, 1.5);
      expect(chapters.single.uploadDate?.millisecondsSinceEpoch, 1794581045000);
      final pages = await runtime.pages(apk, _source, chapters.single);
      expect(pages.first.url.toString(), 'https://media.example.com/page.jpg');
      expect(pages.first.headers, {'Referer': 'https://manga.example.com/'});
      expect(pages.last.url.toString(), '$_endpoint/image/next-page');
      expect(pages.last.headers, isEmpty);
    },
  );

  test(
    'rejects runtime endpoints off loopback before sending APK data',
    () async {
      final client = MockClient((request) async {
        fail('No request expected: ${request.url}');
      });
      final runtime = MihonRuntimeClient(
        client: client,
        resolveEndpoint: () async =>
            Uri.parse('http://server.example.com:34879'),
      );
      await expectLater(
        runtime.inspect(Uint8List.fromList([1]), packageName: 'example.manga'),
        throwsA(isA<MihonRuntimeException>()),
      );
    },
  );

  test('passes the native runtime token to the HTTP bridge only', () async {
    const channel = MethodChannel('m_extension_server');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'startServer');
      return {'port': 34879, 'token': 'local-bridge-token'};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final client = MockClient((request) async {
      expect(request.url.host, '127.0.0.1');
      expect(request.headers['x-kuchie-runtime-token'], 'local-bridge-token');
      if (request.url.path == '/capabilities') {
        return http.Response(_capabilities, 200);
      }
      return http.Response('{"mangas":[],"hasNextPage":false}', 200);
    });
    final runtime = MihonRuntimeClient(client: client);
    final result = await runtime.browse(
      Uint8List.fromList([1]),
      _source,
      query: '',
      latest: false,
      page: 1,
    );
    expect(result.items, isEmpty);
  });

  test('accepts empty URLs and blank names the way Mihon does', () async {
    final apk = Uint8List.fromList([4, 2]);
    final client = MockClient((request) async {
      if (request.url.path == '/capabilities') {
        return http.Response(_capabilities, 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return switch (body['method']) {
        'extensionInfo' when body['data'] == null => http.Response(
          '{"error":"Extension not loaded","code":409}',
          409,
        ),
        'extensionInfo' => http.Response(
          jsonEncode({
            'packageName': 'example.webcomic',
            'itemType': 'manga',
            'sources': [
              {'id': _source.id, 'name': _source.name, 'lang': 'en'},
            ],
          }),
          200,
        ),
        // A single-series source lists its comic at the site's front page.
        'getPopularManga' => http.Response(
          jsonEncode({
            'mangas': [
              {'url': '', 'title': 'Patch Friday'},
            ],
            'hasNextPage': false,
          }),
          200,
        ),
        // Details that leave the URL and title empty keep the listed ones.
        'getDetailsManga' => http.Response(
          jsonEncode({'url': '', 'title': ' ', 'description': 'Webcomic'}),
          200,
        ),
        'getChapterList' => http.Response(
          jsonEncode([
            {'url': '', 'name': '', 'chapter_number': 3.0},
            {'url': '/2', 'name': ' '},
          ]),
          200,
        ),
        _ => http.Response('{"error":"unexpected"}', 500),
      };
    });
    final runtime = MihonRuntimeClient(
      client: client,
      resolveEndpoint: () async => _endpoint,
    );
    addTearDown(runtime.close);
    await runtime.inspect(apk, packageName: 'example.webcomic');

    final listed = (await runtime.browse(
      apk,
      _source,
      query: '',
      latest: false,
      page: 1,
    )).items.single;
    expect(listed.locator, '');
    expect(listed.title, 'Patch Friday');

    final details = await runtime.details(apk, _source, listed);
    expect(details.locator, '');
    expect(details.title, 'Patch Friday');
    expect(details.description, 'Webcomic');

    final chapters = await runtime.chapters(apk, _source, details);
    expect(chapters.map((chapter) => chapter.locator), ['', '/2']);
    expect(chapters.map((chapter) => chapter.title), ['Chapter 3', 'Chapter']);
  });
}
