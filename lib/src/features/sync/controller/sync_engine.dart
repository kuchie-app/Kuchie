import 'dart:async';
import 'dart:math' as math;

import '../../local_collection/data/local_catalog.dart';
import '../../local_collection/data/local_collection_services.dart';
import '../../local_collection/data/local_series_reader_meta.dart';
import '../data/suwayomi/suwayomi_identity.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/sync_backend.dart';
import '../data/sync_journal.dart';
import '../data/sync_state_store.dart';
import '../domain/merge_rules.dart';
import '../domain/sync_change.dart';
import '../domain/sync_meta_keys.dart';
import '../domain/sync_method.dart';
import '../domain/sync_records.dart';
import '../domain/sync_status.dart';

// One sync cycle (design 4.3): preflight, pull, map, merge, apply here,
// push, commit. The base in `sync_base` is the truth about what both sides
// agreed on; the outbox only says where to look between full comparisons.

/// A Mihon extension on this iPhone, as the engine needs it to add a series
/// the server has.
class SyncLocalSource {
  const SyncLocalSource({
    required this.id,
    required this.catalogOrigin,
    required this.name,
    this.locatorFor,
  });

  /// `<package>:<source id>`, or the built-in Shinigami adapter's id.
  final String id;
  final Uri catalogOrigin;
  final String name;

  /// The Local locator for a server manga URL; the URL itself when null,
  /// as for Mihon extensions.
  final String Function(String url)? locatorFor;
}

/// What one cycle did.
class SyncReport {
  const SyncReport(
    this.outcome, {
    this.pulled = 0,
    this.pushed = 0,
    this.seriesErrors = const {},
    this.notReadableHere = 0,
    this.error,
  });

  final SyncOutcome outcome;

  /// Writes applied to this iPhone and sent to the server.
  final int pulled;
  final int pushed;

  /// Local series id → why it did not sync; retried next cycle.
  final Map<String, SyncSeriesError> seriesErrors;

  /// Server series no extension here reads: in the library as "Needs
  /// server", read through it.
  final int notReadableHere;
  final Object? error;

  @override
  String toString() =>
      'SyncReport(${outcome.name}, pulled: $pulled, pushed: $pushed, '
      'errors: $seriesErrors, error: $error)';
}

enum SyncOutcome {
  synced,

  /// Sync is off, or waiting out a backoff.
  skipped,
  unreachable,
  actionNeeded,
  failed,

  /// Stopped when the app went to the background. What was sent is kept.
  cancelled,
}

enum SyncSeriesError {
  /// The server has no manga for it and could not make one: a regular
  /// user's restore does nothing (spike S4b) and the source search missed.
  notOnServer,

  /// A request for it failed; it goes again next cycle.
  requestFailed,
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class SyncEngine {
  SyncEngine({
    required Future<LocalCatalog> Function() catalog,
    required SyncStateStore store,
    required Future<SuwayomiReachability> Function() probe,
    required SyncBackend Function(String baseUrl) backendAt,
    required Future<Map<String, SyncLocalSource>> Function() localSources,
    required Future<String> Function(String baseUrl) ensureServerIdentity,
    this.readerMeta,
    this.onNewSeries,
    DateTime Function()? clock,
    this.onStatus,
    this.batchSize = 50,
  }) : _catalog = catalog,
       _store = store,
       _probe = probe,
       _backendAt = backendAt,
       _localSources = localSources,
       _ensureServerIdentity = ensureServerIdentity,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final Future<LocalCatalog> Function() _catalog;
  final SyncStateStore _store;
  final Future<SuwayomiReachability> Function() _probe;
  final SyncBackend Function(String baseUrl) _backendAt;
  final Future<Map<String, SyncLocalSource>> Function() _localSources;
  final Future<String> Function(String baseUrl) _ensureServerIdentity;

  /// Per-series reader settings; without it they don't sync.
  final LocalSeriesReaderMeta? readerMeta;

  /// Told the series a cycle added to this iPhone from [baseUrl], with the
  /// server's thumbnail path, so their covers can be fetched.
  final void Function(
    String baseUrl,
    List<({String seriesId, String thumbnailUrl})> series,
  )?
  onNewSeries;
  final DateTime Function() _clock;

  /// Told each status a cycle passes through; the Sync controller listens.
  void Function(SyncStatus status)? onStatus;
  final int batchSize;

  /// Waits after the server could not be reached, in order (design 3.8).
  static const backoff = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
  ];

  /// How often an automatic cycle compares every chapter, not just recent
  /// reads.
  static const fullSyncEvery = Duration(hours: 24);

  Future<SyncReport>? _running;
  bool _rerun = false;
  bool _rerunManual = false;
  bool _cancelled = false;
  int _failures = 0;
  DateTime? _retryAt;

  bool get isRunning => _running != null;

  /// Whether a sync method is on, or a server was just connected and waits
  /// for its first sync.
  bool get enabled =>
      _store.method == SyncMethod.suwayomi || _store.connectChoice != null;

