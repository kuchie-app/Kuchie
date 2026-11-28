import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/sync/controller/server_chapter_pages.dart';
import 'package:kuchie/src/features/sync/controller/server_transfers.dart';
import 'package:kuchie/src/features/sync/controller/sync_engine.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_backend.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Engine extends SyncEngine {
  _Engine(SyncStateStore store)
    : super(
        catalog: () => throw UnimplementedError(),
        store: store,
        probe: () => throw UnimplementedError(),
        backendAt: (_) => throw UnimplementedError(),
        localSources: () => throw UnimplementedError(),
        ensureServerIdentity: (_) => throw UnimplementedError(),
      );
}

/// The server's chapters and what it reports for their downloads.
class _Pages extends Fake implements SuwayomiChapterPages {
  _Pages(this.engine);

  @override
  final SyncEngine engine;
  bool reachable = true;
  final mangas = <String, String>{'s': '10'};
  final chapterIds = <String, int>{};

  @override
  Future<String?> baseUrl() async => reachable ? 'http://server' : null;

  @override
  Future<String?> mangaId(String seriesId) async => mangas[seriesId];

  @override
  Future<int?> chapterId(
    String baseUrl,
    String mangaId,
    String chapterId,
  ) async => chapterIds[chapterId];

  @override
  Future<Set<String>> downloadedChapters(
    String baseUrl,
    String mangaId,
  ) async => const {};

  @override
  void forget(String mangaId) {}
}

class _Server extends Fake implements SuwayomiBackend {
  final requested = <int>[];
  final reports = <int, ({bool downloaded, int pageCount})>{};
  bool down = false;

  @override
  Future<void> enqueueDownloads(List<int> chapterIds) async {
    if (down) throw const SocketException('down');
    requested.addAll(chapterIds);
  }

  @override
  Future<Map<int, ({bool downloaded, int pageCount})>> downloadStates(
    List<int> chapterIds,
  ) async {
    if (down) throw const SocketException('down');
    return {for (final id in chapterIds) id: ?reports[id]};
  }
}

/// Records every removal and fails the test if it comes before verified.
class _GuardedCatalog extends LocalCatalog {
  _GuardedCatalog(super.root);

  late SyncJournal journal;
  final removed = <String>[];

  @override
  Future<void> removeChapter(String seriesId, String chapterId) async {
    final transfer = (await journal.transfers()).firstWhere(
      (transfer) => transfer.chapterId == chapterId,
    );
    expect(
      transfer.state,
      SyncTransferState.verified,
      reason: 'a copy here was deleted before the server proved it has it',
    );
    removed.add(chapterId);
    return super.removeChapter(seriesId, chapterId);
  }
}

void main() {
  late Directory workspace;
  late _GuardedCatalog catalog;
  late SyncJournal journal;
  late _Pages pages;
  late _Server server;
  late DateTime now;
  late String saved;

  ServerTransfers transfers() => ServerTransfers(
    engine: pages.engine,
    catalog: () async => catalog,
    pages: pages,
    backendAt: (_) => server,
    clock: () => now,
  );

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-transfers');
    catalog = _GuardedCatalog(Directory(p.join(workspace.path, 'catalog')));
    journal = SyncJournal(catalog);
    catalog.journal = journal;
    await catalog.setInLibrary(seriesId: 's', title: 'S', inLibrary: true);
    final pagesZip = Archive();
    for (var i = 0; i < 3; i++) {
      pagesZip.addFile(ArchiveFile.bytes('$i.jpg', [i]));
    }
    final file = await File(
      p.join(workspace.path, 'c.cbz'),
    ).writeAsBytes(ZipEncoder().encode(pagesZip));
    saved = (await catalog.importArchive(
      file,
      seriesId: 's',
    )).chapters.single.id;
    SharedPreferences.setMockInitialValues({});
    final store = SyncStateStore(await SharedPreferences.getInstance());
    await store.setConnectChoice(ConnectChoice.merge);
    pages = _Pages(_Engine(store))..chapterIds[saved] = 7;
    server = _Server();
    now = DateTime.utc(2026, 11, 28, 10);
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  Future<SyncTransferState> stateOf(String chapterId) async =>
      (await journal.transfers())
          .firstWhere((transfer) => transfer.chapterId == chapterId)
          .state;

  Future<bool> savedHere() async =>
      (await catalog.find('s'))?.chapters.any((c) => c.id == saved) ?? false;

  test(
    'moving deletes the copy here only once the server has every page',
    () async {
      final job = transfers();
      await job.moveToServer([('s', saved)], keepLocal: false);
      expect(server.requested, [7]);
      expect(await stateOf(saved), SyncTransferState.requested);

      server.reports[7] = (downloaded: true, pageCount: 2);
      await job.run();
      expect(await savedHere(), isTrue, reason: 'a full disk: 2 of 3 pages');

      server.reports[7] = (downloaded: true, pageCount: 3);
      await job.run();
      expect(await stateOf(saved), SyncTransferState.done);
      expect(await savedHere(), isFalse);
      expect(catalog.removed, [saved]);
      job.dispose();
    },
  );

  test('keeping the copy leaves it here', () async {
    final job = transfers();
    await job.moveToServer([('s', saved)], keepLocal: true);
    server.reports[7] = (downloaded: true, pageCount: 3);
    await job.run();
    expect(await stateOf(saved), SyncTransferState.done);
    expect(await savedHere(), isTrue);
    job.dispose();
  });

  test(
    'a download the server never finishes fails and keeps the copy',
    () async {
      final job = transfers();
      await job.moveToServer([('s', saved)], keepLocal: false);
      now = now.add(const Duration(hours: 7));
      await job.run();
      expect(await stateOf(saved), SyncTransferState.failed);
      expect(await savedHere(), isTrue);
      job.dispose();
    },
  );

  test('a chapter the server lacks fails at once; the copy stays', () async {
    pages.chapterIds.clear();
    final job = transfers();
    await job.moveToServer([('s', saved)], keepLocal: false);
    expect(await stateOf(saved), SyncTransferState.failed);
    expect(await savedHere(), isTrue);
    job.dispose();
  });

  test('away from home the queue waits', () async {
    pages.reachable = false;
    final job = transfers();
    await job.moveToServer([('s', saved)], keepLocal: false);
    expect(await stateOf(saved), SyncTransferState.queued);
    expect(server.requested, isEmpty);
    job.dispose();
  });

  test('a server that drops mid-way keeps everything queued', () async {
    server.down = true;
    final job = transfers();
    await job.moveToServer([('s', saved)], keepLocal: false);
    expect(await stateOf(saved), SyncTransferState.queued);
    server.down = false;
    await job.run();
    expect(await stateOf(saved), SyncTransferState.requested);
    job.dispose();
  });

  test('a force-closed app picks up from the database', () async {
    await transfers().moveToServer([('s', saved)], keepLocal: false);
    // A new job, as after relaunching, reads the requested state back.
    final relaunched = transfers();
    server.reports[7] = (downloaded: true, pageCount: 3);
    await relaunched.run();
    expect(await stateOf(saved), SyncTransferState.done);
    relaunched.dispose();
  });

  test('a download to the server keeps nothing here to delete', () async {
    pages.chapterIds['online'] = 8;
    final job = transfers();
    await job.download('s', 'online');
    server.reports[8] = (downloaded: true, pageCount: 20);
    await job.run();
    expect(await stateOf('online'), SyncTransferState.done);
    expect(catalog.removed, isEmpty);
    job.dispose();
  });
}
