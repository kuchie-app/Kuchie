import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_identity.dart';

const _mangadex = 'eu.kanade.tachiyomi.extension.all.mangadex';
const _weebCentral = 'eu.kanade.tachiyomi.extension.en.weebcentral';

void main() {
  group('spike S1 libraries match by source id and URL', () {
    for (final (file, package) in [
      ('s1-2499283573021220255.json', _mangadex),
      ('s1-2131019126180322627.json', _weebCentral),
    ]) {
      test(file, () {
        final data =
            jsonDecode(
                  File('tool/qa/sync_spike/results/$file').readAsStringSync(),
                )
                as Map<String, Object?>;
        final source = data['source']! as String;
        // A popular page can list a series twice; a library can't.
        final seen = <String>{};
        final series = [
          for (final item
              in (data['series']! as List).cast<Map<String, Object?>>())
            if (seen.add(item['kuchieId']! as String)) item,
        ];
        final local = [
          for (final item in series)
            LocalSeriesRef(
              id: item['kuchieId']! as String,
              title: item['title']! as String,
              sourceId: '$package:$source',
              locator: item['kuchie']! as String,
            ),
        ];
        var nextId = 1;
        final remote = [
          for (final item in series)
            RemoteSeriesRef(
              id: nextId++,
              title: item['title']! as String,
              sourceId: source,
              url: item['kuchie']! as String,
            ),
        ];
        final match = matchSeries(
          local: local,
          remote: remote,
          serverPackages: {package},
          localSourceIds: {source},
        );
        expect(match.links, hasLength(series.length));
        expect(series.length, greaterThan(15));
        expect(match.onlyLocal, isEmpty);
        expect(match.onlyRemote, isEmpty);
      });
    }
  });

  test('parses Mihon source ids and rejects the rest', () {
    expect(parseLocalSource('$_mangadex:2499283573021220255'), (
      package: _mangadex,
      sourceId: '2499283573021220255',
    ));
    expect(parseLocalSource('pkg:-42'), (package: 'pkg', sourceId: '-42'));
    expect(parseLocalSource('pkg:99999999999999999999'), isNotNull);
    expect(parseLocalSource(builtInShinigamiPackage), isNull);
    expect(parseLocalSource('kuchie.native-catalog.v1'), isNull);
    expect(parseLocalSource('pkg:abc'), isNull);
    expect(parseLocalSource(':1'), isNull);
    expect(parseLocalSource('pkg:'), isNull);
  });

  test('stable locators drop the chapter suffix and Mangayomi memo', () {
    expect(stableLocator('/manga/1'), '/manga/1');
    expect(stableLocator('/manga/1|kuchie-chapter|eyJ9'), '/manga/1');
    expect(stableLocator('/manga/1|mangayomi-memo|x'), '/manga/1');
    expect(
      stableLocator('/manga/1|mangayomi-memo|x|kuchie-chapter|e'),
      '/manga/1',
    );
  });

  test('says why a series is only on this iPhone, and what can be sent', () {
    const sourceId = '7';
    final match = matchSeries(
      local: const [
        LocalSeriesRef(id: 'cbz', title: 'Imported'),
        LocalSeriesRef(
          id: 'repo',
          title: 'Repo',
          sourceId: 'kuchie.native-catalog.v1',
          locator: 'https://repo.example/a',
        ),
        LocalSeriesRef(
          id: 'shinigami',
          title: 'Built in',
          sourceId: builtInShinigamiPackage,
          locator: 'https://api.example/a',
        ),
        LocalSeriesRef(
          id: 'new',
          title: 'New',
          sourceId: 'pkg.a:$sourceId',
          locator: '/m/new',
        ),
        LocalSeriesRef(
          id: 'missing',
          title: 'Missing',
          sourceId: 'pkg.b:8',
          locator: '/m/x',
        ),
        LocalSeriesRef(
          id: 'both',
          title: 'Both',
          sourceId: 'pkg.a:$sourceId',
          locator: '/m/both|kuchie-chapter|e',
        ),
      ],
      remote: const [
        RemoteSeriesRef(
          id: 1,
          title: 'Both',
          sourceId: sourceId,
          url: '/m/both',
        ),
        RemoteSeriesRef(
          id: 2,
          title: 'Readable',
          sourceId: sourceId,
          url: '/m/r',
        ),
        RemoteSeriesRef(
          id: 3,
          title: 'Unreadable',
          sourceId: '99',
          url: '/m/u',
        ),
      ],
      serverPackages: {'pkg.a'},
      localSourceIds: {sourceId},
    );
    expect(match.links, {'both': 1});
    expect(
      {for (final (series, reason) in match.onlyLocal) series.id: reason},
      {
        'cbz': const ImportedFile(),
        'repo': const KuchieRepo(),
        'shinigami': const BuiltIn(),
        'new': const Sendable(),
        'missing': const ExtensionMissing('pkg.b'),
      },
    );
    expect(match.onlyLocal.where((entry) => entry.$2.sendable), hasLength(1));
    expect(
      {for (final (manga, here) in match.onlyRemote) manga.id: here},
      {2: true, 3: false},
    );
  });

  test('a server manga links to one Local series only', () {
    final match = matchSeries(
      local: const [
        LocalSeriesRef(id: 'a', title: 'A', sourceId: 'p:1', locator: '/m'),
        LocalSeriesRef(id: 'b', title: 'B', sourceId: 'p:1', locator: '/m'),
      ],
      remote: const [
        RemoteSeriesRef(id: 9, title: 'M', sourceId: '1', url: '/m'),
      ],
      serverPackages: {'p'},
      localSourceIds: {'1'},
    );
    expect(match.links, {'a': 9});
    expect(match.onlyLocal.single.$1.id, 'b');
    expect(match.onlyRemote, isEmpty);
  });
}
