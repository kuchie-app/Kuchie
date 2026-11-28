// The sync engine (PR 8) against a real Suwayomi server.
//
// Start a fresh QA server, then run:
//
//   python3 tool/qa/server.py --jar <Suwayomi JAR> --java <java 21>
//   KUCHIE_QA_SERVER=http://127.0.0.1:14567 \
//     flutter test tool/qa/sync_spike/sync_engine_qa_test.dart
//
// It uses the server's local source (id 0) and the three series
// `server.py` seeds, so it needs no extension or network. It writes to the
// server, so run it once per fresh server.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_services.dart';
import 'package:kuchie/src/features/offline/data/offline_server_identity_repository.dart';
import 'package:kuchie/src/features/sync/controller/sync_engine.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_backend.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_identity.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_reachability.dart';
import 'package:kuchie/src/features/sync/data/sync_state_store.dart';
import 'package:kuchie/src/features/sync/domain/sync_records.dart';
import 'package:kuchie/src/utils/graphql/legacy_user_fields_link.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final _server = Platform.environment['KUCHIE_QA_SERVER'];
final _origin = Uri.parse('https://qa.kuchie.local');
const _source = 'local:0';

void main() {
  test(
    'two-way sync against the QA server',
    timeout: const Timeout(Duration(minutes: 5)),
    skip: _server == null
        ? 'Set KUCHIE_QA_SERVER to a fresh QA server.'
        : false,
    () async {
      final client = GraphQLClient(
        link: LegacyUserFieldsLink().concat(HttpLink('$_server/api/graphql')),
        cache: GraphQLCache(),
        defaultPolicies: DefaultPolicies(
          query: Policies(fetch: FetchPolicy.noCache),
          mutate: Policies(fetch: FetchPolicy.noCache),
        ),
      );
      Future<Map<String, dynamic>> request(
        String document, [
        Map<String, dynamic> variables = const {},
      ]) async {
        final result = await client.query(
          QueryOptions(
            document: gql(document),
            variables: variables,
            fetchPolicy: FetchPolicy.noCache,
          ),
        );
        if (result.hasException) throw result.exception!;
        return result.data!;
      }

      // The server side, as WebUI would see it.
      final seeded = await request('''
        mutation { fetchSourceManga(input: {source: "0", type: POPULAR, page: 1}) {
          mangas { id url } } }
      ''');
      final ids = {
        for (final manga
            in seeded['fetchSourceManga']['mangas'] as List<dynamic>)
          manga['url'] as String: '${manga['id']}',
      };
      final lantern = ids['QA - Lantern Station']!;
      final paper = ids['QA - Paper Signal']!;
      Future<List<Map<String, dynamic>>> chapters(String mangaId) async {
        await request(
          'mutation(\$id: Int!) { fetchMangaAndChapters(input: {id: \$id, '
          'fetchManga: true, fetchChapters: true}) { manga { id } } }',
          {'id': int.parse(mangaId)},
        );
        final data = await request(
          'query(\$id: Int!) { chapters(condition: {mangaId: \$id}, '
          'order: [{by: SOURCE_ORDER, byType: ASC}]) { nodes { id url '
          'user { isRead isBookmarked lastPageRead lastReadAt } } } }',
          {'id': int.parse(mangaId)},
        );
        return (data['chapters']['nodes'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }

      Future<Map<String, dynamic>> chapterOnServer(
        String mangaId,
        String url,
      ) async =>
          (await chapters(mangaId)).firstWhere((c) => c['url'] == url)['user']
              as Map<String, dynamic>;

      Future<bool> inServerLibrary(String mangaId) async =>
          (await request(
                'query(\$id: Int!) { manga(id: \$id) { user { inLibrary } } }',
                {'id': int.parse(mangaId)},
              ))['manga']['user']['inLibrary']
              as bool;

      // The server has Lantern Station, with chapter 1 read to page 5.
      final lanternChapters = await chapters(lantern);
      final lantern1 = lanternChapters[0], lantern2 = lanternChapters[1];
      await request(
        'mutation(\$ids: [Int!]!) { updateMangas(input: {ids: \$ids, '
        'patch: {inLibrary: true}}) { clientMutationId } }',
        {
          'ids': [int.parse(lantern)],
        },
      );
      // Opened once, so the server keeps its page (spike S2).
      await request(
        'mutation(\$id: Int!) { fetchChapterPages(input: {chapterId: \$id}) '
        '{ pages } }',
        {'id': lantern1['id']},
      );
      await request(
        'mutation(\$ids: [Int!]!) { updateChapters(input: {ids: \$ids, '
        'patch: {isRead: true, lastPageRead: 5}}) { clientMutationId } }',
        {
          'ids': [lantern1['id']],
        },
      );

      // This iPhone has Paper Signal, which the server has outside its
      // library.
      final workspace = await Directory.systemTemp.createTemp('kuchie-qa-sync');
      addTearDown(() => workspace.delete(recursive: true));
      final catalog = LocalCatalog(Directory(p.join(workspace.path, 'c')));
      addTearDown(catalog.close);
      String seriesId(String url) => localSeriesIdFor(
        origin: _origin,
        sourceId: _source,
        mangaId: kuchieLocatorId(url),
      );
      await catalog.setInLibrary(
        seriesId: seriesId('QA - Paper Signal'),
        title: 'QA - Paper Signal',
        inLibrary: true,
        source: LocalSeriesSource(
          sourceId: _source,
          mangaId: kuchieLocatorId('QA - Paper Signal'),
          locator: 'QA - Paper Signal',
        ),
      );

      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final store = SyncStateStore(await SharedPreferences.getInstance());
      await store.setConnectChoice(ConnectChoice.merge);
      final identity = OfflineServerIdentityRepository(client);
      final engine = SyncEngine(
        catalog: () async => catalog,
        store: store,
        probe: () => SuwayomiReachabilityProbe(
          addresses: [_server!],
          readIdentity: (_) => identity.read(),
          expectedIdentity: store.serverIdentity,
        ).probe(),
        backendAt: (_) => SuwayomiBackend(client),
        localSources: () async => {
          '0': SyncLocalSource(
            id: _source,
            catalogOrigin: _origin,
            name: 'Local',
          ),
        },
        ensureServerIdentity: (_) => identity.resolve(),
      );
      Future<SyncReport> sync({bool manual = false}) async {
        final report = await engine.sync(manual: manual);
        // ignore: avoid_print
        print(report);
        expect(report.outcome, SyncOutcome.synced);
        expect(report.seriesErrors, isEmpty);
        return report;
      }

      Future<ChapterState?> stateHere(String series, String chapterUrl) async =>
          (await catalog.syncChapterStates(seriesId(series)))[kuchieLocatorId(
            chapterUrl,
          )];

      // 1. First sync, merge: each side gets the other's series.
      await sync();
      expect(store.serverIdentity, isNotNull);
      expect(await inServerLibrary(paper), isTrue);
      final here = {
        for (final series in await catalog.syncSeries())
          if (series.inLibrary) series.id,
      };
      expect(here, {
        seriesId('QA - Lantern Station'),
        seriesId('QA - Paper Signal'),
      });
      final pulled = await stateHere(
        'QA - Lantern Station',
        lantern1['url'] as String,
      );
      expect(pulled?.read, isTrue);
      expect(pulled?.page, 5);
      expect(pulled?.readAt, isNotNull);

      // 2. Read here; it reaches the server, even on a chapter the server
      // never opened (spike S2).
      final paper1 = (await chapters(paper)).first;
      final series = await catalog.find(seriesId('QA - Paper Signal'));
      await catalog.recordRemoteRead(
        series: series!,
        chapterId: kuchieLocatorId(paper1['url'] as String),
        chapterTitle: 'Chapter 01',
        progress: 7,
      );
      await sync();
      expect(
        (await chapterOnServer(paper, paper1['url'] as String))['lastPageRead'],
        7,
      );

      // 3. Nothing changed: nothing is sent or written, both ways.
      for (var i = 0; i < 2; i++) {
        final quiet = await sync(manual: true);
        expect(quiet.pushed + quiet.pulled, 0, reason: 'cycle ${i + 1}');
      }

      // 4. Read on the server; it reaches this iPhone.
      await request(
        'mutation(\$ids: [Int!]!) { updateChapters(input: {ids: \$ids, '
        'patch: {isRead: true, isBookmarked: true}}) { clientMutationId } }',
        {
          'ids': [lantern2['id']],
        },
      );
      await sync(manual: true);
      final marked = await stateHere(
        'QA - Lantern Station',
        lantern2['url'] as String,
      );
      expect(marked?.read, isTrue);
      expect(marked?.bookmarked, isTrue);

      // 5. Unread here; the server follows.
      await catalog.setChapterMarks(seriesId('QA - Lantern Station'), [
        kuchieLocatorId(lantern1['url'] as String),
      ], read: false);
      await sync();
      expect(
        (await chapterOnServer(lantern, lantern1['url'] as String))['isRead'],
        isFalse,
      );

      // 6. A category here appears on the server with its series.
      await catalog.createCategory('QA Action');
      await catalog.setCategories(seriesId('QA - Lantern Station'), [
        'QA Action',
      ]);
      await sync();
      final onServer = await request(
        'query(\$id: Int!) { manga(id: \$id) { categories { nodes { name } } } }',
        {'id': int.parse(lantern)},
      );
      expect(
        [
          for (final node
              in onServer['manga']['categories']['nodes'] as List<dynamic>)
            node['name'],
        ],
        ['QA Action'],
      );

      // 7. Removed on the server, not read here since: it leaves here too.
      await request(
        'mutation(\$ids: [Int!]!) { updateMangas(input: {ids: \$ids, '
        'patch: {inLibrary: false}}) { clientMutationId } }',
        {
          'ids': [int.parse(paper)],
        },
      );
      await sync(manual: true);
      expect(
        (await catalog.syncSeries())
            .firstWhere((s) => s.id == seriesId('QA - Paper Signal'))
            .inLibrary,
        isFalse,
      );
      final settled = await sync(manual: true);
      expect(settled.pushed + settled.pulled, 0);
    },
  );
}
