import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/local_collection/data/package_catalog_index.dart';

typedef _Pkg = ({String id, String name, String version, String lang});

PackageCatalogIndex<_Pkg> _index(List<_Pkg> packages) => PackageCatalogIndex(
  packages,
  id: (p) => p.id,
  name: (p) => p.name,
  version: (p) => p.version,
  language: (p) => p.lang,
);

void main() {
  const packages = <_Pkg>[
    (id: 'shini', name: 'Shinigami', version: '1.4.2', lang: 'id'),
    (id: 'shini', name: 'Shinigami', version: '1.4.10', lang: 'id'),
    (id: 'kiryuu', name: 'kiryuu', version: '1.0.0', lang: 'id'),
    (id: 'asura', name: 'Asura Scans', version: '2.0.0', lang: 'en'),
    (id: 'mangadex', name: 'MangaDex', version: '1.3.0', lang: 'all'),
  ];

  test('keeps the newest version of each package, by semver', () {
    final index = _index(packages);
    expect(index.length, 4);
    expect(index['shini']!.version, '1.4.10');
  });

  test('groups by language in case-insensitive name order', () {
    final grouped = _index(packages).group(installed: {}, query: '');
    expect(grouped.updates, isEmpty);
    expect(grouped.byLanguage['id']!.map((p) => p.name), [
      'kiryuu',
      'Shinigami',
    ]);
    expect(grouped.byLanguage.keys.toSet(), {'id', 'en', 'all'});
  });

  test('installed packages show only when an update exists', () {
    final grouped = _index(
      packages,
    ).group(installed: {'shini': '1.4.2', 'asura': '2.0.0'}, query: '');
    expect(grouped.updates.map((p) => p.id), ['shini']);
    expect(grouped.byLanguage['en'], isNull);
    expect(grouped.byLanguage['id']!.map((p) => p.id), ['kiryuu']);
  });

  test('filters by trimmed, case-insensitive query and language', () {
    final index = _index(packages);
    final byQuery = index.group(installed: {}, query: '  SHINI ');
    expect(byQuery.byLanguage.values.expand((l) => l).map((p) => p.id), [
      'shini',
    ]);
    final byLanguage = index.group(
      installed: {},
      query: '',
      languageAllowed: (language) => language == 'en',
    );
    expect(byLanguage.byLanguage.keys, ['en']);
  });
}
