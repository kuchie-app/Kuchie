import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kuchie/src/features/local_collection/data/local_catalog.dart';
import 'package:kuchie/src/features/local_collection/data/local_collection_providers.dart';
import 'package:kuchie/src/features/local_collection/data/local_series_reader_meta.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/manga_book/presentation/reader/controller/reader_settings_model.dart';
import 'package:kuchie/src/features/sync/data/sync_journal.dart';
import 'package:kuchie/src/features/sync/domain/sync_change.dart';
import 'package:kuchie/src/global_providers/global_providers.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late Directory workspace;
  late LocalCatalog catalog;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'local.reader.manga.old': jsonEncode({'flag': 'true'}),
      'local.reader.manga.broken': '{not json',
    });
    prefs = await SharedPreferences.getInstance();
    workspace = await Directory.systemTemp.createTemp('kuchie-reader-meta');
    catalog = LocalCatalog(Directory(p.join(workspace.path, 'catalog')));
  });

  tearDown(() async {
    await catalog.close();
    await workspace.delete(recursive: true);
  });

  Future<List<(SyncRecordKind, String)>> entries() async => [
    for (final change in await SyncJournal(catalog).pending())
      (change.kind, change.key),
  ];

  test('keeps the stored format of older versions', () async {
    final meta = LocalSeriesReaderMeta(prefs);
    expect(meta.read('old'), {'flag': 'true'});
    expect(meta.read('broken'), isEmpty);
    expect(meta.read('missing'), isEmpty);

    expect(await meta.patch('old', 'scale', 2), {'flag': 'true', 'scale': '2'});
    expect(jsonDecode(prefs.getString('local.reader.manga.old')!), {
      'flag': 'true',
      'scale': '2',
    });
    expect(await meta.patch('old', 'flag', null), {'scale': '2'});
    expect(meta.read('old'), {'scale': '2'});
  });

  test('tells the journal after the values are saved', () async {
    final calls = <String>[];
    late final LocalSeriesReaderMeta meta;
    meta = LocalSeriesReaderMeta(
      prefs,
      onChanged: (seriesId) {
        expect(meta.read(seriesId), {'scale': '1'});
        calls.add(seriesId);
      },
    );
    await meta.patch('s', 'scale', 1);
    expect(calls, ['s']);
  });

  test('a patch records one reader_meta change while sync is on', () async {
    final meta = LocalSeriesReaderMeta(
      prefs,
      onChanged: catalog.recordReaderMetaChange,
    );
    await meta.patch('s', 'scale', 1);
    expect(await entries(), isEmpty);

    catalog.journalEnabled = true;
    await meta.patch('s', 'scale', 2);
    expect(await entries(), [(SyncRecordKind.readerMeta, 's')]);

    await runApplyingRemote(() => meta.patch('s', 'scale', 3));
    expect(await entries(), hasLength(1));
    expect(meta.read('s'), {'scale': '3'});
  });

  group('provider', () {
    ProviderContainer container() {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('saves without opening the Local collection', () async {
      final c = container();
      await c.read(localSeriesReaderMetaProvider).patch('s', 'scale', 1);
      expect(c.read(activeLocalCatalogProvider), isNull);
      expect(c.read(localSeriesReaderMetaProvider).read('s'), {'scale': '1'});
    });

    test(
      'the reader settings sheet records changes in the open catalog',
      () async {
        final c = container();
        catalog.journalEnabled = true;
        c.read(activeLocalCatalogProvider.notifier).attach(catalog);
        final settings = readerSettingsModelProvider(0, localSeriesId: 's');
        final lock = c.listen(settings, (_, _) {});
        addTearDown(lock.close);

        await c.read(settings.notifier).setOffsetDoublePages(true);

        expect(c.read(settings).offsetDoublePages, isTrue);
        expect(LocalSeriesReaderMeta(prefs).read('s'), {
          MangaMetaKeys.offsetDoublePages.key: 'true',
        });
        expect(await entries(), [(SyncRecordKind.readerMeta, 's')]);
      },
    );
  });
}
