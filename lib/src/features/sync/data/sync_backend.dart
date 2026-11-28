import '../domain/sync_records.dart';

// What the sync engine needs from a sync target. Ids are strings so the
// journal can store any backend's; the Suwayomi backend uses its integer ids.

/// A series in the backend's library, or one it found by source and URL.
class RemoteSeries {
  const RemoteSeries({
    required this.id,
    required this.sourceId,
    required this.url,
    required this.title,
    required this.inLibrary,
    this.thumbnailUrl,
    this.inLibraryAt,
    this.categoryIds = const {},
    this.meta = const {},
  });

  final String id;

  /// The Mihon source id, as in `<package>:<source id>` on this iPhone.
  final String sourceId;

  /// The manga URL, exactly as the extension gives it (spike S1).
  final String url;
  final String title;
  final String? thumbnailUrl;
  final bool inLibrary;

  /// When it was last added to the library, if the backend knows.
  final DateTime? inLibraryAt;
  final Set<String> categoryIds;

  /// Manga meta: rating, tags, notes and reader settings among others.
  final Map<String, String> meta;
}

class RemoteCategory {
  const RemoteCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class RemoteChapter {
  const RemoteChapter({
    required this.id,
    required this.seriesId,
    required this.url,
    required this.name,
    required this.state,
  });

  final String id;
  final String seriesId;

  /// The chapter URL; Kuchie's chapter id is its SHA-256.
  final String url;
  final String name;
  final ChapterState state;
}

/// A series to create on the backend, from this iPhone's library.
class NewRemoteSeries {
  const NewRemoteSeries({
    required this.sourceId,
    required this.url,
    required this.title,
    this.sourceName = '',
  });

  final String sourceId;
  final String url;
  final String title;
  final String sourceName;
}

/// The fields of a chapter to change; null leaves one as it is.
class ChapterPatch {
  const ChapterPatch({this.read, this.page, this.bookmarked});

  final bool? read;
  final int? page;
  final bool? bookmarked;

  bool get isEmpty => read == null && page == null && bookmarked == null;

  @override
  bool operator ==(Object other) =>
      other is ChapterPatch &&
      other.read == read &&
      other.page == page &&
      other.bookmarked == bookmarked;

  @override
  int get hashCode => Object.hash(read, page, bookmarked);

  @override
  String toString() =>
      'ChapterPatch(read: $read, page: $page, bookmarked: $bookmarked)';
}

/// A sync target, such as a Suwayomi server. One instance talks to one
/// address for one cycle.
abstract interface class SyncBackend {
  /// The name its links and base values are stored under.
  String get key;

  /// Every series in the library.
  Future<List<RemoteSeries>> library();

  /// The reader's categories, without the backend's built-in default one.
  Future<List<RemoteCategory>> categories();

  /// Every chapter of [seriesId].
  Future<List<RemoteChapter>> chaptersOf(String seriesId);

  /// Chapters of [seriesIds] read after [since].
  Future<List<RemoteChapter>> chaptersReadSince(
    Set<String> seriesIds,
    DateTime since,
  );

  /// A series the backend knows by source and URL, in its library or not.
  Future<RemoteSeries?> findSeries(String sourceId, String url);

  /// Creates [series] the backend doesn't know yet and returns those it now
  /// has, in its library or not. Missing ones could not be created.
  Future<List<RemoteSeries>> createSeries(List<NewRemoteSeries> series);

  /// Loads a series' chapters from its source, for a series just added that
  /// the backend never opened. Returns them.
  Future<List<RemoteChapter>> refreshChapters(String seriesId);

  Future<void> setInLibrary(List<String> seriesIds, {required bool inLibrary});

  Future<RemoteCategory> createCategory(String name);

  Future<void> changeCategories(
    List<String> seriesIds, {
    Set<String> add = const {},
    Set<String> remove = const {},
  });

  /// Sets manga meta: series id → key → value.
  Future<void> setMetas(Map<String, Map<String, String>> metas);

  /// Deletes manga meta: series id → keys.
  Future<void> deleteMetas(Map<String, Set<String>> keys);

  /// Applies [patch] to [chapterIds] and returns them as the backend now
  /// holds them, which may differ from the patch (spike S2).
  Future<List<RemoteChapter>> updateChapters(
    List<String> chapterIds,
    ChapterPatch patch,
  );
}
