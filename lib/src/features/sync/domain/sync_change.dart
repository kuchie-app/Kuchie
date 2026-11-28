import 'dart:convert';

// Names of the rows the catalog keeps for sync (`sync_changes`, `sync_links`,
// `sync_base`, `sync_transfers`) and the keys they use. The names are stored,
// so they must never change.

/// What a journal entry or an agreed base value is about.
enum SyncRecordKind {
  series('series'),
  chapterState('chapter_state'),
  category('category'),
  membership('membership'),
  seriesMeta('series_meta'),
  readerMeta('reader_meta'),
  appSetting('app_setting');

  const SyncRecordKind(this.storedName);

  final String storedName;

  static SyncRecordKind? parse(String name) =>
      values.where((kind) => kind.storedName == name).firstOrNull;
}

enum SyncChangeOp {
  upsert,
  delete;

  static SyncChangeOp? parse(String name) =>
      values.where((op) => op.name == name).firstOrNull;
}

/// What a local key is linked to on a backend.
enum SyncLinkKind {
  series,
  chapter,
  category;

  static SyncLinkKind? parse(String name) =>
      values.where((kind) => kind.name == name).firstOrNull;
}

/// One outbox entry: [key] of [kind] changed locally at [changedAt].
class SyncChange {
  const SyncChange({
    required this.seq,
    required this.kind,
    required this.key,
    required this.op,
    required this.changedAt,
  });

  /// Increases with every entry, so entries up to a pushed one can be trimmed.
  final int seq;
  final SyncRecordKind kind;

  /// A series id, a [categoryKey], or a [chapterStateKey].
  final String key;
  final SyncChangeOp op;
  final DateTime changedAt;

  @override
  bool operator ==(Object other) =>
      other is SyncChange &&
      other.seq == seq &&
      other.kind == kind &&
      other.key == key &&
      other.op == op &&
      other.changedAt == changedAt;

  @override
  int get hashCode => Object.hash(seq, kind, key, op, changedAt);

  @override
  String toString() =>
      'SyncChange($seq, ${kind.storedName}, $key, ${op.name}, $changedAt)';
}

/// The key of a chapter's reading state. Series and chapter ids may hold any
/// character, so the pair is stored as a JSON array.
String chapterStateKey(String seriesId, String chapterId) =>
    jsonEncode([seriesId, chapterId]);

/// The series and chapter ids in a [chapterStateKey], or null if [key] is not
/// one.
(String seriesId, String chapterId)? parseChapterStateKey(String key) {
  try {
    if (jsonDecode(key) case [final String seriesId, final String chapterId]) {
      return (seriesId, chapterId);
    }
  } on FormatException {
    // Not a chapter key.
  }
  return null;
}
