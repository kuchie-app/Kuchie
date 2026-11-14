import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_download_queue.dart';

void main() {
  test(
    'an interrupted job stays on disk and can resume with the same ids',
    () async {
      final root = await Directory.systemTemp.createTemp('kuchie-queue-test');
      addTearDown(() => root.delete(recursive: true));
      final catalog = LocalCatalog(Directory('${root.path}/catalog'));
      addTearDown(catalog.close);
      final file = File('${root.path}/queue.json');
      final queue = LocalDownloadQueue(
        catalog,
        file,
        clientFactory: () =>
            MockClient((_) async => http.Response('temporary failure', 503)),
      );
      const title = 'QA Manga';
      await queue.enqueue(
        LocalDownloadRequest(
          seriesId: 'qa:series',
          title: title,
          chapterId: 'one',
          chapterTitle: 'Chapter 1',
          pages: [Uri.parse('https://example.com/1.png')],
        ),
      );
      await queue.idle;
      expect(queue.value.single.state, LocalDownloadState.failed);
      final restarted = LocalDownloadQueue(catalog, file);
      await restarted.load();
      expect(restarted.value.single.request.title, title);
      expect(restarted.value.single.state, LocalDownloadState.failed);
      await restarted.remove('qa:series', 'one');
      expect(restarted.value, isEmpty);
    },
  );

  test('Mihon chapter resolves new URLs and headers after reopening', () async {
    final root = await Directory.systemTemp.createTemp('kuchie-queue-runtime');
    addTearDown(() => root.delete(recursive: true));
    final catalog = LocalCatalog(Directory('${root.path}/catalog'));
    addTearDown(catalog.close);
    final file = File('${root.path}/queue.json');
    final first = LocalDownloadQueue(
      catalog,
      file,
      resolveRuntimeChapter: (_, _) async => throw StateError('Runtime down'),
    );
    await first.enqueue(
      const LocalDownloadRequest(
        seriesId: 'source:manga',
        title: 'Manga',
        chapterId: 'chapter',
        chapterTitle: 'Chapter',
        pages: [],
        runtimeChapter: (sourceId: 'source', locator: '/chapter/1'),
      ),
    );
    await first.idle;
    expect(first.value.single.state, LocalDownloadState.failed);
    expect(await file.readAsString(), isNot(contains('"pages"')));

    final restarted = LocalDownloadQueue(
      catalog,
      file,
      resolveRuntimeChapter: (id, locator) async {
        expect(id, 'source');
        expect(locator, '/chapter/1');
        return [
          (
            url: Uri.parse('http://127.0.0.1:49001/image/fresh-token'),
            headers: const {'Referer': 'https://example.com/chapter/1'},
          ),
        ];
      },
      clientFactory: () => MockClient((request) async {
        expect(request.url.path, '/image/fresh-token');
        expect(request.headers['Referer'], 'https://example.com/chapter/1');
        return http.Response.bytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j0l8AAAAASUVORK5CYII=',
          ),
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    await restarted.load();
    await restarted.resume('source:manga', 'chapter');
    await restarted.idle;
    expect(restarted.value, isEmpty);
    expect((await catalog.list()).single.chapters.single.pages, hasLength(1));
  });
}
