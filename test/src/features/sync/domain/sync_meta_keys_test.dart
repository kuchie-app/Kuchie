import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:kuchie/src/features/sync/domain/sync_meta_keys.dart';
import 'package:kuchie/src/features/sync/domain/sync_records.dart';

void main() {
  test('Sync owns every reader key the Local reader can store', () {
    expect(readerMetaKeys, {
      for (final key in MangaMetaKeys.values)
        if (key != MangaMetaKeys.rating &&
            key != MangaMetaKeys.tags &&
            key != MangaMetaKeys.customCover)
          key.key,
    });
    expect(ratingMetaKey, MangaMetaKeys.rating.key);
    expect(tagsMetaKey, MangaMetaKeys.tags.key);
  });

  test('series meta reads and writes the server format', () {
    const meta = SeriesMeta(rating: 3, tags: ['A', 'B'], notes: 'n');
    final server = seriesMetaToServer(meta);
    expect(server, {
      'flutter_rating': '3',
      'flutter_tags': '["A","B"]',
      'kuchie_notes': 'n',
    });
    expect(seriesMetaFromServer(server.cast()), meta);
    expect(seriesMetaToServer(const SeriesMeta()), {
      'flutter_rating': null,
      'flutter_tags': null,
      'kuchie_notes': null,
    });
    expect(
      seriesMetaFromServer({'flutter_rating': '0', 'flutter_tags': 'oops'}),
      const SeriesMeta(),
    );
  });
}
