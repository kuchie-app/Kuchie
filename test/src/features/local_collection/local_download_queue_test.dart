import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_download_lifecycle.dart';
import 'package:kuchie/src/features/local_collection/data/local_download_queue.dart';
import 'package:kuchie/src/features/local_collection/data/local_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  LocalDownloadRequest runtimeRequest(int index) => LocalDownloadRequest(
    seriesId: 'source:manga',
    title: 'Manga',
    chapterId: 'chapter-$index',
    chapterTitle: 'Chapter $index',
    pages: const [],
    runtimeChapter: (sourceId: 'source', locator: '/chapter/$index'),
  );

  test('downloads up to the concurrency limit at once', () async {
    final root = await Directory.systemTemp.createTemp('kuchie-queue-parallel');
    addTearDown(() => root.delete(recursive: true));
    final catalog = LocalCatalog(Directory('${root.path}/catalog'));
    addTearDown(catalog.close);
    var running = 0;
    var peak = 0;
    final gate = Completer<void>();
    final queue = LocalDownloadQueue(
      catalog,
      File('${root.path}/queue.json'),
      resolveRuntimeChapter: (_, _) async {
        running++;
        peak = max(peak, running);
        await gate.future;
        running--;
        throw StateError('Stopped by the test');
      },
    )..concurrency = 2;
    for (var index = 0; index < 3; index++) {
      await queue.enqueue(runtimeRequest(index));
    }
    await pumpEventQueue();
    expect(peak, 2);
    expect(
      queue.value.where((item) => item.state == LocalDownloadState.downloading),
      hasLength(2),
    );
    gate.complete();
    await queue.idle;
    expect(peak, 2);
    expect(
      queue.value.map((item) => item.state),
      everyElement(LocalDownloadState.failed),
    );
  });

  testWidgets(
    'background off pauses running downloads and resumes them on return',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('kuchie-queue-bg');
        addTearDown(() => root.delete(recursive: true));
        final catalog = LocalCatalog(Directory('${root.path}/catalog'));
        addTearDown(catalog.close);
        final gate = Completer<void>();
        final queue = LocalDownloadQueue(
          catalog,
          File('${root.path}/queue.json'),
          resolveRuntimeChapter: (_, _) async {
            await gate.future;
            throw StateError('Stopped by the test');
          },
        );
        final preferences = LocalPreferences.instance;
        await preferences.setBackgroundDownloads(false);
        final lifecycle = LocalDownloadLifecycle(
          queue,
          supportsBackgroundTime: false,
        );
        await lifecycle.start();
        addTearDown(lifecycle.dispose);

        await queue.enqueue(runtimeRequest(0));
        await queue.enqueue(runtimeRequest(1));
        await pumpEventQueue();
        expect(queue.running, isTrue);

        await lifecycle.onHidden();
        expect(
          queue.value.map((item) => item.state),
          everyElement(LocalDownloadState.paused),
        );

        await lifecycle.onShown();
        expect(queue.running, isTrue);
        gate.complete();
        await queue.idle;
      });
    },
  );
}
