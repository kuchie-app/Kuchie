import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/sync/controller/extension_sync.dart';
import 'package:kuchie/src/features/sync/data/suwayomi/suwayomi_backend.dart';

ServerExtension _ext(String package, {bool installed = true}) =>
    ServerExtension(
      package: package,
      name: package.split('.').last,
      language: 'en',
      installed: installed,
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
}
