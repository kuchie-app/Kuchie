import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_services.dart';
import 'package:kuchie/src/features/local_collection/data/local_series_reader_meta.dart';
import 'package:kuchie/src/features/sync/controller/sync_engine.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_identity.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_reachability.dart';
import 'package:kuchie/src/features/sync/data/sync_backend.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/domain/sync_method.dart';
import 'package:kuchie/src/features/sync/domain/sync_records.dart';
import 'package:kuchie/src/features/sync/domain/sync_status.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// Design section 8, scenarios 1–6 and 12–14, against an in-memory server.

final _origin = Uri.parse('https://repo.example');
const _source = 'p:1';

class _Manga {
  _Manga(this.id, this.url, {this.inLibrary = true, Set<String>? categories})
    : categories = categories ?? {};

  final String id;
  final String url;
  bool inLibrary;
  DateTime? inLibraryAt;
  final Set<String> categories;
  final chapters = <_Chapter>[];
  final meta = <String, String>{};
  String get title => 'Title $url';
}

class _Chapter {
  _Chapter(this.id, this.seriesId, this.url);

  final String id;
  final String seriesId;
  final String url;
  ChapterState state = const ChapterState();
}

class _FakeServer implements SyncBackend {
  final mangas = <String, _Manga>{};
  final categoryNames = <String, String>{};
  var _nextId = 100;

  /// Every write request, by name.
  final writes = <String>[];

  /// The server time it stamps on a page update, in whole seconds.
  DateTime now = DateTime.utc(2026, 11, 1, 12);

  _Manga addManga(String url, {bool inLibrary = true}) {
    final manga = _Manga('${_nextId++}', url, inLibrary: inLibrary);
    mangas[manga.id] = manga;
    return manga;
  }

  _Chapter addChapter(_Manga manga, String url) {
    final chapter = _Chapter('${_nextId++}', manga.id, url);
    manga.chapters.add(chapter);
    return chapter;
  }

  String addCategory(String name) {
    final id = '${_nextId++}';
    categoryNames[id] = name;
    return id;
  }

  _Chapter chapter(String url) => mangas.values
      .expand((manga) => manga.chapters)
      .firstWhere((chapter) => chapter.url == url);

  RemoteSeries _series(_Manga manga) => RemoteSeries(
    id: manga.id,
    sourceId: '1',
    url: manga.url,
    title: manga.title,
    inLibrary: manga.inLibrary,
    inLibraryAt: manga.inLibraryAt,
    categoryIds: {...manga.categories},
    meta: {...manga.meta},
  );

  RemoteChapter _remote(_Chapter chapter) => RemoteChapter(
    id: chapter.id,
    seriesId: chapter.seriesId,
    url: chapter.url,
    name: 'Chapter ${chapter.url}',
    state: chapter.state,
  );

  @override
  String get key => 'suwayomi';

  @override
  Future<List<RemoteSeries>> library() async => [
    for (final manga in mangas.values)
      if (manga.inLibrary) _series(manga),
  ];

  @override
  Future<List<RemoteCategory>> categories() async => [
    for (final MapEntry(:key, :value) in categoryNames.entries)
      RemoteCategory(id: key, name: value),
  ];

  @override
  Future<List<RemoteChapter>> chaptersOf(String seriesId) async =>
      mangas[seriesId]!.chapters.map(_remote).toList();

  @override
  Future<List<RemoteChapter>> chaptersReadSince(
    Set<String> seriesIds,
    DateTime since,
  ) async => [
    for (final id in seriesIds)
      for (final chapter in mangas[id]?.chapters ?? <_Chapter>[])
        if (chapter.state.readAt?.isAfter(since) ?? false) _remote(chapter),
  ];

  @override
  Future<RemoteSeries?> findSeries(String sourceId, String url) async {
    for (final manga in mangas.values) {
      if (manga.url == url) return _series(manga);
    }
    return null;
  }

  /// Whether [createSeries] can make manga, as an admin's restore can.
  bool canCreate = true;

  @override
  Future<List<RemoteSeries>> createSeries(List<NewRemoteSeries> series) async {
    if (!canCreate) return const [];
    writes.add('createSeries');
    return [
      for (final entry in series)
        _series(addManga(entry.url)..inLibraryAt = now),
    ];
  }

  @override
  Future<List<RemoteChapter>> refreshChapters(String seriesId) =>
      chaptersOf(seriesId);