  /// Runs a cycle, or marks one more after the running one. [manual] skips
  /// the backoff and compares every chapter.
  Future<SyncReport> sync({bool manual = false}) {
    if (_running case final running?) {
      _rerun = true;
      _rerunManual |= manual;
      return running;
    }
    _cancelled = false;
    final run = _loop(manual);
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  /// Turns the outbox on while sync is on, so changes made before the next
  /// cycle are not missed.
  Future<void> prepare() async {
    if (enabled) (await _catalog()).journalEnabled = true;
  }

  /// Stops the running cycle at the next batch.
  void cancel() => _cancelled = true;

  Future<SyncReport> _loop(bool manual) async {
    var report = await _guarded(manual);
    while (_rerun && !_cancelled && report.outcome == SyncOutcome.synced) {
      _rerun = false;
      final rerunManual = _rerunManual;
      _rerunManual = false;
      report = await _guarded(rerunManual);
    }
    _rerun = false;
    _rerunManual = false;
    return report;
  }

  Future<SyncReport> _guarded(bool manual) async {
    if (!enabled) {
      onStatus?.call(const SyncOff());
      return const SyncReport(SyncOutcome.skipped);
    }
    final now = _clock();
    if (!manual && _retryAt != null && now.isBefore(_retryAt!)) {
      return const SyncReport(SyncOutcome.skipped);
    }
    onStatus?.call(const SyncInProgress());
    final report = await _attempt(manual);
    try {
      await _record(report);
    } catch (_) {
      // The log is for reading later; a full disk must not fail the sync.
    }
    return report;
  }

  Future<SyncReport> _attempt(bool manual) async {
    try {
      final report = await _cycle(manual);
      if (report.outcome == SyncOutcome.synced) {
        _failures = 0;
        _retryAt = null;
      }
      return report;
    } on _Cancelled {
      onStatus?.call(await _restingStatus());
      return const SyncReport(SyncOutcome.cancelled);
    } catch (error) {
      if (isSyncAuthFailure(error)) {
        onStatus?.call(const SyncActionNeeded(SyncActionReason.loginExpired));
        return SyncReport(SyncOutcome.actionNeeded, error: error);
      }
      await _store.recordError('$error');
      _scheduleRetry();
      onStatus?.call(await _waitingStatus());
      return SyncReport(SyncOutcome.failed, error: error);
    }
  }

  /// Adds [report] to the sync log, and keeps why series did not sync for
  /// Needs attention.
  Future<void> _record(SyncReport report) async {
    if (report.outcome == SyncOutcome.synced) {
      await _store.setSeriesErrors({
        for (final MapEntry(:key, :value) in report.seriesErrors.entries)
          key: value.name,
      });
    }
    await _store.appendLog(
      SyncLogEntry(
        at: _clock(),
        outcome: report.outcome.name,
        pulled: report.pulled,
        pushed: report.pushed,
        seriesErrors: report.seriesErrors.length,
        serverOnly: report.notReadableHere,
        message: report.error == null ? null : '${report.error}',
      ),
    );
  }

  void _scheduleRetry() {
    final wait = backoff[math.min(_failures, backoff.length - 1)];
    _failures++;
    _retryAt = _clock().add(wait);
  }

  Future<int> _pendingCount() async {
    final catalog = await _catalog();
    return (await SyncJournal(catalog).coalesced()).length;
  }

  Future<SyncStatus> _waitingStatus() async => SyncWaitingForServer(
    lastSuccessAt: _store.lastSuccessAt,
    pending: await _pendingCount(),
  );

  Future<SyncStatus> _restingStatus() async {
    final pending = await _pendingCount();
    return pending > 0
        ? SyncPending(pending)
        : SyncIdle(lastSuccessAt: _store.lastSuccessAt);
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<SyncReport> _cycle(bool manual) async {
    final catalog = await _catalog();
    catalog.journalEnabled = true;
    final journal = SyncJournal(catalog);

    // 1. Preflight.
    final reachability = await _probe();
    switch (reachability) {
      case SuwayomiUnreachable(:final lastError):
        _scheduleRetry();
        onStatus?.call(await _waitingStatus());
        return SyncReport(SyncOutcome.unreachable, error: lastError);
      case SuwayomiAuthFailed():
        onStatus?.call(const SyncActionNeeded(SyncActionReason.loginExpired));
        return const SyncReport(SyncOutcome.actionNeeded);
      case SuwayomiIdentityChanged():
        onStatus?.call(const SyncActionNeeded(SyncActionReason.serverChanged));
        return const SyncReport(SyncOutcome.actionNeeded);
      case SuwayomiReachable():
    }
    final baseUrl = reachability.baseUrl;
    // The probe may have been built before the identity was saved.
    if (_store.serverIdentity case final expected?
        when reachability.serverIdentity != expected) {
      onStatus?.call(const SyncActionNeeded(SyncActionReason.serverChanged));
      return const SyncReport(SyncOutcome.actionNeeded);
    }
    if (_store.serverIdentity == null) {
      await _store.setServerIdentity(
        reachability.serverIdentity ?? await _ensureServerIdentity(baseUrl),
      );
    }
    final backend = _backendAt(baseUrl);
    final run = _Cycle(
      engine: this,
      catalog: catalog,
      journal: journal,
      backend: backend,
      manual: manual,
      baseUrl: baseUrl,
    );
    final report = await run.run();
    final now = _clock();
    await _store.recordSuccess(now);
    if (run.full) await _store.setLastFullSyncAt(now);
    if (run.cursor case final cursor?) await _store.setChapterCursor(cursor);
    if (_store.method != SyncMethod.suwayomi) {
      await _store.setMethod(SyncMethod.suwayomi);
    }
    onStatus?.call(await _restingStatus());
    return report;
  }
}

/// A linked pair and what this cycle knows of each side.
class _Pair {
  _Pair({
    required this.localId,
    required this.remoteId,
    this.local,
    this.remote,
    this.newSource,
  });

  final String localId;
  final String remoteId;
  LocalSyncSeries? local;
  RemoteSeries? remote;

  /// Set for a series the server has and this iPhone doesn't yet.
  LocalSeriesSource? newSource;

  /// Server chapters pulled this cycle, and whether they are all of them.
  List<RemoteChapter> chapters = const [];
  bool allChapters = false;

  String get title => local?.title ?? remote?.title ?? localId;
  LocalSeriesSource? get source => local?.source ?? newSource;
}

class _ChapterPush {
  const _ChapterPush(this.pair, this.chapter, this.key);

  final _Pair pair;
  final RemoteChapter chapter;
  final String key;
}

class _Cycle {
  _Cycle({
    required this.engine,
    required this.catalog,
    required this.journal,
    required this.backend,
    required this.manual,
    required this.baseUrl,
  });

  final String baseUrl;
  final SyncEngine engine;
  final LocalCatalog catalog;
  final SyncJournal journal;
  final SyncBackend backend;
  final bool manual;

  SyncStateStore get store => engine._store;

  late final bool firstSync = store.lastSuccessAt == null;
  late final ConnectChoice choice = firstSync
      ? store.connectChoice ?? ConnectChoice.merge
      : ConnectChoice.merge;
  late final bool full =
      manual ||
      firstSync ||
      store.chapterCursor == null ||
      switch (store.lastFullSyncAt) {
        final at? => engine._clock().difference(at) >= SyncEngine.fullSyncEvery,
        null => true,
      };

  /// Server seconds of the newest read seen, for the next incremental pull.
  int? cursor;

  final _errors = <String, SyncSeriesError>{};
  var _pulled = 0;
  var _pushed = 0;

  String get _key => backend.key;

  void _seen(DateTime? readAt) {
    if (readAt == null) return;
    final seconds = readAt.millisecondsSinceEpoch ~/ 1000;
    cursor = math.max(cursor ?? store.chapterCursor ?? 0, seconds);
  }

  Future<SyncReport> run() async {
    final changes = await journal.coalesced();
    final lastSeq = changes.map((change) => change.seq).fold(0, math.max);
    final changedAt = <String, DateTime>{
      for (final change in changes)
        if (change.kind == SyncRecordKind.series ||
            change.kind == SyncRecordKind.membership)
          change.key: change.changedAt,
    };
    final changedChapters = <String>{
      for (final change in changes)
        if (change.kind == SyncRecordKind.chapterState)
          if (parseChapterStateKey(change.key) case (final seriesId, _))
            seriesId,
    };

    // 2. Pull. One request at a time, so an Unauthorized answer reaches
    // the auth check as itself.
    final remoteLibrary = await backend.library();
    final remoteCategories = await backend.categories();
    final localSeries = await catalog.syncSeries();
    final sources = await engine._localSources();
    final links = await journal.links(_key);
    engine._checkCancelled();

    // 3. Map.
    final localById = {for (final series in localSeries) series.id: series};
    final remoteById = {for (final series in remoteLibrary) series.id: series};
    final remoteByUrl = {
      for (final series in remoteLibrary) (series.sourceId, series.url): series,
    };
    final pairs = <String, _Pair>{};
    final linkedRemote = <String>{};
    final retired = <String>[];
    for (final link in links) {
      if (link.kind != SyncLinkKind.series) continue;
      // A "Needs server" series whose extension is here now becomes the
      // real Mihon series below; the server keeps its reading state.
      final linkedRemoteSeries = remoteById[link.remoteId];
      if (isServerOnlySeriesId(link.localKey) &&
          linkedRemoteSeries != null &&
          sources.containsKey(linkedRemoteSeries.sourceId)) {
        retired.add(link.localKey);
        continue;
      }
      pairs[link.localKey] = _Pair(
        localId: link.localKey,
        remoteId: link.remoteId,
        local: localById[link.localKey],
        remote: remoteById[link.remoteId],
      );
      linkedRemote.add(link.remoteId);
    }
    final newLinks = <_Pair>[];
    final lookups = <(LocalSyncSeries, String sourceId, String url)>[];
    final dropLocal = <LocalSyncSeries>[];
    for (final series in localSeries) {
      if (!series.inLibrary || pairs.containsKey(series.id)) continue;
      final source = series.source;
      final key = source == null
          ? null
          : suwayomiKeyOf(
              sourceId: source.sourceId,
              mangaId: source.mangaId,
              locator: source.locator,
            );
      // Imports and Kuchie repo sources stay on this iPhone.
      if (key == null) continue;
      final (:sourceId, :url) = key;
      final match = remoteByUrl[(sourceId, url)];
      if (match != null && linkedRemote.add(match.id)) {
        newLinks.add(
          _Pair(
            localId: series.id,
            remoteId: match.id,
            local: series,
            remote: match,
          ),
        );
      } else if (firstSync && choice == ConnectChoice.useServer) {
        dropLocal.add(series);
      } else {
        lookups.add((series, sourceId, url));
      }
    }
    final dropRemote = <String>[];
    for (final series in remoteLibrary) {
      if (linkedRemote.contains(series.id)) continue;
      final source = sources[series.sourceId];
      if (source == null) {
        if (firstSync && choice == ConnectChoice.useLocal) {
          dropRemote.add(series.id);
          continue;
        }
        // No extension here: the series still joins the library, read
        // through the server ("Needs server", design 3.5).
        linkedRemote.add(series.id);
        newLinks.add(
          _Pair(
            localId: serverOnlySeriesId(series.id),
            remoteId: series.id,
            local: localById[serverOnlySeriesId(series.id)],
            remote: series,
            newSource: LocalSeriesSource(
              sourceId: serverOnlySourceId,
              mangaId: series.id,
              locator: series.url,
            ),
          ),
        );
        continue;
      }
      final mangaId = localMangaIdFor(series.sourceId, series.url);
      final localId = localSeriesIdFor(
        origin: source.catalogOrigin,
        sourceId: source.id,
        mangaId: mangaId,
      );
      if (pairs.containsKey(localId) ||
          newLinks.any((pair) => pair.localId == localId)) {
        continue;
      }
      linkedRemote.add(series.id);
      newLinks.add(
        _Pair(
          localId: localId,
          remoteId: series.id,
          local: localById[localId],
          remote: series,
          newSource: LocalSeriesSource(
            sourceId: source.id,
            mangaId: mangaId,
            locator: source.locatorFor?.call(series.url) ?? series.url,
            sourceName: source.name,
          ),
        ),
      );
    }
    void linkFound(LocalSyncSeries series, RemoteSeries? found) {
      if (found == null || !linkedRemote.add(found.id)) {
        _errors[series.id] = SyncSeriesError.notOnServer;
        return;
      }
      _errors.remove(series.id);
      newLinks.add(
        _Pair(
          localId: series.id,
          remoteId: found.id,
          local: series,
          remote: found,
        ),
      );
    }

    final create = <(LocalSyncSeries, String sourceId, String url)>[];
    for (final lookup in lookups) {
      engine._checkCancelled();
      final (series, sourceId, url) = lookup;
      final found = await backend.findSeries(sourceId, url);
      found == null ? create.add(lookup) : linkFound(series, found);
    }
    if (create.isNotEmpty) {
      engine._checkCancelled();
      final created = {
        for (final series in await backend.createSeries([
          for (final (series, sourceId, url) in create)
            NewRemoteSeries(
              sourceId: sourceId,
              url: url,
              title: series.title,
              sourceName: series.source?.sourceName ?? '',
            ),
        ]))
          (series.sourceId, series.url): series,
      };
      for (final (series, sourceId, url) in create) {
        linkFound(series, created[(sourceId, url)]);
      }
    }
    for (final id in retired) {
      await journal.removeLink(_key, SyncLinkKind.series, id);
      await catalog.forgetSyncPlaceholder(id);
    }
    for (final pair in newLinks) {
      await journal.putLink(
        _key,
        SyncLink(
          kind: SyncLinkKind.series,
          localKey: pair.localId,
          remoteId: pair.remoteId,
        ),
      );
      pairs[pair.localId] = pair;
    }

    // Chapters: every chapter on a full pass, else recent reads on the
    // server and series with reads here.
    final active = [
      for (final pair in pairs.values)
        if ((pair.local?.inLibrary ?? false) ||
            (pair.remote?.inLibrary ?? false))
          pair,
    ];
    final fresh = {for (final pair in newLinks) pair.localId};
    final byRemote = {for (final pair in active) pair.remoteId: pair};
    if (!full) {
      final since = DateTime.fromMillisecondsSinceEpoch(
        (store.chapterCursor ?? 0) * 1000,
        isUtc: true,
      );
      final recent = await backend.chaptersReadSince(
        byRemote.keys.toSet(),
        since,
      );
      final grouped = <String, List<RemoteChapter>>{};
      for (final chapter in recent) {
        grouped.putIfAbsent(chapter.seriesId, () => []).add(chapter);
      }
      for (final MapEntry(:key, :value) in grouped.entries) {
        byRemote[key]?.chapters = value;
      }
    }
    for (final pair in active) {
      if (!full &&
          !fresh.contains(pair.localId) &&
          !changedChapters.contains(pair.localId)) {
        continue;
      }
      engine._checkCancelled();
      List<RemoteChapter> chapters;
      try {
        chapters = await backend.chaptersOf(pair.remoteId);
        // A manga the server never opened has no chapters yet (spike S3).
        if (chapters.isEmpty && fresh.contains(pair.localId)) {
          chapters = await backend.refreshChapters(pair.remoteId);
        }
      } catch (error) {
        if (isSyncAuthFailure(error)) rethrow;
        // Its source is down on the server; the library still syncs.
        _errors[pair.localId] = SyncSeriesError.requestFailed;
        continue;
      }
      pair
        ..chapters = chapters
        ..allChapters = true;
    }

    // 4. Merge.
    final categoryKeyById = {
      for (final category in remoteCategories)
        category.id: categoryKey(category.name),
    };
    final remoteCategoryByKey = {
      for (final category in remoteCategories)
        categoryKey(category.name): category,
    };
    final localCategoryNames = {
      for (final name in await catalog.categories()) categoryKey(name): name,
    };
    final seriesWrites = <LocalSyncSeriesWrite>[];
    final memberships = <String, Set<String>>{};
    final newCategories = <String>{};
    final chapterWrites = <LocalSyncChapterWrite>[];
    final seriesBase = <String, SeriesState>{};
    final chapterBase = <String, ChapterState>{};
    final addRemote = <_Pair>[];
    final removeRemote = <String>[...dropRemote];
    final categoryChanges = <_Pair, ({Set<String> add, Set<String> remove})>{};
    final chapterPushes = <ChapterPatch, List<_ChapterPush>>{};
    final lastSuccessAt = store.lastSuccessAt;
    final chapterBases = await journal.bases(_key, SyncRecordKind.chapterState);
    final seriesBases = await journal.bases(_key, SyncRecordKind.series);
    final syncsLibrary = store.includes(SyncDataKind.library);
    final syncsProgress = store.includes(SyncDataKind.progress);
    final syncsBookmarks = store.includes(SyncDataKind.bookmarks);
    // Rating, tags and notes start off, unless the server holds them
    // already, as after Server mode (design 3.4).
    if (!store.choseIncludes(SyncDataKind.seriesMeta) &&
        remoteLibrary.any(
          (series) =>
              series.meta.containsKey(ratingMetaKey) ||
              series.meta.containsKey(tagsMetaKey),
        )) {
      await store.setIncludes(SyncDataKind.seriesMeta, true);
    }
    final syncsSeriesMeta = store.includes(SyncDataKind.seriesMeta);
    final readerMeta = store.includes(SyncDataKind.readerMeta)
        ? engine.readerMeta
        : null;
    final seriesMetaBases = await journal.bases(
      _key,
      SyncRecordKind.seriesMeta,
    );
    final readerMetaBases = await journal.bases(
      _key,
      SyncRecordKind.readerMeta,
    );
    final metaChangedAt = <(SyncRecordKind, String), DateTime>{
      for (final change in changes) (change.kind, change.key): change.changedAt,
    };
    final seriesMetaWrites = <String, SeriesMeta>{};
    final readerMetaWrites = <String, Map<String, String>>{};
    final metaSets = <_Pair, Map<String, String>>{};
    final metaDeletes = <_Pair, Set<String>>{};
    final seriesMetaBase = <String, SeriesMeta>{};
    final readerMetaBase = <String, ReaderMeta>{};

    for (final series in dropLocal) {
      seriesWrites.add(
        LocalSyncSeriesWrite(
          id: series.id,
          title: series.title,
          inLibrary: false,
        ),
      );
    }

    for (final pair in active) {
      // Chapters first: reading since the last sync decides a removal.
      var localReadSince = false, remoteReadSince = false;
      if (pair.chapters.isNotEmpty) {
        final localStates = await catalog.syncChapterStates(pair.localId);
        for (final chapter in pair.chapters) {
          _seen(chapter.state.readAt);
          final chapterId = localChapterIdFor(pair.localId, chapter.url);
          final key = chapterStateKey(pair.localId, chapterId);
          final base = switch (chapterBases[key]) {
            final json? => ChapterState.fromJson(json),
            null => null,
          };
          var local = localStates[chapterId] ?? const ChapterState();
          // This iPhone keeps a page only with a read time (History). A page
          // the server holds without one was never changed here: keep it,
          // instead of sending page 0 back.
          if (local.readAt == null &&
              local.page == 0 &&
              base != null &&
              base.readAt == null) {
            local = local.copyWith(page: base.page);
          }
          var remote = chapter.state;
          // The read time the server stamped on Kuchie's own update stands
          // for the iPhone's; only a newer one is a read elsewhere.
          if (base != null && remote.readAt == base.readAt) {
            remote = remote.copyWith(readAt: () => local.readAt);
          }
          if (!syncsProgress) {
            remote = remote.copyWith(
              read: local.read,
              page: local.page,
              readAt: () => local.readAt,
            );
          }
          if (!syncsBookmarks) {
            remote = remote.copyWith(bookmarked: local.bookmarked);
          }
          if (lastSuccessAt != null) {
            localReadSince |= local.readAt?.isAfter(lastSuccessAt) ?? false;
            remoteReadSince |=
                chapter.state.readAt?.isAfter(lastSuccessAt) ?? false;
          }
          final merged = switch (choice) {
            ConnectChoice.useServer => remote,
            ConnectChoice.useLocal => local,
            ConnectChoice.merge => mergeChapter(
              base: base,
              local: local,
              remote: remote,
            ).value,
          };
          if (merged != local) {
            chapterWrites.add(
              LocalSyncChapterWrite(
                seriesId: pair.localId,
                seriesTitle: pair.title,
                source: pair.source,
                chapterId: chapterId,
                chapterTitle: chapter.name.trim().isEmpty
                    ? chapterId
                    : chapter.name,
                state: merged,
              ),
            );
          }
          final server = chapter.state;
          final patch = ChapterPatch(
            read: syncsProgress && merged.read != server.read
                ? merged.read
                : null,
            page: syncsProgress && merged.page != server.page
                ? merged.page
                : null,
            bookmarked: syncsBookmarks && merged.bookmarked != server.bookmarked
                ? merged.bookmarked
                : null,
          );
          if (!patch.isEmpty) {
            chapterPushes
                .putIfAbsent(patch, () => [])
                .add(_ChapterPush(pair, chapter, key));
          } else {
            // Stored as the next pull will see it: the server's read time,
            // and the server's values for kinds left out, so turning one
            // back on sends what changed here meanwhile.
            final agreed = merged.copyWith(
              read: syncsProgress ? null : server.read,
              page: syncsProgress ? null : server.page,
              bookmarked: syncsBookmarks ? null : server.bookmarked,
              readAt: () => server.readAt,
            );
            if (agreed != base && !(base == null && agreed.isBlank)) {
              chapterBase[key] = agreed;
            }
          }
        }
      }

      // Rating, tags, notes and reader settings, per key (design 4.2).
      if (pair.remote case final remote?) {
        void push(Map<String, String?> merged, Map<String, String> server) {
          for (final MapEntry(:key, :value) in merged.entries) {
            if (value == null) {
              if (server.containsKey(key)) {
                metaDeletes.putIfAbsent(pair, () => {}).add(key);
              }
            } else if (server[key] != value) {
              metaSets.putIfAbsent(pair, () => {})[key] = value;
            }
          }
        }

        if (syncsSeriesMeta) {
          final stored = await catalog.seriesMeta(pair.localId);
          final local = SeriesMeta(
            rating: stored.rating == 0 ? null : stored.rating,
            tags: stored.tags,
            notes: stored.notes.isEmpty ? null : stored.notes,
          );
          final server = seriesMetaFromServer(remote.meta);
          final base = switch (seriesMetaBases[pair.localId]) {
            final json? => SeriesMeta.fromJson(json),
            null => null,
          };
          final merged = switch (choice) {
            ConnectChoice.useServer => server,
            ConnectChoice.useLocal => local,
            // Without a base, a field only one side set is an addition,
            // not a conflict: start from empty.
            ConnectChoice.merge => mergeSeriesMeta(
              base: base ?? const SeriesMeta(),
              local: local,
              remote: server,
              localChangedAt:
                  metaChangedAt[(SyncRecordKind.seriesMeta, pair.localId)],
            ).value,
          };
          if (merged != local) seriesMetaWrites[pair.localId] = merged;
          if (merged != server) {
            push(seriesMetaToServer(merged), remote.meta);
          }
          if (merged != base) seriesMetaBase[pair.localId] = merged;
        }
        if (readerMeta != null) {
          final stored = readerMeta.read(pair.localId);
          final local = ReaderMeta({
            for (final MapEntry(:key, :value) in stored.entries)
              if (value != null) key: '$value',
          });
          final server = ReaderMeta(remote.meta);
          final base = switch (readerMetaBases[pair.localId]) {
            final json? => ReaderMeta.fromJson(json),
            null => null,
          };
          ReaderMeta owned(ReaderMeta meta) => ReaderMeta({
            for (final MapEntry(:key, :value) in meta.values.entries)
              if (ownsReaderMetaKey(key)) key: value,
          });
          final merged = switch (choice) {
            ConnectChoice.useServer => owned(server),
            ConnectChoice.useLocal => owned(local),
            ConnectChoice.merge => mergeReaderMeta(
              base: base ?? const ReaderMeta(),
              local: local,
              remote: server,
              owns: ownsReaderMetaKey,
              localChangedAt:
                  metaChangedAt[(SyncRecordKind.readerMeta, pair.localId)],
            ).value,
          };
          if (merged != owned(local)) {
            readerMetaWrites[pair.localId] = {
              for (final MapEntry(:key, :value) in local.values.entries)
                if (!ownsReaderMetaKey(key)) key: value,
              ...merged.values,
            };
          }
          if (merged != owned(server)) {
            push({
              for (final key in owned(server).values.keys) key: null,
              ...merged.values,
            }, remote.meta);
          }
          if (merged != base) readerMetaBase[pair.localId] = merged;
        }
      }

      if (!syncsLibrary) continue;
      final base = switch (seriesBases[pair.localId]) {
        final json? => SeriesState.fromJson(json),
        null => null,
      };
      final unknown = base?.categories ?? const <String>{};
      final local = pair.local?.inLibrary ?? false
          ? SeriesState(
              inLibrary: true,
              categories: pair.local!.categories.map(categoryKey).toSet(),
              changedAt: changedAt[pair.localId],
            )
          : SeriesState(inLibrary: false, categories: unknown);
      final remoteCategories = {
        for (final id in pair.remote?.categoryIds ?? const <String>{})
          ?categoryKeyById[id],
      };
      final remote = pair.remote?.inLibrary ?? false
          ? SeriesState(
              inLibrary: true,
              categories: remoteCategories,
              changedAt: pair.remote!.inLibraryAt,
            )
          : SeriesState(inLibrary: false, categories: unknown);
      final merged = switch (choice) {
        ConnectChoice.useServer => remote,
        ConnectChoice.useLocal => local,
        ConnectChoice.merge =>
          mergeSeries(
                base: base,
                local: local,
                remote: remote,
                localReadSinceBase: localReadSince,
                remoteReadSinceBase: remoteReadSince,
              ).value ??
              SeriesState.absent,
      };
      if (merged.inLibrary != local.inLibrary) {
        seriesWrites.add(
          LocalSyncSeriesWrite(
            id: pair.localId,
            title: pair.title,
            inLibrary: merged.inLibrary,
            source: pair.source,
          ),
        );
      }
      if (merged.inLibrary &&
          !_sameSet(merged.categories, {
            if (pair.local?.inLibrary ?? false)
              ...pair.local!.categories.map(categoryKey),
          })) {
        memberships[pair.localId] = {
          for (final key in merged.categories)
            localCategoryNames[key] ?? remoteCategoryByKey[key]?.name ?? key,
        };
        for (final key in merged.categories) {
          if (!localCategoryNames.containsKey(key)) {
            newCategories.add(remoteCategoryByKey[key]?.name ?? key);
          }
        }
      }
      if (merged.inLibrary != (pair.remote?.inLibrary ?? false)) {
        if (merged.inLibrary) {
          addRemote.add(pair);
        } else {
          removeRemote.add(pair.remoteId);
        }
      }
      if (merged.inLibrary) {
        final current = pair.remote?.inLibrary ?? false
            ? remoteCategories
            : const <String>{};
        final add = merged.categories.difference(current);
        final remove = current.difference(merged.categories);
        if (add.isNotEmpty || remove.isNotEmpty) {
          categoryChanges[pair] = (add: add, remove: remove);
        }
      }
      final agreed = SeriesState(
        inLibrary: merged.inLibrary,
        categories: merged.categories,
      );
      if (base == null || !base.sameAs(agreed)) {
        seriesBase[pair.localId] = agreed;
      }
    }
    engine._checkCancelled();

    // 5. Apply here, in one transaction.
    final write = LocalSyncWrite(
      series: seriesWrites,
      categories: newCategories,
      memberships: memberships,
      chapters: chapterWrites,
      seriesMeta: seriesMetaWrites,
    );
    await catalog.applySync(write);
    // New series, and on a full pass every one still without a cover.
    final added = [
      for (final pair in active)
        if (pair.remote?.thumbnailUrl case final thumbnail?)
          if (full
              ? pair.remote!.inLibrary
              : pair.local == null &&
                    seriesWrites.any(
                      (series) => series.id == pair.localId && series.inLibrary,
                    ))
            (seriesId: pair.localId, thumbnailUrl: thumbnail),
    ];
    if (added.isNotEmpty) engine.onNewSeries?.call(baseUrl, added);
    for (final MapEntry(key: id, value: values) in readerMetaWrites.entries) {
      await readerMeta?.replaceSynced(id, values);
    }
    _pulled =
        seriesWrites.length +
        memberships.length +
        chapterWrites.length +
        seriesMetaWrites.length +
        readerMetaWrites.length;
    await journal.putBases(_key, SyncRecordKind.chapterState, {
      for (final MapEntry(:key, :value) in chapterBase.entries)
        key: value.toJson(),
    });

    // 6. Push, in batches. A series' base waits for its own requests.
    final seriesFailed = <String>{};
    Future<void> attempt(
      Iterable<String> localIds,
      Future<void> Function() request,
    ) async {
      engine._checkCancelled();
      try {
        await request();
      } catch (error) {
        if (isSyncAuthFailure(error)) rethrow;
        for (final id in localIds) {
          seriesFailed.add(id);
          _errors[id] = SyncSeriesError.requestFailed;
        }
      }
    }

    final remoteCategoryIds = {
      for (final category in remoteCategories)
        categoryKey(category.name): category.id,
    };
    final neededCategories = {
      for (final change in categoryChanges.values) ...change.add,
    }.where((key) => !remoteCategoryIds.containsKey(key));
    for (final key in neededCategories) {
      final users = [
        for (final MapEntry(key: pair, value: change)
            in categoryChanges.entries)
          if (change.add.contains(key)) pair.localId,
      ];
      await attempt(users, () async {
        final created = await backend.createCategory(
          localCategoryNames[key] ?? key,
        );
        remoteCategoryIds[key] = created.id;
      });
    }

    for (final batch in _batches(addRemote, engine.batchSize)) {
      await attempt(batch.map((pair) => pair.localId), () async {
        await backend.setInLibrary([
          for (final pair in batch) pair.remoteId,
        ], inLibrary: true);
        _pushed += batch.length;
      });
    }
    final localByRemote = {
      for (final pair in pairs.values) pair.remoteId: pair.localId,
    };
    for (final batch in _batches(removeRemote, engine.batchSize)) {
      await attempt([for (final id in batch) ?localByRemote[id]], () async {
        await backend.setInLibrary(batch, inLibrary: false);
        _pushed += batch.length;
      });
    }

    final groupedCategories = <String, List<_Pair>>{};
    for (final MapEntry(key: pair, value: change) in categoryChanges.entries) {
      final label = [
        ...(change.add.toList()..sort()).map((key) => '+$key'),
        ...(change.remove.toList()..sort()).map((key) => '-$key'),
      ].join('\n');
      groupedCategories.putIfAbsent(label, () => []).add(pair);
    }
    for (final group in groupedCategories.values) {
      final change = categoryChanges[group.first]!;
      final add = {for (final key in change.add) ?remoteCategoryIds[key]};
      final remove = {for (final key in change.remove) ?remoteCategoryIds[key]};
      if (add.length != change.add.length) {
        // Creating a category failed; those series retry next cycle.
        for (final pair in group) {
          seriesFailed.add(pair.localId);
          _errors[pair.localId] = SyncSeriesError.requestFailed;
        }
        continue;
      }
      for (final batch in _batches(group, engine.batchSize)) {
        await attempt(batch.map((pair) => pair.localId), () async {
          await backend.changeCategories(
            [for (final pair in batch) pair.remoteId],
            add: add,
            remove: remove,
          );
          _pushed += batch.length;
        });
      }
    }

    await journal.putBases(_key, SyncRecordKind.series, {
      for (final MapEntry(key: id, value: state) in seriesBase.entries)
        if (!seriesFailed.contains(id)) id: state.toJson(),
    });

    final metaPairs = {...metaSets.keys, ...metaDeletes.keys}.toList();
    for (final batch in _batches(metaPairs, engine.batchSize)) {
      await attempt(batch.map((pair) => pair.localId), () async {
        await backend.setMetas({
          for (final pair in batch) pair.remoteId: ?metaSets[pair],
        });
        await backend.deleteMetas({
          for (final pair in batch) pair.remoteId: ?metaDeletes[pair],
        });
        _pushed += batch.length;
      });
    }
    await journal.putBases(_key, SyncRecordKind.seriesMeta, {
      for (final MapEntry(key: id, value: meta) in seriesMetaBase.entries)
        if (!seriesFailed.contains(id)) id: meta.toJson(),
    });
    await journal.putBases(_key, SyncRecordKind.readerMeta, {
      for (final MapEntry(key: id, value: meta) in readerMetaBase.entries)
        if (!seriesFailed.contains(id)) id: meta.toJson(),
    });

    for (final MapEntry(key: patch, value: pushes) in chapterPushes.entries) {
      for (final batch in _batches(pushes, engine.batchSize)) {
        await attempt(batch.map((push) => push.pair.localId), () async {
          final updated = {
            for (final chapter in await backend.updateChapters([
              for (final push in batch) push.chapter.id,
            ], patch))
              chapter.id: chapter,
          };
          _pushed += batch.length;
          // Stored as the server now holds it, which may still differ from
          // what was sent (spike S2); the next cycle sends it again.
          for (final chapter in updated.values) {
            _seen(chapter.state.readAt);
          }
          await journal.putBases(_key, SyncRecordKind.chapterState, {
            for (final push in batch)
              if (updated[push.chapter.id]?.state case final held?)
                push.key: held.toJson(),
          });
        });
      }
    }

    // 7. Commit. Failed series keep their outbox entries for the next try.
    if (_errors.isEmpty) await journal.trimThrough(lastSeq);
    return SyncReport(
      SyncOutcome.synced,
      pulled: _pulled,
      pushed: _pushed,
      seriesErrors: Map.unmodifiable(_errors),
      notReadableHere: active
          .where(
            (pair) =>
                isServerOnlySeriesId(pair.localId) &&
                (pair.remote?.inLibrary ?? false),
          )
          .length,
    );
  }
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

Iterable<List<T>> _batches<T>(List<T> items, int size) sync* {
  for (var start = 0; start < items.length; start += size) {
    yield items.sublist(start, math.min(start + size, items.length));
  }
}
