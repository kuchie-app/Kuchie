import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

// `fixtures/catalog_v6` was written by the 1.2.1 catalog (schema 6): two
// library series, a saved chapter with progress and a bookmark, categories,
// an online read in History, chapter marks and series meta.
void main() {
  late Directory workspace;
  late Directory root;
  late LocalCatalog catalog;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-catalog-v7');
    root = Directory(p.join(workspace.path, 'catalog'));
    await _copy(
      Directory('test/src/features/sync/data/fixtures/catalog_v6'),
      root,
    );
    catalog = LocalCatalog(root);
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  test('the fixture is a schema 6 catalog without sync tables', () {
    final db = sqlite3.open(
      'test/src/features/sync/data/fixtures/catalog_v6/catalog.sqlite',
      mode: OpenMode.readOnly,
    );
    addTearDown(db.close);
    expect(db.select('PRAGMA user_version').single.values.single, 6);
    expect(
      db.select("SELECT name FROM sqlite_master WHERE name LIKE 'sync_%'"),
      isEmpty,
    );
  });

  test('upgrading keeps every row of the 1.2.1 catalog', () async {
    final series = {for (final s in await catalog.list()) s.id: s};
    expect(series.keys, unorderedEquals(['lantern', 'harbor']));

    final lantern = series['lantern']!;
    expect(lantern.title, 'Lantern');
    expect(lantern.inLibrary, isTrue);
    expect(lantern.source?.toJson(), {
      'sourceId': 'qa.source',
      'mangaId': 'lantern',
      'locator': 'https://comics.example/lantern',
    });
    expect(lantern.categories, ['Favorites']);
    final chapter = lantern.chapters.single;
    expect(chapter.progress, 2);
    expect(chapter.bookmarked, isTrue);
    expect(chapter.lastReadAt, isNotNull);
    expect(chapter.pages, hasLength(3));
    for (final page in chapter.pages) {
      expect(await page.exists(), isTrue);
    }

    expect(series['harbor']!.inLibrary, isTrue);
    expect(await catalog.categories(), ['Favorites', 'Later']);
    final read = (await catalog.remoteHistory()).single;
    expect(
      (read.seriesId, read.chapterId, read.progress),
      ('harbor', 'harbor-1', 4),
    );
    final marks = await catalog.chapterMarks('harbor');
    expect(marks.keys, unorderedEquals(['harbor-1', 'harbor-2']));
    expect(marks.values.every((mark) => mark.read), isTrue);
    final meta = await catalog.seriesMeta('harbor');
    expect(meta.rating, 4);
    expect(meta.notes, 'Reread arc 2');
    expect(meta.tags, ['Isekai', 'Favorite']);
  });

  test('upgrading adds empty sync tables and reaches schema 7', () async {
    final journal = SyncJournal(catalog);
    expect(await journal.pending(), isEmpty);
    expect(await journal.links('suwayomi'), isEmpty);
    expect(await journal.transfers(), isEmpty);
    await catalog.close();

    final db = sqlite3.open(p.join(root.path, 'catalog.sqlite'));
    addTearDown(db.close);
    expect(db.select('PRAGMA user_version').single.values.single, 7);
    expect(
      db
          .select(
            "SELECT name FROM sqlite_master WHERE name LIKE 'sync_%' ORDER BY name",
          )
          .map((row) => row['name']),
      [
        'sync_base',
        'sync_changes',
        'sync_changes_key',
        'sync_links',
        'sync_links_remote',
        'sync_transfers',
      ],
    );
    catalog = LocalCatalog(root);
  });

  test('the upgrade writes nothing to the outbox, even with sync on', () async {
    catalog.journalEnabled = true;
    expect(await catalog.list(), hasLength(2));
    expect(await SyncJournal(catalog).pending(), isEmpty);
  });
}

Future<void> _copy(Directory from, Directory to) async {
  await for (final entity in from.list(recursive: true)) {
    final target = p.join(to.path, p.relative(entity.path, from: from.path));
    if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}
