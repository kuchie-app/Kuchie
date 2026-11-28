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
}
