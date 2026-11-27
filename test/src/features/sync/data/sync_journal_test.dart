import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/domain/sync_change.dart';
import 'package:path/path.dart' as p;

typedef _Entry = (SyncRecordKind, String, SyncChangeOp);

const _upsert = SyncChangeOp.upsert;

void main() {
  late Directory workspace;
  late LocalCatalog catalog;
  late SyncJournal journal;
  late String saved;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-sync-journal');
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
    journal = SyncJournal(catalog);
    await catalog.setInLibrary(seriesId: 's', title: 'S', inLibrary: true);
    final contents = Archive()
      ..addFile(ArchiveFile.bytes('1.jpg', [1]))
      ..addFile(ArchiveFile.bytes('2.jpg', [2]));
    final file = await File(
      p.join(workspace.path, 'Chapter.cbz'),
    ).writeAsBytes(ZipEncoder().encode(contents));
    saved = (await catalog.importArchive(
      file,
      seriesId: 's',
    )).chapters.single.id;
    await catalog.createCategory('Favorites');
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  Future<List<_Entry>> entries() async => [
    for (final change in await journal.pending())
      (change.kind, change.key, change.op),
  ];

  String chapter(String id) => chapterStateKey('s', id);

  final writes = <String, (Future<void> Function(LocalCatalog), _Entry)>{
    'setInLibrary': (
      (c) => c.setInLibrary(seriesId: 'x', title: 'X', inLibrary: true),
      (SyncRecordKind.series, 'x', _upsert),
    ),
    'setInLibrary off': (
      (c) => c.setInLibrary(seriesId: 's', title: 'S', inLibrary: false),
      (SyncRecordKind.series, 's', _upsert),
    ),
    'recordRemoteRead': (
      (c) => c.recordRemoteRead(
        series: LocalSeries(id: 's', title: 'S', chapters: const []),
        chapterId: 'online',
        chapterTitle: 'Online',
        progress: 3,
      ),
      (SyncRecordKind.chapterState, chapterStateKey('s', 'online'), _upsert),
    ),
    'setChapterMarks': (
      (c) => c.setChapterMarks('s', ['online'], read: true),
      (SyncRecordKind.chapterState, chapterStateKey('s', 'online'), _upsert),
    ),
    'setCategories': (
      (c) => c.setCategories('s', ['Favorites']),
      (SyncRecordKind.membership, 's', _upsert),
    ),
    'createCategory': (
      (c) => c.createCategory('  Later '),
      (SyncRecordKind.category, 'later', _upsert),
    ),
    'deleteCategory': (
      (c) => c.deleteCategory('Favorites'),
      (SyncRecordKind.category, 'favorites', SyncChangeOp.delete),
    ),
    'setRating': (
      (c) => c.setRating('s', 4),
      (SyncRecordKind.seriesMeta, 's', _upsert),
    ),
    'setNotes': (
      (c) => c.setNotes('s', 'Notes'),
      (SyncRecordKind.seriesMeta, 's', _upsert),
    ),
    'setTags': (
      (c) => c.setTags('s', ['Isekai']),
      (SyncRecordKind.seriesMeta, 's', _upsert),
    ),
  };

  group('with sync on, each write records exactly one change', () {
    setUp(() => catalog.journalEnabled = true);

    for (final MapEntry(key: name, value: (write, expected))
        in writes.entries) {
      test(name, () async {
        await write(catalog);
        expect(await entries(), [expected]);
      });
    }

    test('setProgress', () async {
      await catalog.setProgress('s', saved, 1);
      expect(await entries(), [
        (SyncRecordKind.chapterState, chapter(saved), _upsert),
      ]);
    });

    test('setBookmark', () async {
      await catalog.setBookmark('s', saved, true);
      expect(await entries(), [
        (SyncRecordKind.chapterState, chapter(saved), _upsert),
      ]);
    });

    test('removeFromHistory records each chapter it clears', () async {
      catalog.journalEnabled = false;
      await catalog.setProgress('s', saved, 1);
      await writes['recordRemoteRead']!.$1(catalog);
      await catalog.recordRemoteRead(
        series: LocalSeries(id: 'other', title: 'O', chapters: const []),
        chapterId: 'c',
        chapterTitle: 'C',
        progress: 0,
      );
      catalog.journalEnabled = true;
      await catalog.removeFromHistory('s');
      expect(
        await entries(),
        unorderedEquals([
          (SyncRecordKind.chapterState, chapter('online'), _upsert),
          (SyncRecordKind.chapterState, chapter(saved), _upsert),
        ]),
      );
      expect((await catalog.remoteHistory()).single.seriesId, 'other');
      expect((await catalog.find('s'))!.chapters.single.lastReadAt, isNull);
    });

    test('clearHistory records each chapter it clears', () async {
      catalog.journalEnabled = false;
      await catalog.setProgress('s', saved, 1);
      await catalog.recordRemoteRead(
        series: LocalSeries(id: 'other', title: 'O', chapters: const []),
        chapterId: 'c',
        chapterTitle: 'C',
        progress: 0,
      );
      catalog.journalEnabled = true;
      await catalog.clearHistory();
      expect(
        await entries(),
        unorderedEquals([
          (SyncRecordKind.chapterState, chapterStateKey('other', 'c'), _upsert),
          (SyncRecordKind.chapterState, chapter(saved), _upsert),
        ]),
      );
      expect(await catalog.remoteHistory(), isEmpty);
    });

    test('setChapterMarks records one change per chapter', () async {
      await catalog.setChapterMarks('s', ['a', 'b', 'a'], bookmarked: true);
      expect(await entries(), [
        (SyncRecordKind.chapterState, chapter('a'), _upsert),
        (SyncRecordKind.chapterState, chapter('b'), _upsert),
      ]);
    });

    test('deleteCategory also records the series that were in it', () async {
      catalog.journalEnabled = false;
      await catalog.setCategories('s', ['Favorites']);
      catalog.journalEnabled = true;
      await catalog.deleteCategory('Favorites');
      expect(await entries(), [
        (SyncRecordKind.category, 'favorites', SyncChangeOp.delete),
        (SyncRecordKind.membership, 's', _upsert),
      ]);
    });

    test('writes that change nothing record nothing', () async {
      await catalog.setProgress('s', 'missing', 1);
      await catalog.setBookmark('s', 'missing', true);
      await catalog.setChapterMarks('s', ['a']);
      await catalog.deleteCategory('Missing');
      expect(await entries(), isEmpty);
    });

    test('writes outside sync record nothing', () async {
      await catalog.renameSeries('s', 'Renamed');
      await catalog.setCover('s', null);
      await catalog.removeChapter('s', saved);
      expect(await entries(), isEmpty);
    });

    test('restoring a backup records what it restored', () async {
      catalog.journalEnabled = false;
      await catalog.setProgress('s', saved, 1);
      await catalog.setCategories('s', ['Favorites']);
      // Backups keep favorites that have a source to open them from.
      await catalog.setInLibrary(
        seriesId: 's',
        title: 'S',
        inLibrary: true,
        source: const LocalSeriesSource(
          sourceId: 'qa.source',
          mangaId: 's',
          locator: 'https://comics.example/s',
        ),
      );
      final backup = File(p.join(workspace.path, 'backup.json'));
      await catalog.exportMetadata(backup);
      await catalog.setInLibrary(seriesId: 's', title: 'S', inLibrary: false);
      await catalog.setCategories('s', []);
      catalog.journalEnabled = true;
      await catalog.restoreMetadata(backup);
      expect(await entries(), [
        (SyncRecordKind.category, 'favorites', _upsert),
        (SyncRecordKind.series, 's', _upsert),
        (SyncRecordKind.chapterState, chapter(saved), _upsert),
        (SyncRecordKind.membership, 's', _upsert),
      ]);
    });

    test('incognito keeps reading progress out, not marks', () async {
      catalog.incognito = true;
      await catalog.setProgress('s', saved, 1);
      await writes['recordRemoteRead']!.$1(catalog);
      expect(await entries(), isEmpty);
      await catalog.setChapterMarks('s', [saved], read: true);
      expect(await entries(), [
        (SyncRecordKind.chapterState, chapter(saved), _upsert),
      ]);
    });

    test('changes applied from a backend are not recorded', () async {
      await runApplyingRemote(() async {
        for (final (write, _) in writes.values) {
          await write(catalog);
        }
        await catalog.setProgress('s', saved, 1);
        await catalog.clearHistory();
      });
      expect(await entries(), isEmpty);
      await catalog.setRating('s', 2);
      expect(await entries(), hasLength(1));
    });

    test('a failed write leaves no change behind', () async {
      await expectLater(
        catalog.setCategories('s', ['No such category']),
        throwsA(anything),
      );
      expect(await entries(), isEmpty);
    });
  });

  test('with sync off, no write records a change', () async {
    for (final (write, _) in writes.values) {
      await write(catalog);
    }
    await catalog.setProgress('s', saved, 1);
    await catalog.setBookmark('s', saved, true);
    await catalog.clearHistory();
    expect(await entries(), isEmpty);
  });

  group('outbox', () {
    setUp(() async {
      catalog.journalEnabled = true;
      await catalog.setRating('a', 1);
      await catalog.setNotes('b', 'n');
      await catalog.setRating('a', 2);
      await catalog.createCategory('Later');
      await catalog.deleteCategory('Later');
    });

    test('pending lists entries oldest first, up to the limit', () async {
      final all = await journal.pending();
      for (var i = 1; i < all.length; i++) {
        expect(all[i].seq, greaterThan(all[i - 1].seq));
      }
      expect(all.map((c) => c.key), ['a', 'b', 'a', 'later', 'later']);
      expect(await journal.pending(limit: 2), all.take(2).toList());
    });

    test('coalesced keeps the newest entry per key, in its order', () async {
      final all = await journal.pending();
      final coalesced = await journal.coalesced();
      expect(coalesced, [all[1], all[2], all[4]]);
      expect(coalesced.last.op, SyncChangeOp.delete);
    });

    test('trimThrough drops pushed entries and keeps later ones', () async {
      final all = await journal.pending();
      await journal.trimThrough(all[2].seq);
      expect(await journal.pending(), all.sublist(3));
      await catalog.setRating('a', 3);
      final next = await journal.pending();
      expect(next.last.seq, greaterThan(all.last.seq));
      await journal.clearChanges();
      expect(await journal.pending(), isEmpty);
    });
  });

  test('links are kept per backend and found from either side', () async {
    const series = SyncLink(
      kind: SyncLinkKind.series,
      localKey: 's',
      remoteId: '42',
    );
    await journal.putLink('suwayomi', series);
    await journal.putLink(
      'suwayomi',
      const SyncLink(
        kind: SyncLinkKind.category,
        localKey: 'favorites',
        remoteId: '7',
      ),
    );
    await journal.putLink(
      'other',
      const SyncLink(kind: SyncLinkKind.series, localKey: 's', remoteId: '9'),
    );
    expect(await journal.links('suwayomi'), [
      const SyncLink(
        kind: SyncLinkKind.category,
        localKey: 'favorites',
        remoteId: '7',
      ),
      series,
    ]);
    expect(
      await journal.localKeyFor('suwayomi', SyncLinkKind.series, '42'),
      's',
    );
    expect(
      await journal.localKeyFor('suwayomi', SyncLinkKind.chapter, '42'),
      isNull,
    );
    await journal.putLink(
      'suwayomi',
      const SyncLink(kind: SyncLinkKind.series, localKey: 's', remoteId: '43'),
    );
    expect(
      await journal.localKeyFor('suwayomi', SyncLinkKind.series, '43'),
      's',
    );
    await journal.removeLinks('suwayomi');
    expect(await journal.links('suwayomi'), isEmpty);
    expect(await journal.links('other'), hasLength(1));
  });

  test('base values round-trip and clear per backend', () async {
    expect(await journal.base('suwayomi', SyncRecordKind.series, 's'), isNull);
    await journal.putBase('suwayomi', SyncRecordKind.series, 's', {
      'inLibrary': true,
      'categories': ['favorites'],
    });
    await journal.putBase('suwayomi', SyncRecordKind.series, 's', {
      'inLibrary': false,
    });
    await journal.putBase('other', SyncRecordKind.series, 's', {
      'inLibrary': true,
    });
    await journal.putLink(
      'suwayomi',
      const SyncLink(kind: SyncLinkKind.series, localKey: 's', remoteId: '1'),
    );
    expect(await journal.base('suwayomi', SyncRecordKind.series, 's'), {
      'inLibrary': false,
    });
    await journal.putBase('suwayomi', SyncRecordKind.seriesMeta, 's', {
      'rating': 3,
    });
    await journal.removeBase('suwayomi', SyncRecordKind.seriesMeta, 's');
    expect(
      await journal.base('suwayomi', SyncRecordKind.seriesMeta, 's'),
      isNull,
    );
    catalog.journalEnabled = true;
    await catalog.setRating('s', 1);
    await journal.clearBackend('suwayomi');
    expect(await journal.base('suwayomi', SyncRecordKind.series, 's'), isNull);
    expect(await journal.links('suwayomi'), isEmpty);
    expect(await journal.base('other', SyncRecordKind.series, 's'), {
      'inLibrary': true,
    });
    expect(await journal.pending(), hasLength(1));
  });

  test('transfers are added, replaced, filtered and removed', () async {
    final queued = SyncTransfer(
      seriesId: 's',
      chapterId: 'c1',
      keepLocal: true,
      state: SyncTransferState.queued,
      updatedAt: DateTime.utc(2026, 11, 27, 10),
    );
    await journal.putTransfer(queued);
    await journal.putTransfer(
      SyncTransfer(
        seriesId: 's',
        chapterId: 'c2',
        keepLocal: false,
        state: SyncTransferState.queued,
        updatedAt: DateTime.utc(2026, 11, 27, 11),
      ),
    );
    final failed = SyncTransfer(
      seriesId: 's',
      chapterId: 'c2',
      remoteChapterId: 88,
      keepLocal: false,
      state: SyncTransferState.failed,
      error: 'disk full',
      updatedAt: DateTime.utc(2026, 11, 27, 12),
    );
    await journal.putTransfer(failed);
    expect(await journal.transfers(), [queued, failed]);
    expect(await journal.transfers(states: {SyncTransferState.failed}), [
      failed,
    ]);
    await journal.removeTransfer('s', 'c1');
    expect(await journal.transfers(), [failed]);
  });

  test('chapter state keys hold any ids and parse back', () {
    const id = 'https://example.com/a?b=["c"]';
    expect(parseChapterStateKey(chapterStateKey(id, 'x/1')), (id, 'x/1'));
    expect(parseChapterStateKey('s'), isNull);
    expect(parseChapterStateKey('[1, 2]'), isNull);
    expect(SyncRecordKind.parse('chapter_state'), SyncRecordKind.chapterState);
    expect(SyncRecordKind.parse('nope'), isNull);
  });
}
