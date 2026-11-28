import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/controller/extension_sync.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_backend.dart';

ServerExtension _ext(
  String package, {
  bool installed = true,
  String store = 'https://k/index.pb',
}) => ServerExtension(
  package: package,
  name: package.split('.').last,
  language: 'en',
  installed: installed,
  storeIndexUrl: store,
);

void main() {
  test('extensions are compared both ways (design 3.5)', () {
    final suggestions = compareExtensions(
      server: [
        _ext('a.mangadex'),
        _ext('a.weeb'),
        _ext('a.asura', installed: false),
      ],
      here: {'a.mangadex', 'a.asura', 'a.private'},
    );
    expect(suggestions.onlyOnServer.map((e) => e.package), ['a.weeb']);
    expect(suggestions.onlyHere.map((e) => e.package), ['a.asura']);
    expect(suggestions.notInServerStores, ['a.private']);
    expect(suggestions.isEmpty, isFalse);
  });

  test('matching extensions suggest nothing', () {
    expect(
      compareExtensions(
        server: [_ext('a.mangadex')],
        here: {'a.mangadex'},
      ).isEmpty,
      isTrue,
    );
  });

  test('a fresh iPhone is offered the server stores and its extensions, '
      'most series first', () {
    final suggestions = compareExtensions(
      server: [
        _ext('a.small'),
        _ext('a.big'),
        _ext('b.other', store: 'https://y/index.pb'),
      ],
      here: const {},
      serverStores: const [
        ServerStore(indexUrl: 'https://k/index.pb', signingKey: 'k', name: 'K'),
        ServerStore(indexUrl: 'https://y/index.pb', signingKey: 'y', name: 'Y'),
        ServerStore(indexUrl: 'https://z/index.pb', signingKey: 'z', name: 'Z'),
      ],
      storeKeysHere: const {'y'},
      seriesByPackage: const {'a.big': 500, 'a.small': 3, 'b.other': 40},
    );
    expect(suggestions.onlyOnServer.map((e) => e.package), [
      'a.big',
      'b.other',
      'a.small',
    ]);
    expect(suggestions.seriesWaiting, 543);
    // Y is here under another key-matched URL; Z serves nothing needed.
    expect(suggestions.storesToAdd.map((store) => store.name), ['K']);
  });

  test('series whose source the server lost are resolved by store, or '
      'reported', () {
    final suggestions = compareExtensions(
      server: [_ext('a.big'), _ext('a.lost', installed: false)],
      here: const {'a.here'},
      seriesByPackage: const {'a.big': 5},
      orphanSeries: const {'11': 18, '12': 4, '13': 2, '99': 3},
      packagesBySource: const {
        '11': (package: 'a.lost', name: 'Lost', language: 'id'),
        '12': (package: 'a.gone', name: 'Gone', language: 'en'),
        '13': (package: 'a.here', name: 'Here', language: 'en'),
      },
    );
    expect(suggestions.missingEverywhere.map((e) => e.package), [
      'a.lost',
      'a.gone',
    ]);
    // Installed here already: the iPhone reads them, nothing to install.
    expect(suggestions.toInstall.map((e) => e.package), [
      'a.big',
      'a.lost',
      'a.gone',
    ]);
    expect(suggestions.seriesWaiting, 27);
    expect(suggestions.unknownSources, {'99': 3});
    expect(suggestions.seriesUnknown, 3);
  });

  test('Shinigami on the server is offered for the built-in adapter', () {
    final suggestions = compareExtensions(
      server: [_ext('eu.kanade.tachiyomi.extension.id.shinigami')],
      here: const {},
    );
    expect(suggestions.toInstall, hasLength(1));
  });
}