  @override
  Future<void> setInLibrary(
    List<String> seriesIds, {
    required bool inLibrary,
  }) async {
    writes.add('setInLibrary');
    for (final id in seriesIds) {
      mangas[id]!
        ..inLibrary = inLibrary
        ..inLibraryAt = inLibrary ? now : null;
    }
  }

  @override
  Future<RemoteCategory> createCategory(String name) async {
    writes.add('createCategory');
    return RemoteCategory(id: addCategory(name), name: name);
  }

  @override
  Future<void> changeCategories(
    List<String> seriesIds, {
    Set<String> add = const {},
    Set<String> remove = const {},
  }) async {
    writes.add('changeCategories');
    for (final id in seriesIds) {
      mangas[id]!.categories
        ..addAll(add)
        ..removeAll(remove);
    }
  }

  @override
  Future<void> setMetas(Map<String, Map<String, String>> metas) async {
    writes.add('setMetas');
    for (final MapEntry(:key, :value) in metas.entries) {
      mangas[key]!.meta.addAll(value);
    }
  }

  @override
  Future<void> deleteMetas(Map<String, Set<String>> keys) async {
    writes.add('deleteMetas');
    for (final MapEntry(:key, :value) in keys.entries) {
      mangas[key]!.meta.removeWhere((name, _) => value.contains(name));
    }
  }

  @override
  Future<List<RemoteChapter>> updateChapters(
    List<String> chapterIds,
    ChapterPatch patch,
  ) async {
    writes.add('updateChapters');
    return [
      for (final id in chapterIds)
        if (mangas.values
                .expand((manga) => manga.chapters)
                .firstWhere((chapter) => chapter.id == id)
            case final chapter)
          _remote(
            chapter
              ..state = chapter.state.copyWith(
                read: patch.read,
                page: patch.page,
                bookmarked: patch.bookmarked,
                readAt: patch.page == null ? null : () => now,
              ),
          ),
    ];
  }
}

String _seriesId(String url) => localSeriesIdFor(
  origin: _origin,
  sourceId: _source,
  mangaId: kuchieLocatorId(url),
);

String _chapterId(String url) => kuchieLocatorId(url);

