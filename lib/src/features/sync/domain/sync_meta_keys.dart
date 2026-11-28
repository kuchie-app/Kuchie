import 'dart:convert';

import 'sync_records.dart';

// The manga meta keys Sync reads and writes on a Suwayomi server. Rating
// and tags use the keys Kuchie's Server mode already wrote, so that data
// comes back as it was (design 2); notes are new.

const ratingMetaKey = 'flutter_rating';
const tagsMetaKey = 'flutter_tags';
const notesMetaKey = 'kuchie_notes';

/// Per-series reader settings Kuchie owns: the `MangaMetaKeys` the Local
/// reader stores, without rating, tags and the server's cover. Other keys
/// (WebUI's, other clients') are never changed or deleted.
/// test/src/features/sync/domain/sync_meta_keys_test.dart keeps it in step
/// with `MangaMetaKeys`.
const readerMetaKeys = {
  'flutter_readerNavigationLayoutInvert',
  'flutter_readerNavigationLayout',
  'flutter_readerMode',
  'flutter_readerPadding',
  'flutter_readerOrientation',
  'flutter_readerTapInvert',
  'webUI_shouldOffsetDoubleSpreads',
  'flutter_scanlator',
  'flutter_chapterListMode',
  'flutter_preferredScanlators',
  'flutter_chapterSortIsAlphabetical',
};

bool ownsReaderMetaKey(String key) => readerMetaKeys.contains(key);

/// Rating, tags and notes as the server keeps them in [meta].
SeriesMeta seriesMetaFromServer(Map<String, String> meta) => SeriesMeta(
  rating: switch (int.tryParse(meta[ratingMetaKey] ?? '')) {
    final int rating when rating > 0 && rating <= 5 => rating,
    _ => null,
  },
  tags: _tags(meta[tagsMetaKey]),
  notes: switch (meta[notesMetaKey]) {
    final String notes when notes.isNotEmpty => notes,
    _ => null,
  },
);

/// The server values for [meta]: null deletes a key.
Map<String, String?> seriesMetaToServer(SeriesMeta meta) => {
  ratingMetaKey: meta.rating == null ? null : '${meta.rating}',
  tagsMetaKey: meta.tags.isEmpty ? null : jsonEncode(meta.tags),
  notesMetaKey: meta.notes,
};

List<String> _tags(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  try {
    return switch (jsonDecode(encoded)) {
      final List<Object?> tags => [for (final tag in tags) ?tag as String?],
      _ => const [],
    };
  } on FormatException {
    return const [];
  } on TypeError {
    return const [];
  }
}
