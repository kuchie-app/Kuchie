import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory workspace;
  late LocalCatalog catalog;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-catalog-test');
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  Future<File> archive(String name, Map<String, List<int>> entries) async {
    final contents = Archive();
    for (final entry in entries.entries) {
      contents.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    return File(
      p.join(workspace.path, '$name.cbz'),
    ).writeAsBytes(ZipEncoder().encode(contents));
  }

  test(
    'a clean catalog imports pages in natural order and persists reading state',
    () async {
      expect(await catalog.list(), isEmpty);
      expect(await catalog.find('a-title-not-in-library'), isNull);
      final file = await archive('Manga', {
        'book/page10.jpg': [10],
        'book/page2.jpg': [2],
        'book/page1.jpg': [1],
        'book/readme.txt': [0],
      });
      final series = await catalog.importArchive(file);
      final chapter = series.chapters.single;
      expect(series.title, 'Manga');
      expect(
        await Future.wait(chapter.pages.map((page) => page.readAsBytes())),
        [
          [1],
          [2],
          [10],
        ],
      );
      await catalog.setProgress(series.id, chapter.id, 1);
      await catalog.setBookmark(series.id, chapter.id, true);
      expect(
        (await catalog.importArchive(file, seriesId: series.id)).chapters,
        hasLength(1),
      );
      await file.delete();
      await catalog.close();
      catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
      final stored = (await catalog.list()).single.chapters.single;
      expect(stored.progress, 1);
      expect(stored.bookmarked, isTrue);
      expect(stored.lastReadAt, isNotNull);
      expect(await stored.pages[1].readAsBytes(), [2]);
    },
  );

  test('rejects archive traversal before publishing a series', () async {
    final file = await archive('Untrusted', {
      '../escape.jpg': [1],
    });
    await expectLater(catalog.importArchive(file), throwsFormatException);
    expect(await catalog.list(), isEmpty);
    expect(await File(p.join(workspace.path, 'escape.jpg')).exists(), isFalse);
  });

  test('migrates previous catalog with chapters into the library', () async {
    final folder = Directory(p.join(workspace.path, 'catalog'));
    final storage = await Directory(
      p.join(folder.path, 'pages', 'old-storage'),
    ).create(recursive: true);
    final page = await File(p.join(storage.path, '1.jpg')).writeAsBytes([1]);
    final db = sqlite3.open(p.join(folder.path, 'catalog.sqlite'));
    try {
      db.execute('''
        PRAGMA user_version = 2;
        CREATE TABLE series (id TEXT PRIMARY KEY, title TEXT NOT NULL);
        CREATE TABLE chapters (
          series_id TEXT, id TEXT, title TEXT, storage TEXT, page_names TEXT,
          fingerprint TEXT, position INTEGER, ready INTEGER, progress INTEGER,
          bookmarked INTEGER, last_read_at INTEGER
        );
        CREATE TABLE categories (name TEXT PRIMARY KEY);
        CREATE TABLE series_categories (series_id TEXT, name TEXT);
        INSERT INTO series VALUES ('old-id', 'Old title');
        INSERT INTO chapters VALUES ('old-id', 'chapter', 'Chapter 1',
          'old-storage', '["1.jpg"]', NULL, 1, 1, 0, 0, 1);
      ''');
    } finally {
      db.close();
    }
    final stored = (await catalog.list()).single;
    expect(stored.inLibrary, isTrue);
    expect(stored.id, 'old-id');
    expect(stored.chapters.single.pages.single.path, page.path);
    expect(await stored.chapters.single.pages.single.exists(), isTrue);
  });

  test('finishes a migration with columns already present', () async {
    await catalog.setInLibrary(
      seriesId: 'existing',
      title: 'Existing',
      inLibrary: true,
    );
    await catalog.close();
    final path = p.join(workspace.path, 'catalog', 'catalog.sqlite');
    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA user_version = 2');
    } finally {
      db.close();
    }
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
    expect((await catalog.find('existing'))?.inLibrary, isTrue);
  });

  test(
    'source favorites survive relaunch and a backup without downloading',
    () async {
      const source = LocalSeriesSource(
        sourceId: 'qa.source',
        mangaId: 'lantern',
        locator: 'https://comics.example/chapters',
      );
      await catalog.setInLibrary(
        seriesId: 'title-id',
        title: 'Lantern',
        inLibrary: true,
        source: source,
      );
      await catalog.createCategory('Favorites');
      await catalog.setCategories('title-id', ['Favorites']);
      await catalog.close();
      catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
      var stored = (await catalog.find('title-id'))!;
      expect(stored.inLibrary, isTrue);
      expect(stored.chapters, isEmpty);
      expect(stored.source?.toJson(), source.toJson());
      final backup = File(p.join(workspace.path, 'library.json'));
      await catalog.exportMetadata(backup);
      await catalog.close();
      catalog = LocalCatalog(Directory(p.join(workspace.path, 'restored')));
      await catalog.restoreMetadata(backup);
      stored = (await catalog.list()).single;
      expect(stored.inLibrary, isTrue);
      expect(stored.chapters, isEmpty);
      expect(stored.categories, ['Favorites']);
      expect(stored.source?.toJson(), source.toJson());
    },
  );

  test(
    'removing a favorite preserves downloaded pages and future downloads',
    () async {
      const source = LocalSeriesSource(
        sourceId: 'qa.source',
        mangaId: 'lantern',
        locator: 'https://comics.example/chapters',
      );
      final client = MockClient(
        (_) async => http.Response.bytes(
          [1],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      addTearDown(client.close);
      Future<LocalSeries> save(String chapterId) => catalog.saveRemoteChapter(
        seriesId: 'title-id',
        title: 'Lantern',
        chapterId: chapterId,
        chapterTitle: chapterId,
        pages: [Uri.parse('https://comics.example/page.png')],
        client: client,
        source: source,
      );
      expect((await save('one')).inLibrary, isTrue);
      await catalog.setInLibrary(
        seriesId: 'title-id',
        title: 'Lantern',
        inLibrary: false,
        source: source,
      );
      final stored = await save('two');
      expect(stored.inLibrary, isFalse);
      expect(stored.source?.toJson(), source.toJson());
      expect(stored.chapters.map((chapter) => chapter.id), ['one', 'two']);
      expect(await stored.chapters.first.pages.single.exists(), isTrue);
    },
  );

  test(
    'keeps categories and the renamed series in the local catalog',
    () async {
      final file = await archive('Original', {
        '1.png': [1],
      });
      final series = await catalog.importArchive(file);
      await catalog.createCategory('Favorites');
      await catalog.createCategory('To read');
      await catalog.setCategories(series.id, [
        'To read',
        'Favorites',
        'To read',
      ]);
      await catalog.renameSeries(series.id, 'Renamed');
      await catalog.deleteCategory('To read');
      await catalog.close();
      catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
      final stored = (await catalog.list()).single;
      expect(stored.title, 'Renamed');
      expect(stored.categories, ['Favorites']);
      expect(await catalog.categories(), ['Favorites']);
      expect(await stored.chapters.single.pages.single.readAsBytes(), [1]);
    },
  );

  test(
    'restores reading metadata after the same archive is imported on a new device',
    () async {
      final archiveFile = await archive('Portable', {
        '1.png': [1],
        '2.png': [2],
      });
      final original = await catalog.importArchive(archiveFile);
      await catalog.createCategory('Portable');
      await catalog.createCategory('Empty category');
      await catalog.setCategories(original.id, ['Portable']);
      await catalog.setProgress(original.id, original.chapters.single.id, 1);
      await catalog.setBookmark(original.id, original.chapters.single.id, true);
      await catalog.importArchive(
        await archive('Absent', {
          '1.png': [3],
        }),
      );
      final backup = File(p.join(workspace.path, 'collection.json'));
      await catalog.exportMetadata(backup);
      await catalog.close();
      catalog = LocalCatalog(Directory(p.join(workspace.path, 'new-catalog')));
      final imported = await catalog.importArchive(archiveFile);
      expect(imported.id, isNot(original.id));
      await catalog.createCategory('Keep');
      await catalog.setCategories(imported.id, ['Keep']);
      final result = await catalog.restoreMetadata(backup);
      expect(result, (restored: 1, skipped: 1));
      final restored = (await catalog.list()).single;
      expect(restored.categories, ['Keep', 'Portable']);
      expect(restored.chapters.single.progress, 1);
      expect(restored.chapters.single.bookmarked, isTrue);
      expect(await catalog.categories(), [
        'Empty category',
        'Keep',
        'Portable',
      ]);
    },
  );

  test(
    'imports image folders and appends a new chapter to the chosen title',
    () async {
      final source = await Directory(p.join(workspace.path, 'Series')).create();
      final nested = await Directory(p.join(source.path, 'pages')).create();
      await File(p.join(nested.path, '1.png')).writeAsBytes([1]);
      final series = await catalog.importFolder(source);
      final file = await archive('Chapter 2', {
        '1.webp': [2],
      });
      final updated = await catalog.importArchive(file, seriesId: series.id);
      expect(updated.title, 'Series');
      expect(updated.chapters.map((chapter) => chapter.title), [
        'Series',
        'Chapter 2',
      ]);
      final removed = updated.chapters.last;
      await catalog.removeChapter(updated.id, removed.id);
      expect((await catalog.list()).single.chapters, hasLength(1));
      expect(await removed.pages.single.exists(), isFalse);
    },
  );

  test('previews remote pages without adding them to the catalog', () async {
    final directory = await Directory(
      p.join(workspace.path, 'preview'),
    ).create();
    final updates = <(int, int)>[];
    final pages = [
      Uri.parse('https://example.test/1'),
      Uri.parse('https://example.test/2'),
    ];
    final client = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response.bytes(
        [int.parse(request.url.path.substring(1))],
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final chapter = await catalog.previewRemoteChapter(
      directory: directory,
      chapterId: 'temp',
      title: 'Preview',
      pages: pages,
      client: client,
      onProgress: (done, total) => updates.add((done, total)),
    );
    expect(chapter.id, 'temp');
    expect(updates, [(1, 2), (2, 2)]);
    expect(await chapter.pages[1].readAsBytes(), [2]);
    expect(await catalog.list(), isEmpty);
    await directory.delete(recursive: true);
    expect(await chapter.pages[0].exists(), isFalse);
  });

  test(
    'source reader requests only visible files and retries pages independently',
    () async {
      final requests = <String>[];
      var fail = true;
      var closed = false;
      final client = MockClient((request) async {
        requests.add(request.url.path);
        expect(request.followRedirects, isFalse);
        expect(request.headers['referer'], 'https://source.test/');
        if (fail && request.url.path == '/2') return http.Response('', 503);
        return http.Response.bytes(
          [1],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final pages = LocalPreviewPages(
        directory: Directory(p.join(workspace.path, 'lazy-preview')),
        chapterId: 'source-chapter',
        title: 'Preview',
        urls: List.generate(
          40,
          (index) => Uri.https('image.test', '/${index + 1}'),
        ),
        headers: List.filled(40, {'referer': 'https://source.test/'}),
        client: client,
        isCancelled: () => closed,
      );
      final files = pages.chapter.pages;
      expect(files, hasLength(40));
      expect(requests, isEmpty);
      final visible = files.first.uri.toString();
      final first = pages.prepare(visible);
      expect(pages.prepare(visible), same(first));
      expect(await (await first).readAsBytes(), [1]);
      final second = files[1].uri.toString();
      await expectLater(
        pages.prepare(second),
        throwsA(isA<http.ClientException>()),
      );
      expect(await files[1].exists(), isFalse);
      fail = false;
      expect(await (await pages.prepare(second)).readAsBytes(), [1]);
      expect(await files.last.exists(), isFalse);
      closed = true;
      await expectLater(
        pages.prepare(files.last.uri.toString()),
        throwsA(isA<LocalTransferCancelled>()),
      );
      expect(requests, ['/1', '/2', '/2']);
      expect(await catalog.list(), isEmpty);
    },
  );

  test(
    'interrupted remote chapter resumes at the next fully saved page',
    () async {
      final pages = [
        Uri.parse('https://example.test/1'),
        Uri.parse('https://example.test/2'),
      ];
      var fail = true;
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/2' && fail) {
          return http.Response('retry', 503);
        }
        return http.Response.bytes(
          [int.parse(request.url.path.substring(1))],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      Future<LocalSeries> save() => catalog.saveRemoteChapter(
        seriesId: 'source:series',
        title: 'Series',
        chapterId: 'source:one',
        chapterTitle: 'Chapter 1',
        pages: pages,
        client: client,
      );
      await expectLater(save(), throwsA(isA<http.ClientException>()));
      expect(await catalog.list(), isEmpty);
      fail = false;
      final saved = await save();
      expect(requests, ['/1', '/2', '/2']);
      expect(await saved.chapters.single.pages.last.readAsBytes(), [2]);
    },
  );
}