void main() {
  late Directory workspace;
  late LocalCatalog catalog;
  late SharedPreferences prefs;
  late SyncStateStore store;
  late _FakeServer server;
  late SuwayomiReachability reachability;
  late List<SyncStatus> statuses;
  late DateTime clock;
  late LocalSeriesReaderMeta readerMeta;

  SyncEngine engine() => SyncEngine(
    catalog: () async => catalog,
    store: store,
    probe: () async => reachability,
    backendAt: (_) => server,
    localSources: () async => {
      '1': SyncLocalSource(id: _source, catalogOrigin: _origin, name: 'P'),
    },
    ensureServerIdentity: (_) async => 'server-a',
    clock: () => clock,
    onStatus: statuses.add,
    readerMeta: readerMeta,
  );

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('kuchie-sync-engine');
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = SyncStateStore(prefs);
    readerMeta = LocalSeriesReaderMeta(
      prefs,
      onChanged: catalog.recordReaderMetaChange,
    );
    await store.setConnectChoice(ConnectChoice.merge);
    server = _FakeServer();
    reachability = const SuwayomiReachable('http://server', 'server-a');
    statuses = [];
    clock = DateTime.utc(2026, 11, 1, 12);
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  Future<void> addLocal(
    String url, {
    List<String> categories = const [],
  }) async {
    await catalog.setInLibrary(
      seriesId: _seriesId(url),
      title: 'Local $url',
      inLibrary: true,
      source: LocalSeriesSource(
        sourceId: _source,
        mangaId: kuchieLocatorId(url),
        locator: url,
      ),
    );
    if (categories.isNotEmpty) {
      for (final name in categories) {
        await catalog.createCategory(name);
      }
      await catalog.setCategories(_seriesId(url), categories);
    }
  }

  Future<void> readHere(String series, String chapter, int page) async {
    final local = (await catalog.syncSeries()).firstWhere(
      (entry) => entry.id == _seriesId(series),
    );
    await catalog.recordRemoteRead(
      series: LocalSeries(id: local.id, title: local.title, chapters: const []),
      chapterId: _chapterId(chapter),
      chapterTitle: chapter,
      progress: page,
    );
  }

  Future<ChapterState?> stateHere(String series, String chapter) async =>
      (await catalog.syncChapterStates(_seriesId(series)))[_chapterId(chapter)];

  Future<Set<String>> libraryHere() async => {
    for (final series in await catalog.syncSeries())
      if (series.inLibrary) series.id,
  };

  group('first sync (scenario 1)', () {
    test('an empty iPhone copies the server library', () async {
      final manga = server.addManga('/a');
      server.addChapter(manga, '/a/1').state = ChapterState(
        read: true,
        page: 4,
        readAt: DateTime.utc(2026, 10, 1),
      );
      final report = await engine().sync();
      expect(report.outcome, SyncOutcome.synced);
      expect(await libraryHere(), {_seriesId('/a')});
      final series = (await catalog.syncSeries()).single;
      expect(series.title, 'Title /a');
      expect(series.source?.locator, '/a');
      expect(
        await stateHere('/a', '/a/1'),
        ChapterState(read: true, page: 4, readAt: DateTime.utc(2026, 10, 1)),
      );
      expect(server.writes, isEmpty);
      expect(store.method, SyncMethod.suwayomi);
      expect(store.serverIdentity, 'server-a');
      expect(statuses.last, SyncIdle(lastSuccessAt: clock));
    });

    test('an empty server gets the iPhone library it already knows', () async {
      server.addManga('/a', inLibrary: false);
      await addLocal('/a');
      await engine().sync();
      expect(server.mangas.values.single.inLibrary, isTrue);
      expect(server.writes, ['setInLibrary']);
    });

    test('a series the server never saw is created there', () async {
      await addLocal('/new');
      final report = await engine().sync();
      expect(report.seriesErrors, isEmpty);
      expect(server.writes, ['createSeries']);
      final created = server.mangas.values.single;
      expect((created.url, created.inLibrary), ('/new', true));
    });

    test('one the server cannot create reports why and stays here', () async {
      server.canCreate = false;
      await addLocal('/new');
      final report = await engine().sync();
      expect(report.seriesErrors, {
        _seriesId('/new'): SyncSeriesError.notOnServer,
      });
      expect(await libraryHere(), {_seriesId('/new')});
    });

    test('merge keeps both libraries', () async {
      await addLocal('/a');
      server.addManga('/a', inLibrary: false);
      server.addManga('/b');
      await engine().sync();
      expect(await libraryHere(), {_seriesId('/a'), _seriesId('/b')});
      expect(server.mangas.values.every((manga) => manga.inLibrary), isTrue);
    });

    test('use the server library: the iPhone follows the server', () async {
      await store.setConnectChoice(ConnectChoice.useServer);
      await addLocal('/a');
      await readHere('/a', '/a/1', 3);
      final a = server.addManga('/a');
      server.addChapter(a, '/a/1');
      server.addManga('/b');
      await addLocal('/only-here');
      await engine().sync();
      expect(await libraryHere(), {_seriesId('/a'), _seriesId('/b')});
      expect((await stateHere('/a', '/a/1'))?.page, 0);
      expect(server.writes, isEmpty);
    });

    test('use the iPhone library: the server follows the iPhone', () async {
      await store.setConnectChoice(ConnectChoice.useLocal);
      await addLocal('/a');
      await readHere('/a', '/a/1', 3);
      final a = server.addManga('/a');
      server.addChapter(a, '/a/1');
      server.addManga('/b');
      await engine().sync();
      expect(await libraryHere(), {_seriesId('/a')});
      expect(server.mangas.values.where((m) => m.inLibrary).map((m) => m.url), [
        '/a',
      ]);
      expect(server.chapter('/a/1').state.page, 3);
    });
  });

  group('after the first sync', () {
    late _Manga a;

    setUp(() async {
      a = server.addManga('/a');
      server
        ..addChapter(a, '/a/1')
        ..addChapter(a, '/a/2');
      await addLocal('/a');
      await engine().sync();
      server.writes.clear();
      clock = clock.add(const Duration(hours: 1));
    });

    test('syncing twice without changes sends and writes nothing', () async {
      final first = await engine().sync(manual: true);
      final second = await engine().sync(manual: true);
      expect(first.pushed + first.pulled, 0);
      expect(second.pushed + second.pulled, 0);
      expect(server.writes, isEmpty);
    });

    test('a read here reaches the server (scenario 2)', () async {
      await readHere('/a', '/a/1', 5);
      final report = await engine().sync();
      expect(report.pushed, 1);
      expect(server.chapter('/a/1').state.page, 5);
      // The server's own read time does not come back as a new read.
      final again = await engine().sync(manual: true);
      expect(again.pushed + again.pulled, 0);
    });

    test('a read on the server reaches the iPhone (scenario 3)', () async {
      server.chapter('/a/2').state = ChapterState(
        read: true,
        page: 7,
        readAt: DateTime.utc(2026, 11, 1, 12, 30),
      );
      await engine().sync(manual: true);
      expect(
        await stateHere('/a', '/a/2'),
        ChapterState(
          read: true,
          page: 7,
          readAt: DateTime.utc(2026, 11, 1, 12, 30),
        ),
      );
      expect(server.writes, isEmpty);
    });

    test('marking unread here clears it on the server (scenario 4)', () async {
      server.chapter('/a/1').state = ChapterState(
        read: true,
        readAt: DateTime.utc(2026, 11, 1, 12, 30),
      );
      await engine().sync(manual: true);
      server.writes.clear();
      await catalog.setChapterMarks(_seriesId('/a'), [
        _chapterId('/a/1'),
      ], read: false);
      await engine().sync();
      expect(server.chapter('/a/1').state.read, isFalse);
      expect(server.writes, ['updateChapters']);
    });

    test(
      'removed on the server while read here: reading wins (scenario 5)',
      () async {
        a.inLibrary = false;
        clock = clock.add(const Duration(minutes: 1));
        await readHere('/a', '/a/1', 2);
        // History times are the real clock's; the last sync was earlier.
        await prefs.setInt(
          SyncStateStore.lastSuccessAtKey,
          DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
        );
        await engine().sync();
        expect(await libraryHere(), {_seriesId('/a')});
        expect(a.inLibrary, isTrue);
      },
    );

    test('removed on the server without reading here: it leaves', () async {
      a.inLibrary = false;
      await engine().sync(manual: true);
      expect(await libraryHere(), isEmpty);
    });

    test('categories move both ways (scenario 6)', () async {
      await catalog.createCategory('Action');
      await catalog.setCategories(_seriesId('/a'), ['Action']);
      await engine().sync();
      final action = server.categoryNames.entries.single;
      expect(action.value, 'Action');
      expect(a.categories, {action.key});

      final drama = server.addCategory('Drama');
      a.categories.add(drama);
      await engine().sync(manual: true);
      expect((await catalog.syncSeries()).single.categories.toSet(), {
        'Action',
        'Drama',
      });
    });

    test('rating and tags from Server mode come here and turn the kind on '
        '(scenario 8)', () async {
      expect(store.includes(SyncDataKind.seriesMeta), isFalse);
      a.meta
        ..['flutter_rating'] = '4'
        ..['flutter_tags'] = '["Reread","Favourite"]';
      await engine().sync(manual: true);
      final meta = await catalog.seriesMeta(_seriesId('/a'));
      expect(meta.rating, 4);
      expect(meta.tags, ['Reread', 'Favourite']);
      expect(server.writes, isEmpty);
      expect(store.includes(SyncDataKind.seriesMeta), isTrue);
    });

    test(
      'notes here reach the server; clearing them deletes the key',
      () async {
        await store.setIncludes(SyncDataKind.seriesMeta, true);
        await catalog.setNotes(_seriesId('/a'), 'Read the side story first');
        await engine().sync();
        expect(a.meta['kuchie_notes'], 'Read the side story first');
        await catalog.setNotes(_seriesId('/a'), '');
        await engine().sync();
        expect(a.meta, isNot(contains('kuchie_notes')));
        final quiet = await engine().sync(manual: true);
        expect(quiet.pushed + quiet.pulled, 0);
      },
    );

    test('reader settings merge per key; other clients keep theirs '
        '(scenario 7)', () async {
      a.meta['webUI_readerLayout'] = 'double';
      a.meta['flutter_readerPadding'] = '0.1';
      await readerMeta.patch(_seriesId('/a'), 'flutter_readerMode', 'webtoon');
      await engine().sync();
      expect(a.meta, {
        'webUI_readerLayout': 'double',
        'flutter_readerPadding': '0.1',
        'flutter_readerMode': 'webtoon',
      });
      expect(readerMeta.read(_seriesId('/a')), {
        'flutter_readerMode': 'webtoon',
        'flutter_readerPadding': '0.1',
      });
      await readerMeta.patch(_seriesId('/a'), 'flutter_readerMode', null);
      await engine().sync();
      expect(a.meta, isNot(contains('flutter_readerMode')));
      expect(a.meta['webUI_readerLayout'], 'double');
    });

    test('a turned-off kind stays out of the merge', () async {
      await store.setIncludes(SyncDataKind.progress, false);
      await readHere('/a', '/a/1', 5);
      server.chapter('/a/2').state = ChapterState(
        page: 9,
        readAt: DateTime.utc(2026, 11, 1, 12, 30),
      );
      await engine().sync(manual: true);
      expect(server.chapter('/a/1').state.page, 0);
      expect(await stateHere('/a', '/a/2'), isNull);
    });
  });

  group('pauses (scenarios 12–14)', () {
    test('a reset server pauses sync and asks', () async {
      await store.setServerIdentity('server-a');
      reachability = const SuwayomiReachable('http://server', 'server-b');
      final report = await engine().sync();
      expect(report.outcome, SyncOutcome.actionNeeded);
      expect(
        statuses.last,
        const SyncActionNeeded(SyncActionReason.serverChanged),
      );
    });

    test('an expired login asks to sign in again', () async {
      reachability = const SuwayomiAuthFailed('http://server');
      final report = await engine().sync();
      expect(report.outcome, SyncOutcome.actionNeeded);
      expect(
        statuses.last,
        const SyncActionNeeded(SyncActionReason.loginExpired),
      );
    });

    test('an Unauthorized answer mid-cycle asks to sign in too', () async {
      final failing = _UnauthorizedServer();
      final report = await SyncEngine(
        catalog: () async => catalog,
        store: store,
        probe: () async => reachability,
        backendAt: (_) => failing,
        localSources: () async => const {},
        ensureServerIdentity: (_) async => 'server-a',
        onStatus: statuses.add,
      ).sync();
      expect(report.outcome, SyncOutcome.actionNeeded);
    });

    test('with sync off nothing runs', () async {
      await store.forgetServer();
      final report = await engine().sync();
      expect(report.outcome, SyncOutcome.skipped);
      expect(statuses, [const SyncOff()]);
    });
  });

  test('an unreachable server backs off; a manual sync tries anyway', () async {
    reachability = const SuwayomiUnreachable();
    final sync = engine();
    expect((await sync.sync()).outcome, SyncOutcome.unreachable);
    expect(statuses.last, isA<SyncWaitingForServer>());
    expect((await sync.sync()).outcome, SyncOutcome.skipped);
    clock = clock.add(const Duration(minutes: 2));
    expect((await sync.sync()).outcome, SyncOutcome.unreachable);
    clock = clock.add(const Duration(minutes: 2));
    expect((await sync.sync()).outcome, SyncOutcome.skipped);
    reachability = const SuwayomiReachable('http://server', 'server-a');
    expect((await sync.sync(manual: true)).outcome, SyncOutcome.synced);
  });

  test('a trigger during a cycle runs one more after it', () async {
    final sync = engine();
    final first = sync.sync();
    final second = sync.sync();
    expect(identical(await first, await second), isTrue);
    // The first cycle and the rerun it was asked for.
    expect(statuses.whereType<SyncInProgress>(), hasLength(2));
  });

  test('each cycle lands in the log; series errors are kept', () async {
    reachability = const SuwayomiUnreachable();
    await engine().sync();
    reachability = const SuwayomiReachable('http://server', 'server-a');
    server.canCreate = false;
    await addLocal('/new');
    await engine().sync(manual: true);
    expect(store.log.map((entry) => entry.outcome), ['synced', 'unreachable']);
    expect(store.log.first.seriesErrors, 1);
    expect(store.seriesErrors, {_seriesId('/new'): 'notOnServer'});
  });

  test('pushed changes leave the outbox; failed ones stay', () async {
    server.addManga('/a');
    await addLocal('/a');
    await engine().sync();
    final journal = SyncJournal(catalog);
    await readHere('/a', '/a/1', 1);
    expect(await journal.pending(), isNotEmpty);
    await engine().sync();
    expect(await journal.pending(), isEmpty);

    server.canCreate = false;
    await addLocal('/new');
    await engine().sync();
    expect(await journal.pending(), isNotEmpty);
  });
}

class _UnauthorizedServer extends _FakeServer {
  @override
  Future<List<RemoteSeries>> library() async => throw OperationException(
    graphqlErrors: [const GraphQLError(message: 'Unauthorized')],
  );
}
