import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'sync_records.dart';

// Three-way merge (design 4.2): each side is compared with the base, the
// state both sides agreed on after the last sync. A side that still equals
// the base did not change, so the other side wins without a conflict. Only
// when both changed, differently, does a per-field conflict rule decide.
//
// Pure functions without Flutter, tested as tables in
// test/src/features/sync/domain/merge_rules_test.dart.

/// What a merge asks the engine to do. [value] is the state both sides hold
/// afterwards, and becomes the new base.
sealed class MergeOutcome<T> {
  const MergeOutcome(this.value);

  final T value;

  /// Whether the iPhone's catalog must be written.
  bool get writesLocal;

  /// Whether the server must be written.
  bool get writesRemote;
}

/// Both sides already agree.
final class MergeKeep<T> extends MergeOutcome<T> {
  const MergeKeep(super.value);

  @override
  bool get writesLocal => false;

  @override
  bool get writesRemote => false;

  @override
  String toString() => 'MergeKeep($value)';
}

/// The iPhone's state wins; send it to the server.
final class MergePushLocal<T> extends MergeOutcome<T> {
  const MergePushLocal(super.value);

  @override
  bool get writesLocal => false;

  @override
  bool get writesRemote => true;

  @override
  String toString() => 'MergePushLocal($value)';
}

/// The server's state wins; apply it to the iPhone.
final class MergeApplyRemote<T> extends MergeOutcome<T> {
  const MergeApplyRemote(super.value);

  @override
  bool get writesLocal => true;

  @override
  bool get writesRemote => false;

  @override
  String toString() => 'MergeApplyRemote($value)';
}

/// A combination of both sides; write it to both.
final class MergeBoth<T> extends MergeOutcome<T> {
  const MergeBoth(super.value);

  @override
  bool get writesLocal => true;

  @override
  bool get writesRemote => true;

  @override
  String toString() => 'MergeBoth($value)';
}

/// Decides a value both sides changed differently since [base].
typedef ConflictRule<T> = T? Function(T? base, T? local, T? remote);

/// How far apart two times must be to say which is newer. Suwayomi stores
/// seconds (spike S2), and the iPhone's and server's clocks drift a little.
const clockTolerance = Duration(seconds: 2);

/// Merges one value. Null means the side does not have it (never set, or
/// deleted).
MergeOutcome<T?> merge3<T>({
  required T? base,
  required T? local,
  required T? remote,
  required ConflictRule<T> rule,
  bool Function(T? a, T? b)? equals,
}) {
  final same = equals ?? (T? a, T? b) => a == b;
  if (same(local, remote)) return MergeKeep(local);
  if (same(local, base)) return MergeApplyRemote(remote);
  if (same(remote, base)) return MergePushLocal(local);
  final merged = rule(base, local, remote);
  return _outcome(
    merged,
    asLocal: same(merged, local),
    asRemote: same(merged, remote),
  );
}

/// Library membership and categories of one series.
///
/// Reading wins: when one side removed the series while the other still has
/// it and read it after the last sync, the series stays in the library.
/// Otherwise a membership conflict goes to the newer change, and to keeping
/// it when the times cannot tell. Categories merge per name: additions and
/// removals from both sides all apply. A null side does not know the series.
MergeOutcome<SeriesState?> mergeSeries({
  required SeriesState? base,
  required SeriesState? local,
  required SeriesState? remote,
  bool localReadSinceBase = false,
  bool remoteReadSinceBase = false,
}) {
  final l = local ?? SeriesState.absent;
  final r = remote ?? SeriesState.absent;
  if (l.sameAs(r)) return MergeKeep(local ?? remote);
  final newer = _newer(l.changedAt, r.changedAt);
  var inLibrary = _field3(
    base?.inLibrary,
    l.inLibrary,
    r.inLibrary,
    hasBase: base != null,
    conflict: () => newer == 0 || (newer < 0 ? l.inLibrary : r.inLibrary),
  );
  if (!inLibrary &&
      ((l.inLibrary && localReadSinceBase) ||
          (r.inLibrary && remoteReadSinceBase))) {
    inLibrary = true;
  }
  final merged = SeriesState(
    inLibrary: inLibrary,
    categories: _set3(base?.categories, l.categories, r.categories),
    changedAt: _later(l.changedAt, r.changedAt),
  );
  return _outcome<SeriesState?>(
    merged,
    asLocal: merged.sameAs(l),
    asRemote: merged.sameAs(r),
  );
}

/// Read state, page and bookmark of one chapter both sides know.
///
/// - Read/unread: the newer side wins; when the times cannot tell, read wins.
/// - Page: the side read more recently wins; otherwise the furthest page.
/// - Bookmark: set wins.
/// - Read time (history): the latest of both; history only grows.
MergeOutcome<ChapterState> mergeChapter({
  required ChapterState? base,
  required ChapterState local,
  required ChapterState remote,
}) {
  if (local == remote) return MergeKeep(local);
  final newer = _newer(local.readAt, remote.readAt);
  final merged = ChapterState(
    read: _field3(
      base?.read,
      local.read,
      remote.read,
      hasBase: base != null,
      conflict: () => newer == 0 || (newer < 0 ? local.read : remote.read),
    ),
    page: _field3(
      base?.page,
      local.page,
      remote.page,
      hasBase: base != null,
      conflict: () => switch (newer) {
        < 0 => local.page,
        > 0 => remote.page,
        _ => math.max(local.page, remote.page),
      },
    ),
    bookmarked: _field3(
      base?.bookmarked,
      local.bookmarked,
      remote.bookmarked,
      hasBase: base != null,
      conflict: () => true,
    ),
    readAt: _later(local.readAt, remote.readAt),
  );
  return _outcome(merged, asLocal: merged == local, asRemote: merged == remote);
}

