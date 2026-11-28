import 'package:collection/collection.dart';

// The state the merge rules compare. One record per series, chapter or meta
// entry, as both sides last saw it; `sync_base` stores the agreed one as JSON.
// Records are immutable values; this file has no Flutter dependency.
// Times are UTC and kept to the millisecond. The Suwayomi backend converts
// the server's seconds (spike S2).

const _setEquality = SetEquality<String>();
const _listEquality = ListEquality<String>();
const _mapEquality = MapEquality<String, String>();

/// Categories are matched by name, ignoring case and surrounding spaces
/// (design 2.1).
String categoryKey(String name) => name.trim().toLowerCase();

DateTime? _time(Object? millis) => millis is int
    ? DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
    : null;

class SeriesState {
  const SeriesState({
    required this.inLibrary,
    this.categories = const {},
    this.changedAt,
  });

  /// A series one side does not know about.
  static const absent = SeriesState(inLibrary: false);

  factory SeriesState.fromJson(Map<String, Object?> json) => SeriesState(
    inLibrary: json['inLibrary'] == true,
    categories: {
      for (final key in json['categories'] as List<Object?>? ?? const [])
        if (key is String) key,
    },
    changedAt: _time(json['changedAt']),
  );

  final bool inLibrary;

  /// [categoryKey]s.
  final Set<String> categories;

  /// When [inLibrary] last changed on this side. A conflict tie-breaker, not
  /// part of what the two sides must agree on (see [sameAs]).
  final DateTime? changedAt;

  /// Whether both sides hold the same library entry, whatever their times.
  bool sameAs(SeriesState other) =>
      inLibrary == other.inLibrary &&
      _setEquality.equals(categories, other.categories);

  SeriesState copyWith({
    bool? inLibrary,
    Set<String>? categories,
    DateTime? changedAt,
  }) => SeriesState(
    inLibrary: inLibrary ?? this.inLibrary,
    categories: categories ?? this.categories,
    changedAt: changedAt ?? this.changedAt,
  );

  Map<String, Object?> toJson() => {
    'inLibrary': inLibrary,
    'categories': categories.toList()..sort(),
    if (changedAt != null) 'changedAt': changedAt!.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is SeriesState && sameAs(other) && other.changedAt == changedAt;

  @override
  int get hashCode =>
      Object.hash(inLibrary, _setEquality.hash(categories), changedAt);

  @override
  String toString() => 'SeriesState(${toJson()})';
}

class ChapterState {
  const ChapterState({
    this.read = false,
    this.page = 0,
    this.bookmarked = false,
    this.readAt,
  }) : assert(page >= 0);

  factory ChapterState.fromJson(Map<String, Object?> json) => ChapterState(
    read: json['read'] == true,
    page: switch (json['page']) {
      final int page when page >= 0 => page,
      _ => 0,
    },
    bookmarked: json['bookmarked'] == true,
    readAt: _time(json['readAt']),
  );

  final bool read;

  /// Last page read, zero-based.
  final int page;
  final bool bookmarked;

  /// Last time the chapter was read: Kuchie's history, Suwayomi's
  /// `lastReadAt`. Null when it never was.
  final DateTime? readAt;

  /// Whether it says anything at all: never read, opened or bookmarked.
  bool get isBlank => !read && page == 0 && !bookmarked && readAt == null;

  ChapterState copyWith({
    bool? read,
    int? page,
    bool? bookmarked,
    DateTime? Function()? readAt,
  }) => ChapterState(
    read: read ?? this.read,
    page: page ?? this.page,
    bookmarked: bookmarked ?? this.bookmarked,
    readAt: readAt == null ? this.readAt : readAt(),
  );

  Map<String, Object?> toJson() => {
    'read': read,
    'page': page,
    'bookmarked': bookmarked,
    if (readAt != null) 'readAt': readAt!.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is ChapterState &&
      other.read == read &&
      other.page == page &&
      other.bookmarked == bookmarked &&
      other.readAt == readAt;

  @override
  int get hashCode => Object.hash(read, page, bookmarked, readAt);

  @override
  String toString() => 'ChapterState(${toJson()})';
}

/// Rating, tags and notes. Suwayomi keeps them as manga meta
/// (`flutter_rating`, `flutter_tags`, `kuchie_notes`).
class SeriesMeta {
  const SeriesMeta({this.rating, this.tags = const [], this.notes});

  factory SeriesMeta.fromJson(Map<String, Object?> json) => SeriesMeta(
    rating: switch (json['rating']) {
      final int rating => rating,
      _ => null,
    },
    tags: [
      for (final tag in json['tags'] as List<Object?>? ?? const [])
        if (tag is String) tag,
    ],
    notes: switch (json['notes']) {
      final String notes => notes,
      _ => null,
    },
  );

  final int? rating;

  /// In the order the reader arranged them.
  final List<String> tags;
  final String? notes;

  Map<String, Object?> toJson() => {
    if (rating != null) 'rating': rating,
    'tags': tags,
    if (notes != null) 'notes': notes,
  };

  @override
  bool operator ==(Object other) =>
      other is SeriesMeta &&
      other.rating == rating &&
      _listEquality.equals(other.tags, tags) &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(rating, _listEquality.hash(tags), notes);

  @override
  String toString() => 'SeriesMeta(${toJson()})';
}

/// Per-series reader settings, one string value per meta key.
class ReaderMeta {
  const ReaderMeta([this.values = const {}]);

  factory ReaderMeta.fromJson(Map<String, Object?> json) => ReaderMeta({
    for (final entry in json.entries)
      if (entry.value case final String value) entry.key: value,
  });

  final Map<String, String> values;

  Map<String, Object?> toJson() => {...values};

  @override
  bool operator ==(Object other) =>
      other is ReaderMeta && _mapEquality.equals(other.values, values);

  @override
  int get hashCode => _mapEquality.hash(values);

  @override
  String toString() => 'ReaderMeta($values)';
}