/// Rating, tags and notes, each merged on its own. A field both sides changed
/// goes to the side changed more recently, and to the iPhone when the times
/// cannot tell: the server keeps no per-field times.
MergeOutcome<SeriesMeta> mergeSeriesMeta({
  required SeriesMeta? base,
  required SeriesMeta local,
  required SeriesMeta remote,
  DateTime? localChangedAt,
  DateTime? remoteChangedAt,
}) {
  if (local == remote) return MergeKeep(local);
  final remoteWins = _newer(localChangedAt, remoteChangedAt) > 0;
  T pick<T>(T l, T r) => remoteWins ? r : l;
  final merged = SeriesMeta(
    rating: _field3(
      base?.rating,
      local.rating,
      remote.rating,
      hasBase: base != null,
      conflict: () => pick(local.rating, remote.rating),
    ),
    tags: _field3(
      base?.tags,
      local.tags,
      remote.tags,
      hasBase: base != null,
      conflict: () => pick(local.tags, remote.tags),
      equals: const ListEquality<String>().equals,
    ),
    notes: _field3(
      base?.notes,
      local.notes,
      remote.notes,
      hasBase: base != null,
      conflict: () => pick(local.notes, remote.notes),
    ),
  );
  return _outcome(merged, asLocal: merged == local, asRemote: merged == remote);
}

/// Per-series reader settings, merged per key with [mergeSeriesMeta]'s
/// conflict rule. Only keys Kuchie [owns] take part: the result never holds
/// another client's keys (WebUI's, for example), so the engine never sends
/// them back changed or deleted.
MergeOutcome<ReaderMeta> mergeReaderMeta({
  required ReaderMeta? base,
  required ReaderMeta local,
  required ReaderMeta remote,
  required bool Function(String key) owns,
  DateTime? localChangedAt,
  DateTime? remoteChangedAt,
}) {
  Map<String, String> owned(ReaderMeta? meta) => {
    for (final entry in (meta?.values ?? const <String, String>{}).entries)
      if (owns(entry.key)) entry.key: entry.value,
  };
  final b = owned(base), l = owned(local), r = owned(remote);
  final ownedLocal = ReaderMeta(l), ownedRemote = ReaderMeta(r);
  if (ownedLocal == ownedRemote) return MergeKeep(ownedLocal);
  final remoteWins = _newer(localChangedAt, remoteChangedAt) > 0;
  final merged = <String, String>{};
  for (final key in {...b.keys, ...l.keys, ...r.keys}) {
    final value = _field3<String?>(
      b[key],
      l[key],
      r[key],
      hasBase: base != null,
      conflict: () => remoteWins ? r[key] : l[key],
    );
    if (value != null) merged[key] = value;
  }
  final result = ReaderMeta(merged);
  return _outcome(
    result,
    asLocal: result == ownedLocal,
    asRemote: result == ownedRemote,
  );
}

// --- Helpers ---------------------------------------------------------------

MergeOutcome<R> _outcome<R>(
  R merged, {
  required bool asLocal,
  required bool asRemote,
}) {
  // Callers return early when local and remote agree, so merged can match
  // at most one of them.
  if (asLocal) return MergePushLocal(merged);
  if (asRemote) return MergeApplyRemote(merged);
  return MergeBoth(merged);
}

/// One field: the side that moved away from [base] wins; [conflict] decides
/// when both did, differently. Without a base (first sync) any difference is
/// a conflict. [hasBase] tells "no base" apart from a base whose value is
/// null, such as a rating both sides agreed to leave empty.
V _field3<V>(
  V? base,
  V local,
  V remote, {
  required bool hasBase,
  required V Function() conflict,
  bool Function(V? a, V? b)? equals,
}) {
  final same = equals ?? (V? a, V? b) => a == b;
  if (same(local, remote)) return local;
  if (hasBase) {
    if (same(local, base)) return remote;
    if (same(remote, base)) return local;
  }
  return conflict();
}

/// Per-element set merge: an element is kept unless a side removed it, and
/// added when a side added it.
Set<String> _set3(Set<String>? base, Set<String> local, Set<String> remote) {
  final b = base ?? const <String>{};
  return {
    for (final key in {...b, ...local, ...remote})
      if (local.contains(key) == remote.contains(key)
          ? local.contains(key)
          : local.contains(key) != b.contains(key)
          ? local.contains(key)
          : remote.contains(key))
        key,
  };
}

/// Negative when [local] is clearly newer, positive when [remote] is, zero
/// when either is unknown or they are within [clockTolerance].
int _newer(DateTime? local, DateTime? remote) {
  if (local == null || remote == null) return 0;
  final difference = local.difference(remote);
  if (difference.abs() <= clockTolerance) return 0;
  return difference.isNegative ? 1 : -1;
}

DateTime? _later(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}
