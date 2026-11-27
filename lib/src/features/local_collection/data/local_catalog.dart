import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/sha256.dart';
import 'package:uuid/uuid.dart';

import '../../sync/domain/sync_change.dart';
import '../../sync/domain/sync_records.dart' show categoryKey;

const _maxPages = 4000;
const _maxPageBytes = 64 * 1024 * 1024;
const _maxChapterBytes = 4 * 1024 * 1024 * 1024;
const _maxBackupBytes = 16 * 1024 * 1024;
const _transferTimeout = Duration(seconds: 30);
const _insertChange =
    'INSERT INTO sync_changes (kind, key, op, changed_at) VALUES (?, ?, ?, ?)';
const _imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.avif',
};
const _imageTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
  'image/avif',
};

class LocalSeriesSource {
  const LocalSeriesSource({
    required this.sourceId,
    required this.mangaId,
    required this.locator,
    this.cover,
    this.genres = const [],
    this.sourceName,
  });

  final String sourceId;
  final String mangaId;
  final String locator;
  final Uri? cover;
  final List<String> genres;
  final String? sourceName;

  static LocalSeriesSource? fromJson(Object? data) => switch (data) {
    {
      'sourceId': final String source,
      'mangaId': final String manga,
      'locator': final String locator,
    }
        when source.isNotEmpty &&
            source.length <= 160 &&
            manga.isNotEmpty &&
            manga.length <= 128 &&
            locator.isNotEmpty &&
            locator.length <= 32768 =>
      LocalSeriesSource(
        sourceId: source,
        mangaId: manga,
        locator: locator,
        cover: _safeCover((data as Map)['cover']),
        genres: _safeGenres(data['genres']),
        sourceName: _safeFormatText(data['sourceName']),
      ),
    _ => null,
  };

  Map<String, Object> toJson({bool includeCover = true}) => {
    'sourceId': sourceId,
    'mangaId': mangaId,
    'locator': locator,
    if (includeCover && cover != null) 'cover': cover.toString(),
    if (genres.isNotEmpty) 'genres': _safeGenres(genres),
    'sourceName': ?_safeFormatText(sourceName),
  };

  static String? _safeFormatText(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 256 ? value : null;

  static List<String> _safeGenres(Object? value) => value is List
      ? List.unmodifiable(value.take(128).map(_safeFormatText).nonNulls)
      : const [];

  static Uri? _safeCover(Object? value) {
    if (value is! String || value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasFragment
        ? uri
        : null;
  }
}

class LocalSeries {
  LocalSeries({
    required this.id,
    required this.title,
    required List<LocalChapter> chapters,
    List<String> categories = const [],
    this.inLibrary = true,
    this.source,
    this.customCover,
  }) : chapters = List.unmodifiable(chapters),
       categories = List.unmodifiable(categories);

  final String id;
  final String title;
  final List<LocalChapter> chapters;
  final List<String> categories;
  final bool inLibrary;
  final LocalSeriesSource? source;

  /// A cover the user picked; shown before the source cover and pages.
  final File? customCover;
}

/// Read and bookmark state for a chapter, saved on this iPhone or not.
typedef LocalChapterMarks = ({bool read, bool bookmarked});

class LocalChapter {
  LocalChapter({
    required this.id,
    required this.title,
    required List<File> pages,
    this.progress = 0,
    this.bookmarked = false,
    this.lastReadAt,
  }) : pages = List.unmodifiable(pages);

  final String id;
  final String title;
  final List<File> pages;
  final int progress;
  final bool bookmarked;
  final DateTime? lastReadAt;
}

/// Personal details for a series, kept even when nothing of it is saved.
class LocalSeriesMeta {
  const LocalSeriesMeta({
    this.rating = 0,
    this.notes = '',
    this.tags = const [],
    this.cover,
  });

  /// 0 means unrated; otherwise 1–5 stars.
  final int rating;
  final String notes;
  final List<String> tags;

  /// A cover the user picked, stored with the catalog.
  final File? cover;
}

/// A chapter read straight from a source, kept for History without its pages.
class LocalRemoteRead {
  const LocalRemoteRead({
    required this.seriesId,
    required this.seriesTitle,
    required this.chapterId,
    required this.chapterTitle,
    required this.progress,
    required this.lastReadAt,
    this.source,
  });

  final String seriesId;
  final String seriesTitle;
  final LocalSeriesSource? source;
  final String chapterId;
  final String chapterTitle;
  final int progress;
  final DateTime lastReadAt;
}

class LocalTransferCancelled implements Exception {
  const LocalTransferCancelled();
}

/// Downloads only pages requested by the reader into its temporary directory.
class LocalPreviewPages {
  LocalPreviewPages({
    required Directory directory,
    required String chapterId,
    required String title,
    required List<Uri> urls,
    required List<Map<String, String>> headers,
    required http.Client client,
    required bool Function() isCancelled,
    int progress = 0,
  }) : _urls = List.unmodifiable(urls),
       _headers = headers
           .map(Map<String, String>.unmodifiable)
           .toList(growable: false),
       _client = client,
       _isCancelled = isCancelled,
       chapter = LocalChapter(
         id: chapterId,
         title: title,
         pages: List.generate(
           urls.length,
           (index) => File(p.join(directory.path, _pageName(index, '.image'))),
         ),
         progress: progress,
       ) {
    _validatePageList(_urls);
    _validatePageHeaders(_urls, _headers);
  }

  final LocalChapter chapter;
  final List<Uri> _urls;
  final List<Map<String, String>> _headers;
  final http.Client _client;
  final bool Function() _isCancelled;
  late final _indexByUri = {
    for (final (index, page) in chapter.pages.indexed)
      page.uri.toString(): index,
  };
  final _inFlight = <String, Future<File>>{};
  int _bytes = 0;

  Future<File> prepare(String fileUri) {
    final index = _indexByUri[fileUri];
    if (index == null) {
      return Future.error(ArgumentError('Unknown preview page.'));
    }
    final file = chapter.pages[index];
    return _inFlight.putIfAbsent(file.path, () async {
      try {
        _checkCancellation(_isCancelled);
        if (await file.exists()) return file;
        await file.parent.create(recursive: true);
        final remaining = _maxChapterBytes - _bytes;
        final downloaded = await _downloadPage(
          _urls[index],
          file,
          _client,
          remaining,
          _isCancelled,
          headers: _headers[index],
        );
        _checkCancellation(_isCancelled);
        if (_bytes + downloaded > _maxChapterBytes) {
          await file.delete();
          throw const FormatException('Chapter is too large.');
        }
        _bytes += downloaded;
        return file;
      } finally {
        unawaited(_inFlight.remove(file.path));
      }
    });
  }

  Future<void> settle() => Future.wait<void>([
    for (final future in _inFlight.values)
      future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  ]);
}

/// Runs [body] so that the catalog writes it makes stay out of the sync
/// outbox. The sync engine applies remote changes through it.
Future<T> runApplyingRemote<T>(Future<T> Function() body) =>
    runZoned(body, zoneValues: {_applyingRemote: true});

const _applyingRemote = #kuchieSyncApplying;

/// A device-owned library with no dependency on a server or authenticated session.
class LocalCatalog {
  LocalCatalog(this._root);

  final Directory _root;

  /// Whether writes add entries to the sync outbox (`sync_changes`). Set by
  /// the sync controller while a sync method is on.
  bool journalEnabled = false;

  /// Keeps reading progress out of the outbox while incognito mode is on.
  /// The reader already skips progress then; marks the reader sets by hand
  /// still sync.
  bool incognito = false;

  final _metadata = _SerialOperations();
  final _transfers = <String, _SerialOperations>{};
  late final Future<_CatalogDatabase> _database = _open();
  Directory get _pages => Directory(p.join(_root.path, 'pages'));
  Directory get _imports => Directory(p.join(_root.path, 'imports'));
  Directory get _downloads => Directory(p.join(_root.path, 'downloads'));
  Directory get _covers => Directory(p.join(_root.path, 'covers'));
  Directory get _sourceCovers =>
      Directory(p.join(_root.path, 'covers', 'source'));

  /// Where the source's own cover for [seriesId] is kept on this iPhone.
  ///
  /// Extensions that need cookies or a referrer serve covers through the
  /// runtime's loopback proxy, whose address changes every launch, so History
  /// and the library show this copy instead. The file may not exist.
  File sourceCoverFile(String seriesId) =>
      File(p.join(_sourceCovers.path, '${_hash(seriesId)}.img'));

  /// Names of the kept source covers, read once so lists never touch the
  /// disk while they build or scroll.
  Set<String>? _keptCovers;
  Future<void>? _keptCoversLoading;

  /// Reads which source covers are kept; [keptCover] answers from memory.
  Future<void> loadKeptCovers() => _keptCoversLoading ??= () async {
    final names = <String>{};
    try {
      if (await _sourceCovers.exists()) {
        await for (final entry in _sourceCovers.list()) {
          if (entry is File && entry.path.endsWith('.img')) {
            names.add(p.basename(entry.path));
          }
        }
      }
    } on FileSystemException {
      // No covers are known; History falls back to source links.
    }
    _keptCovers = {...?_keptCovers, ...names};
  }();

  /// The kept source cover of [seriesId], without disk access, or null when
  /// there is none or [loadKeptCovers] has not finished yet.
  File? keptCover(String seriesId) {
    final file = sourceCoverFile(seriesId);
    return _keptCovers?.contains(p.basename(file.path)) ?? false ? file : null;
  }

  /// Keeps [bytes] as the source cover for [seriesId], replacing any older one.
  /// The folder of source covers kept for History and the library.
  Directory get sourceCoverDirectory => _sourceCovers;

  /// Deletes every kept source cover; History and the library fall back to
  /// the source link or the first saved page.
  Future<void> clearSourceCovers() async {
    try {
      _keptCovers?.clear();
      if (await _sourceCovers.exists()) {
        await _sourceCovers.delete(recursive: true);
      }
    } on FileSystemException {
      // A cover written meanwhile is harmless.
    }
  }

  Future<void> saveSourceCover(String seriesId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _maxCoverBytes) return;
    final target = sourceCoverFile(seriesId);
    await target.parent.create(recursive: true);
    final partial = File('${target.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(target.path);
    (_keptCovers ??= {}).add(p.basename(target.path));
  }

  Future<_CatalogDatabase> _open() async {
    await _pages.create(recursive: true);
    await _imports.create(recursive: true);
    final database = _CatalogDatabase(
      NativeDatabase.createInBackground(
        File(p.join(_root.path, 'catalog.sqlite')),
      ),
    );
    try {
      await _recover(database);
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<void> _recover(_CatalogDatabase db) async {
    final pending = await db
        .customSelect('SELECT * FROM chapters WHERE ready = 0')
        .get();
    for (final row in pending) {
      final storage = row.read<String>('storage');
      final filenames = _decodePageNames(row.read<String>('page_names'));
      final allPagesExist = await Future.wait(
        filenames.map(
          (name) => File(p.join(_pages.path, storage, name)).exists(),
        ),
      );
      if (allPagesExist.isNotEmpty && allPagesExist.every((exists) => exists)) {
        await db.customStatement(
          'UPDATE chapters SET ready = 1 WHERE storage = ?',
          [storage],
        );
      } else {
        await db.customStatement('DELETE FROM chapters WHERE storage = ?', [
          storage,
        ]);
      }
    }
    await _removeEmptySeries(db);
    final stored = (await db.customSelect('SELECT storage FROM chapters').get())
        .map((row) => row.read<String>('storage'))
        .toSet();
    await for (final entity in _pages.list(followLinks: false)) {
      if (entity is Directory && !stored.contains(p.basename(entity.path))) {
        await entity.delete(recursive: true);
      }
    }
    await for (final entity in _imports.list(followLinks: false)) {
      if (entity is Directory) await entity.delete(recursive: true);
    }
  }

  Future<void> close() => _metadata.run(() async => (await _database).close());

  /// Runs [action] in one transaction on the catalog database, queued behind
  /// other catalog writes. Only the sync journal uses it, for its own tables.
  Future<T> withSyncTables<T>(
    Future<T> Function(DatabaseConnectionUser db) action,
  ) => _metadata.run(() async {
    final db = await _database;
    return db.transaction(() => action(db));
  });

  /// Records that the reader settings of [seriesId] changed. They live in
  /// SharedPreferences, so `LocalSeriesReaderMeta` calls this after a write.
  Future<void> recordReaderMetaChange(String seriesId) =>
      _metadata.run(() async {
        if (!_journals()) return;
        final db = await _database;
        await db.transaction(
          () => _journal(db, SyncRecordKind.readerMeta, [seriesId]),
        );
      });

  bool _journals({bool progress = false}) =>
      journalEnabled &&
      Zone.current[_applyingRemote] != true &&
      !(progress && incognito);

  // Called inside the transaction of the write it records.
  Future<void> _journal(
    _CatalogDatabase db,
    SyncRecordKind kind,
    Iterable<String> keys, {
    SyncChangeOp op = SyncChangeOp.upsert,
    bool progress = false,
  }) async {
    if (!_journals(progress: progress)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in keys) {
      await db.customStatement(_insertChange, [
        kind.storedName,
        key,
        op.name,
        now,
      ]);
    }
  }

  // The chapters of [seriesId] (or of every series) that History shows.
  Future<List<String>> _historyKeys(
    _CatalogDatabase db, [
    String? seriesId,
  ]) async {
    final where = seriesId == null ? '' : 'WHERE series_id = ?';
    final rows = await db
        .customSelect(
          '''
          SELECT series_id, chapter_id FROM remote_history $where
          UNION
          SELECT series_id, id AS chapter_id FROM chapters
          WHERE last_read_at IS NOT NULL
          ${seriesId == null ? '' : 'AND series_id = ?'}
          ORDER BY series_id, chapter_id
          ''',
          variables: [
            if (seriesId != null) ...[
              Variable.withString(seriesId),
              Variable.withString(seriesId),
            ],
          ],
        )
        .get();
    return [
      for (final row in rows)
        chapterStateKey(
          row.read<String>('series_id'),
          row.read<String>('chapter_id'),
        ),
    ];
  }

  Future<List<LocalSeries>> list() =>
      _metadata.run(() async => _list(await _database));

  Future<LocalSeries?> find(String id) => _metadata.run<LocalSeries?>(
    () async => (await _list(await _database, seriesId: id)).singleOrNull,
  );

  Future<void> setInLibrary({
    required String seriesId,
    required String title,
    required bool inLibrary,
    LocalSeriesSource? source,
  }) => _metadata.run(() async {
    final db = await _database;
    await db.transaction(() async {
      if (inLibrary) {
        await db.customStatement(
          '''
          INSERT INTO series (id, title, source, in_library)
          VALUES (?, ?, ?, 1)
          ON CONFLICT(id) DO UPDATE SET in_library = 1,
            source = COALESCE(excluded.source, series.source)
          ''',
          [
            seriesId,
            _nonEmptyName(title, 'title'),
            _encodeSeriesSource(source),
          ],
        );
      } else {
        await db.customStatement(
          'UPDATE series SET in_library = 0 WHERE id = ?',
          [seriesId],
        );
        await _removeEmptySeries(db);
      }
      await _journal(db, SyncRecordKind.series, [seriesId]);
    });
  });

  Future<List<LocalSeries>> _list(
    _CatalogDatabase db, {
    String? seriesId,
  }) async {
    final rows = await db
        .customSelect(
          '''
      SELECT s.id AS catalog_series_id, s.title AS series_title, s.in_library, s.source,
        m.cover AS custom_cover, c.*
      FROM series s
      LEFT JOIN series_meta m ON m.series_id = s.id
      LEFT JOIN chapters c ON c.series_id = s.id AND c.ready = 1
      ${seriesId == null ? '' : 'WHERE s.id = ?'}
      ORDER BY s.title COLLATE NOCASE, s.id, c.position
      ''',
          variables: [if (seriesId != null) Variable.withString(seriesId)],
        )
        .get();
    final byId =
        <
          String,
          ({
            String title,
            bool inLibrary,
            LocalSeriesSource? source,
            String? cover,
            List<LocalChapter> chapters,
          })
        >{};
    for (final row in rows) {
      final id = row.read<String>('catalog_series_id');
      final series = byId.putIfAbsent(
        id,
        () => (
          title: row.read<String>('series_title'),
          inLibrary: row.readNullable<int>('in_library') != 0,
          source: _decodeSeriesSource(row.readNullable<String>('source')),
          cover: row.readNullable<String>('custom_cover'),
          chapters: [],
        ),
      );
      if (row.readNullable<String>('storage') == null) continue;
      final storage = row.read<String>('storage');
      final lastReadAt = row.readNullable<int>('last_read_at');
      series.chapters.add(
        LocalChapter(
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          pages: _decodePageNames(
            row.read<String>('page_names'),
          ).map((name) => File(p.join(_pages.path, storage, name))).toList(),
          progress: row.read<int>('progress'),
          bookmarked: row.read<int>('bookmarked') != 0,
          lastReadAt: lastReadAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(lastReadAt),
        ),
      );
    }
    if (byId.isEmpty) return <LocalSeries>[];
    final memberships = await db
        .customSelect(
          '''
          SELECT series_id, name FROM series_categories
          ${seriesId == null ? '' : 'WHERE series_id = ?'}
          ORDER BY name COLLATE NOCASE, name
          ''',
          variables: [if (seriesId != null) Variable.withString(seriesId)],
        )
        .get();
    final bySeries = <String, List<String>>{};
    for (final row in memberships) {
      bySeries
          .putIfAbsent(row.read<String>('series_id'), () => [])
          .add(row.read<String>('name'));
    }
    return [
      for (final row in byId.entries)
        LocalSeries(
          id: row.key,
          title: row.value.title,
          chapters: row.value.chapters,
          categories: bySeries[row.key] ?? const [],
          inLibrary: row.value.inLibrary,
          source: row.value.source,
          customCover: switch (row.value.cover) {
            final name? => File(p.join(_covers.path, name)),
            null => null,
          },
        ),
    ];
  }

  Future<LocalSeries> importArchive(File file, {String? seriesId}) {
    final title = p.basenameWithoutExtension(file.path);
    return _import(file.path, title, seriesId, _extractArchive);
  }

  Future<LocalSeries> importFolder(Directory folder, {String? seriesId}) {
    final title = p.basename(p.normalize(folder.path));
    return _import(folder.path, title, seriesId, _copyImageFolder);
  }

  Future<LocalSeries> _import(
    String source,
    String title,
    String? seriesId,
    List<String> Function(String source, String destination) stage,
  ) async {
    final db = await _database;
    final staging = await _imports.createTemp('chapter-');
    try {
      final (filenames, fingerprint) = await _stageImport(
        source,
        staging.path,
        stage,
      );
      return await _metadata.run(() async {
        if (seriesId != null && (await _list(db, seriesId: seriesId)).isEmpty) {
          throw StateError('The selected series no longer exists.');
        }
        final duplicate = await db
            .customSelect(
              '''
          SELECT series_id FROM chapters WHERE fingerprint = ? AND ready = 1
          ${seriesId == null ? '' : 'AND series_id = ?'} LIMIT 1
          ''',
              variables: [
                Variable.withString(fingerprint),
                if (seriesId != null) Variable.withString(seriesId),
              ],
            )
            .getSingleOrNull();
        if (duplicate != null) {
          return (await _list(
            db,
            seriesId: duplicate.read<String>('series_id'),
          )).single;
        }
        final id = seriesId ?? const Uuid().v4();
        return _publish(
          db,
          seriesId: id,
          seriesTitle: title,
          chapterId: const Uuid().v4(),
          chapterTitle: title,
          staging: staging,
          filenames: filenames,
          fingerprint: fingerprint,
        );
      });
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<LocalSeries> saveRemoteChapter({
    required String seriesId,
    required String title,
    required String chapterId,
    required String chapterTitle,
    required List<Uri> pages,
    List<Map<String, String>>? pageHeaders,
    required http.Client client,
    LocalSeriesSource? source,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    final id = _downloadId(seriesId, chapterId);
    return _withTransfer(id, () async {
      _validatePageList(pages);
      _validatePageHeaders(pages, pageHeaders);
      final db = await _database;
      final existing = await _metadata.run(() => _list(db, seriesId: seriesId));
      if (existing.isNotEmpty &&
          existing.single.chapters.any((chapter) => chapter.id == chapterId)) {
        onProgress?.call(pages.length, pages.length);
        return existing.single;
      }
      final staging = Directory(p.join(_downloads.path, id));
      final fingerprint = _hash(
        jsonEncode(pages.map((page) => page.toString()).toList()),
      );
      await _prepareDownload(staging, fingerprint);
      final filenames = await _transferPages(
        staging,
        pages,
        client,
        pageHeaders: pageHeaders,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      return _metadata.run(() {
        _checkCancellation(isCancelled);
        return _publish(
          db,
          seriesId: seriesId,
          seriesTitle: title,
          chapterId: chapterId,
          chapterTitle: chapterTitle,
          staging: staging,
          filenames: filenames,
          source: source,
        );
      });
    });
  }

  /// Fetches a chapter into a dedicated empty directory owned by the caller.
  Future<LocalChapter> previewRemoteChapter({
    required Directory directory,
    required String chapterId,
    required String title,
    required List<Uri> pages,
    List<Map<String, String>>? pageHeaders,
    required http.Client client,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _validatePageList(pages);
    _validatePageHeaders(pages, pageHeaders);
    _checkCancellation(isCancelled);
    await directory.create(recursive: true);
    if (!await directory.list(followLinks: false).isEmpty) {
      throw ArgumentError('The preview directory must be empty.');
    }
    final filenames = await _transferPages(
      directory,
      pages,
      client,
      pageHeaders: pageHeaders,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return LocalChapter(
      id: chapterId,
      title: title,
      pages: filenames
          .map((name) => File(p.join(directory.path, name)))
          .toList(),
    );
  }

  Future<void> purgePartialRemoteChapter(String seriesId, String chapterId) {
    final id = _downloadId(seriesId, chapterId);
    return _withTransfer(id, () async {
      final staging = Directory(p.join(_downloads.path, id));
      if (await staging.exists()) await staging.delete(recursive: true);
    });
  }

  Future<T> _withTransfer<T>(String id, Future<T> Function() operation) {
    final queue = _transfers.putIfAbsent(id, _SerialOperations.new);
    return queue.run(operation).whenComplete(() {
      if (queue.isIdle && identical(_transfers[id], queue)) {
        _transfers.remove(id);
      }
    });
  }

  Future<LocalSeries> _publish(
    _CatalogDatabase db, {
    required String seriesId,
    required String seriesTitle,
    required String chapterId,
    required String chapterTitle,
    required Directory staging,
    required List<String> filenames,
    String? fingerprint,
    LocalSeriesSource? source,
  }) async {
    final storage = const Uuid().v4();
    await db.transaction(() async {
      await db.customStatement(
        '''
        INSERT INTO series (id, title, source) VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET source = COALESCE(excluded.source, series.source)
        ''',
        [seriesId, seriesTitle, _encodeSeriesSource(source)],
      );
      await db.customStatement(
        '''
        INSERT INTO chapters (series_id, id, title, storage, page_names, fingerprint, position)
        VALUES (?, ?, ?, ?, ?, ?, (SELECT COALESCE(MAX(position), 0) + 1 FROM chapters WHERE series_id = ?))
        ''',
        [
          seriesId,
          chapterId,
          chapterTitle,
          storage,
          jsonEncode(filenames),
          fingerprint,
          seriesId,
        ],
      );
    });
    try {
      await staging.rename(p.join(_pages.path, storage));
    } catch (_) {
      await db.transaction(() async {
        await db.customStatement('DELETE FROM chapters WHERE storage = ?', [
          storage,
        ]);
        await _removeEmptySeries(db);
      });
      rethrow;
    }
    await db.customStatement(
      'UPDATE chapters SET ready = 1 WHERE storage = ?',
      [storage],
    );
    return (await _list(db, seriesId: seriesId)).single;
  }

  Future<void> setProgress(
    String seriesId,
    String chapterId,
    int index,
  ) => _metadata.run(() async {
    final db = await _database;
    final row = await db
        .customSelect(
          'SELECT page_names FROM chapters WHERE series_id = ? AND id = ? AND ready = 1',
          variables: [
            Variable.withString(seriesId),
            Variable.withString(chapterId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return;
    final pageCount = _decodePageNames(row.read<String>('page_names')).length;
    final page = index.clamp(0, pageCount - 1);
    await db.transaction(() async {
      await db.customStatement(
        'UPDATE chapters SET progress = ?, last_read_at = ? WHERE series_id = ? AND id = ?',
        [page, DateTime.now().millisecondsSinceEpoch, seriesId, chapterId],
      );
      await _journal(db, SyncRecordKind.chapterState, [
        chapterStateKey(seriesId, chapterId),
      ], progress: true);
    });
  });

  /// Kept apart from [setProgress] so online reads never touch saved files.
  Future<void> recordRemoteRead({
    required LocalSeries series,
    required String chapterId,
    required String chapterTitle,
    required int progress,
  }) => _metadata.run(() async {
    final db = await _database;
    await db.transaction(() async {
      await db.customStatement(
        '''
      INSERT INTO remote_history
        (series_id, series_title, source, chapter_id, chapter_title, progress, last_read_at)
      -- Reads within one millisecond still order newest first in History.
      VALUES (?, ?, ?, ?, ?, ?,
        MAX(?, COALESCE((SELECT MAX(last_read_at) FROM remote_history), 0) + 1))
      ON CONFLICT(series_id, chapter_id) DO UPDATE SET
        series_title = excluded.series_title,
        source = COALESCE(excluded.source, remote_history.source),
        chapter_title = excluded.chapter_title,
        progress = excluded.progress,
        last_read_at = excluded.last_read_at
      ''',
        [
          series.id,
          _nonEmptyName(series.title, 'title'),
          _encodeSeriesSource(series.source),
          chapterId,
          _nonEmptyName(chapterTitle, 'chapterTitle'),
          progress < 0 ? 0 : progress,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      await _journal(db, SyncRecordKind.chapterState, [
        chapterStateKey(series.id, chapterId),
      ], progress: true);
    });
  });

  /// Takes a series off History. Saved pages and reading progress stay.
  /// Sync sends the cleared read times; the server keeps its History.
  Future<void> removeFromHistory(String seriesId) => _metadata.run(() async {
    final db = await _database;
    await db.transaction(() async {
      final keys = _journals() ? await _historyKeys(db, seriesId) : <String>[];
      await db.customStatement(
        'DELETE FROM remote_history WHERE series_id = ?',
        [seriesId],
      );
      await db.customStatement(
        'UPDATE chapters SET last_read_at = NULL WHERE series_id = ?',
        [seriesId],
      );
      await _journal(db, SyncRecordKind.chapterState, keys);
    });
  });

  /// Empties History. Saved pages and reading progress stay.
  /// Sync sends the cleared read times; the server keeps its History.
  Future<void> clearHistory() => _metadata.run(() async {
    final db = await _database;
    await db.transaction(() async {
      final keys = _journals() ? await _historyKeys(db) : <String>[];
      await db.customStatement('DELETE FROM remote_history');
      await db.customStatement('UPDATE chapters SET last_read_at = NULL');
      await _journal(db, SyncRecordKind.chapterState, keys);
    });
  });

  /// Newest first.
  Future<List<LocalRemoteRead>> remoteHistory() => _metadata.run(() async {
    final db = await _database;
    final rows = await db
        .customSelect(
          'SELECT * FROM remote_history ORDER BY last_read_at DESC LIMIT 500',
        )
        .get();
    return [for (final row in rows) _remoteRead(row)];
  });

  /// The chapter of [seriesId] last read online, if any.
  Future<LocalRemoteRead?> lastRemoteRead(String seriesId) =>
      _metadata.run(() async {
        final db = await _database;
        final row = await db
            .customSelect(
              'SELECT * FROM remote_history WHERE series_id = ? '
              'ORDER BY last_read_at DESC LIMIT 1',
              variables: [Variable.withString(seriesId)],
            )
            .getSingleOrNull();
        return row == null ? null : _remoteRead(row);
      });

  LocalRemoteRead _remoteRead(QueryRow row) => LocalRemoteRead(
    seriesId: row.read<String>('series_id'),
    seriesTitle: row.read<String>('series_title'),
    source: _decodeSeriesSource(row.readNullable<String>('source')),
    chapterId: row.read<String>('chapter_id'),
    chapterTitle: row.read<String>('chapter_title'),
    progress: row.read<int>('progress'),
    lastReadAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('last_read_at'),
    ),
  );

  Future<int> remoteProgress(
    String seriesId,
    String chapterId,
  ) => _metadata.run(() async {
    final db = await _database;
    final row = await db
        .customSelect(
          'SELECT progress FROM remote_history WHERE series_id = ? AND chapter_id = ?',
          variables: [
            Variable.withString(seriesId),
            Variable.withString(chapterId),
          ],
        )
        .getSingleOrNull();
    return row?.read<int>('progress') ?? 0;
  });

  Future<LocalSeriesMeta> seriesMeta(String seriesId) =>
      _metadata.run(() async {
        final db = await _database;
        final row = await db
            .customSelect(
              'SELECT * FROM series_meta WHERE series_id = ?',
              variables: [Variable.withString(seriesId)],
            )
            .getSingleOrNull();
        if (row == null) return const LocalSeriesMeta();
        final cover = row.readNullable<String>('cover');
        return LocalSeriesMeta(
          rating: row.read<int>('rating'),
          notes: row.read<String>('notes'),
          tags: _decodeTags(row.read<String>('tags')),
          cover: cover == null ? null : File(p.join(_covers.path, cover)),
        );
      });

  Future<void> setRating(String seriesId, int rating) =>
      _updateMeta(seriesId, 'rating', rating.clamp(0, 5));

  Future<void> setNotes(String seriesId, String notes) => _updateMeta(
    seriesId,
    'notes',
    notes.length > _maxNotesLength
        ? notes.substring(0, _maxNotesLength)
        : notes,
  );

  /// Trims, drops blanks and duplicates (case-insensitive), keeps the order.
  Future<void> setTags(String seriesId, List<String> tags) {
    final seen = <String>{};
    final cleaned = [
      for (final tag in tags.map((tag) => tag.trim()))
        if (tag.isNotEmpty && tag.length <= 64 && seen.add(tag.toLowerCase()))
          tag,
    ].take(64).toList();
    return _updateMeta(seriesId, 'tags', jsonEncode(cleaned));
  }

  // [column] is always a literal from this file, never user input.
  Future<void> _updateMeta(String seriesId, String column, Object value) =>
      _metadata.run(() async {
        final db = await _database;
        await db.transaction(() async {
          await db.customStatement(
            '''
            INSERT INTO series_meta (series_id, $column) VALUES (?, ?)
            ON CONFLICT(series_id) DO UPDATE SET $column = excluded.$column
            ''',
            [seriesId, value],
          );
          await _journal(db, SyncRecordKind.seriesMeta, [seriesId]);
        });
      });

  /// Saved chapters report their own bookmark; marks cover the rest.
  Future<Map<String, LocalChapterMarks>> chapterMarks(
    String seriesId,
  ) => _metadata.run(() async {
    final db = await _database;
    final marks = <String, LocalChapterMarks>{
      for (final row
          in await db
              .customSelect(
                'SELECT chapter_id, read, bookmarked FROM chapter_marks WHERE series_id = ?',
                variables: [Variable.withString(seriesId)],
              )
              .get())
        row.read<String>('chapter_id'): (
          read: row.read<int>('read') != 0,
          bookmarked: row.read<int>('bookmarked') != 0,
        ),
    };
    for (final row
        in await db
            .customSelect(
              'SELECT id, bookmarked FROM chapters WHERE series_id = ? AND ready = 1 AND bookmarked = 1',
              variables: [Variable.withString(seriesId)],
            )
            .get()) {
      final id = row.read<String>('id');
      marks[id] = (read: marks[id]?.read ?? false, bookmarked: true);
    }
    return marks;
  });

  /// Leaves a field unchanged when it is null.
  Future<void> setChapterMarks(
    String seriesId,
    Iterable<String> chapterIds, {
    bool? read,
    bool? bookmarked,
  }) => _metadata.run(() async {
    if (read == null && bookmarked == null) return;
    final db = await _database;
    final ids = chapterIds.toSet();
    await db.transaction(() async {
      for (final id in ids) {
        await db.customStatement(
          '''
          INSERT INTO chapter_marks (series_id, chapter_id, read, bookmarked)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(series_id, chapter_id) DO UPDATE SET
            read = COALESCE(?, chapter_marks.read),
            bookmarked = COALESCE(?, chapter_marks.bookmarked)
          ''',
          [
            seriesId,
            id,
            read == true ? 1 : 0,
            bookmarked == true ? 1 : 0,
            read == null ? null : (read ? 1 : 0),
            bookmarked == null ? null : (bookmarked ? 1 : 0),
          ],
        );
        if (bookmarked != null) {
          await db.customStatement(
            'UPDATE chapters SET bookmarked = ? WHERE series_id = ? AND id = ? AND ready = 1',
            [bookmarked ? 1 : 0, seriesId, id],
          );
        }
      }
      await _journal(db, SyncRecordKind.chapterState, [
        for (final id in ids) chapterStateKey(seriesId, id),
      ]);
    });
  });

  /// Copies [image] into the catalog, or removes the custom cover when null.
  Future<void> setCover(String seriesId, File? image) =>
      _metadata.run(() async {
        final db = await _database;
        final previous = await db
            .customSelect(
              'SELECT cover FROM series_meta WHERE series_id = ?',
              variables: [Variable.withString(seriesId)],
            )
            .getSingleOrNull();
        String? name;
        if (image != null) {
          final length = await image.length();
          if (length == 0 || length > _maxCoverBytes) {
            throw const FormatException('The image is empty or too large.');
          }
          await _covers.create(recursive: true);
          name = '${const Uuid().v4()}${_coverExtension(image.path)}';
          await image.copy(p.join(_covers.path, name));
        }
        await db.customStatement(
          '''
          INSERT INTO series_meta (series_id, cover) VALUES (?, ?)
          ON CONFLICT(series_id) DO UPDATE SET cover = excluded.cover
          ''',
          [seriesId, name],
        );
        if (previous?.readNullable<String>('cover') case final old?) {
          final file = File(p.join(_covers.path, old));
          if (await file.exists()) await file.delete();
        }
      });

  Future<void> setBookmark(
    String seriesId,
    String chapterId,
    bool bookmarked,
  ) => _metadata.run(() async {
    final db = await _database;
    await db.transaction(() async {
      final changed = await db.customUpdate(
        'UPDATE chapters SET bookmarked = ? WHERE series_id = ? AND id = ? AND ready = 1',
        variables: [
          Variable.withInt(bookmarked ? 1 : 0),
          Variable.withString(seriesId),
          Variable.withString(chapterId),
        ],
      );
      if (changed == 0) return;
      await _journal(db, SyncRecordKind.chapterState, [
        chapterStateKey(seriesId, chapterId),
      ]);
    });
  });

  Future<List<String>> categories() => _metadata.run(() async {
    final db = await _database;
    final rows = await db
        .customSelect(
          'SELECT name FROM categories ORDER BY name COLLATE NOCASE, name',
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toList();
  });

  Future<void> createCategory(String name) => _metadata.run(() async {
    final db = await _database;
    final trimmed = _nonEmptyName(name, 'name');
    await db.transaction(() async {
      await db.customStatement(
        'INSERT OR IGNORE INTO categories (name) VALUES (?)',
        [trimmed],
      );
      await _journal(db, SyncRecordKind.category, [categoryKey(trimmed)]);
    });
  });

  /// Series in the category leave it, so their membership is recorded too.
  Future<void> deleteCategory(String name) => _metadata.run(() async {
    final db = await _database;
    final trimmed = name.trim();
    await db.transaction(() async {
      final members = _journals()
          ? [
              for (final row
                  in await db
                      .customSelect(
                        'SELECT series_id FROM series_categories WHERE name = ? ORDER BY series_id',
                        variables: [Variable.withString(trimmed)],
                      )
                      .get())
                row.read<String>('series_id'),
            ]
          : const <String>[];
      final deleted = await db.customUpdate(
        'DELETE FROM categories WHERE name = ?',
        variables: [Variable.withString(trimmed)],
      );
      if (deleted == 0) return;
      await _journal(db, SyncRecordKind.category, [
        categoryKey(trimmed),
      ], op: SyncChangeOp.delete);
      await _journal(db, SyncRecordKind.membership, members);
    });
  });

  Future<void> setCategories(String seriesId, List<String> categories) {
    final names = categories
        .map((name) => _nonEmptyName(name, 'category'))
        .toSet();
    return _metadata.run(() async {
      final db = await _database;
      await db.transaction(() async {
        await db.customStatement(
          'DELETE FROM series_categories WHERE series_id = ?',
          [seriesId],
        );
        for (final name in names) {
          await db.customStatement(
            'INSERT INTO series_categories (series_id, name) VALUES (?, ?)',
            [seriesId, name],
          );
        }
        await _journal(db, SyncRecordKind.membership, [seriesId]);
      });
    });
  }

  Future<void> renameSeries(String seriesId, String title) =>
      _metadata.run(() async {
        final db = await _database;
        await db.customStatement('UPDATE series SET title = ? WHERE id = ?', [
          _nonEmptyName(title, 'title'),
          seriesId,
        ]);
      });

  /// Exports library, category and reading metadata. Page files stay on the device.
  Future<void> exportMetadata(File destination) async {
    final contents = await _metadata.run(() async {
      final db = await _database;
      final categories = await db
          .customSelect('SELECT name FROM categories')
          .get();
      final memberships = await db
          .customSelect('SELECT series_id, name FROM series_categories')
          .get();
      final chapters = await db.customSelect('''
        SELECT series_id, id, fingerprint, progress, bookmarked, last_read_at
        FROM chapters WHERE ready = 1
        ''').get();
      final favorites = await db.customSelect('''
        SELECT id, title, source FROM series WHERE in_library = 1 AND source IS NOT NULL
        ''').get();
      return {
        'format': 'kuchie.local.metadata',
        'version': 2,
        'categories': categories
            .map((row) => row.read<String>('name'))
            .toList(),
        'memberships': memberships.map((row) => row.data).toList(),
        'chapters': chapters.map((row) => row.data).toList(),
        'favorites': [
          for (final row in favorites)
            {
              'id': row.read<String>('id'),
              'title': row.read<String>('title'),
              'source': _decodeSeriesSource(
                row.read<String>('source'),
              )!.toJson(includeCover: false),
            },
        ],
      };
    });
    final staging = File('${destination.path}.${const Uuid().v4()}.part');
    try {
      final bytes = utf8.encode(jsonEncode(contents));
      if (bytes.length > _maxBackupBytes) {
        throw const FormatException('The metadata backup is too large.');
      }
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(destination.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  /// Restores library favorites and merges metadata for chapters on this device.
  Future<({int restored, int skipped})> restoreMetadata(File source) async {
    final input = await source.open();
    late final _MetadataBackup backup;
    try {
      final length = await input.length();
      if (length > _maxBackupBytes) {
        throw const FormatException('The metadata backup is too large.');
      }
      backup = _MetadataBackup.parse(await input.read(length));
    } finally {
      await input.close();
    }
    return _metadata.run(() async {
      final db = await _database;
      final rows = await db.customSelect('''
        SELECT series_id, id, fingerprint, page_names
        FROM chapters WHERE ready = 1
        ''').get();
      final byId = <(String, String), QueryRow>{};
      final byFingerprint = <String, List<QueryRow>>{};
      for (final row in rows) {
        byId[(row.read<String>('series_id'), row.read<String>('id'))] = row;
        final fingerprint = row.readNullable<String>('fingerprint');
        if (fingerprint != null) {
          byFingerprint.putIfAbsent(fingerprint, () => []).add(row);
        }
      }
      final existingFavorites = (await db.customSelect('''
        SELECT id FROM series WHERE in_library IS NULL OR in_library = 1
        ''').get()).map((row) => row.read<String>('id')).toSet();
      final existingSeries =
          (await db.customSelect('SELECT id FROM series').get())
              .map((row) => row.read<String>('id'))
              .toSet();
      final matchedSeries = <String, Set<String>>{};
      final restoredChapters = <String>{};
      var restored = 0;
      final journals = _journals();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.batch((batch) {
        for (final name in backup.categories) {
          batch.customStatement(
            'INSERT OR IGNORE INTO categories (name) VALUES (?)',
            [name],
          );
        }
        for (final favorite in backup.favorites) {
          final id = favorite.id;
          if (!existingSeries.contains(id) || existingFavorites.contains(id)) {
            matchedSeries.putIfAbsent(id, () => {}).add(id);
          }
          batch.customStatement(
            '''
            INSERT INTO series (id, title, in_library, source) VALUES (?, ?, 1, ?)
            ON CONFLICT(id) DO UPDATE SET in_library = 1,
              source = COALESCE(series.source, excluded.source)
            WHERE series.in_library IS NULL
            ''',
            [id, favorite.title, _encodeSeriesSource(favorite.source)],
          );
        }
        for (final chapter in backup.chapters) {
          final row =
              byId[(chapter.seriesId, chapter.id)] ??
              byFingerprint[chapter.fingerprint]?.singleOrNull;
          if (row == null) continue;
          restored++;
          final seriesId = row.read<String>('series_id');
          final id = row.read<String>('id');
          matchedSeries.putIfAbsent(chapter.seriesId, () => {}).add(seriesId);
          restoredChapters.add(chapterStateKey(seriesId, id));
          if (chapter.bookmarked) {
            batch.customStatement(
              'UPDATE chapters SET bookmarked = 1 WHERE series_id = ? AND id = ?',
              [seriesId, id],
            );
          }
          final lastReadAt = chapter.lastReadAt;
          if (lastReadAt != null) {
            final pageCount = _decodePageNames(
              row.read<String>('page_names'),
            ).length;
            batch.customStatement(
              '''
              UPDATE chapters SET progress = ?, last_read_at = ?
              WHERE series_id = ? AND id = ? AND (last_read_at IS NULL OR last_read_at < ?)
              ''',
              [
                chapter.progress.clamp(0, pageCount - 1),
                lastReadAt,
                seriesId,
                id,
                lastReadAt,
              ],
            );
          }
        }
        final members = <String>{};
        for (final (seriesId, name) in backup.memberships) {
          for (final matched in matchedSeries[seriesId] ?? const <String>{}) {
            members.add(matched);
            batch.customStatement(
              'INSERT OR IGNORE INTO series_categories (series_id, name) VALUES (?, ?)',
              [matched, name],
            );
          }
        }
        if (!journals) return;
        void journal(SyncRecordKind kind, Iterable<String> keys) {
          for (final key in keys) {
            batch.customStatement(_insertChange, [
              kind.storedName,
              key,
              SyncChangeOp.upsert.name,
              now,
            ]);
          }
        }

        journal(SyncRecordKind.category, {
          for (final name in backup.categories) categoryKey(name),
        });
        journal(SyncRecordKind.series, {
          for (final favorite in backup.favorites) favorite.id,
        });
        journal(SyncRecordKind.chapterState, restoredChapters);
        journal(SyncRecordKind.membership, members);
      });
      return (restored: restored, skipped: backup.chapters.length - restored);
    });
  }

  Future<void> removeChapter(String seriesId, String chapterId) {
    final id = _downloadId(seriesId, chapterId);
    return _withTransfer(
      id,
      () => _metadata.run(() async {
        final db = await _database;
        final row = await db
            .customSelect(
              'SELECT storage FROM chapters WHERE series_id = ? AND id = ?',
              variables: [
                Variable.withString(seriesId),
                Variable.withString(chapterId),
              ],
            )
            .getSingleOrNull();
        if (row != null) {
          await db.transaction(() async {
            await db.customStatement(
              'DELETE FROM chapters WHERE series_id = ? AND id = ?',
              [seriesId, chapterId],
            );
            await _removeEmptySeries(db);
          });
          final stored = Directory(
            p.join(_pages.path, row.read<String>('storage')),
          );
          if (await stored.exists()) await stored.delete(recursive: true);
        }
        final partial = Directory(p.join(_downloads.path, id));
        if (await partial.exists()) await partial.delete(recursive: true);
      }),
    );
  }
}

typedef _ChapterMetadata = ({
  String seriesId,
  String id,
  String? fingerprint,
  int progress,
  bool bookmarked,
  int? lastReadAt,
});

typedef _FavoriteMetadata = ({
  String id,
  String title,
  LocalSeriesSource source,
});

class _MetadataBackup {
  _MetadataBackup(
    this.categories,
    this.memberships,
    this.chapters,
    this.favorites,
  );

  final Set<String> categories;
  final List<(String, String)> memberships;
  final List<_ChapterMetadata> chapters;
  final List<_FavoriteMetadata> favorites;

  factory _MetadataBackup.parse(List<int> bytes) {
    const invalid = FormatException('Invalid Kuchie Local metadata backup.');
    if (bytes.length > _maxBackupBytes) throw invalid;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded case {
      'format': 'kuchie.local.metadata',
      'version': final int version,
      'categories': List<dynamic> savedCategories,
      'memberships': List<dynamic> savedMemberships,
      'chapters': List<dynamic> savedChapters,
    } when version == 1 || version == 2) {
      final categories = <String>{};
      for (final name in savedCategories) {
        if (name is! String || name.trim().isEmpty || name.trim() != name) {
          throw invalid;
        }
        categories.add(name);
      }
      final memberships = <(String, String)>[];
      for (final row in savedMemberships) {
        if (row case {
          'series_id': String id,
          'name': String name,
        } when id.isNotEmpty && categories.contains(name)) {
          memberships.add((id, name));
        } else {
          throw invalid;
        }
      }
      final chapters = <_ChapterMetadata>[];
      final seen = <(String, String)>{};
      for (final row in savedChapters) {
        if (row
            case {
              'series_id': String seriesId,
              'id': String id,
              'fingerprint': final String? fingerprint,
              'progress': int progress,
              'bookmarked': int bookmarked,
              'last_read_at': final int? lastReadAt,
            }
            when seriesId.isNotEmpty &&
                id.isNotEmpty &&
                progress >= 0 &&
                (bookmarked == 0 || bookmarked == 1) &&
                (lastReadAt == null || lastReadAt >= 0) &&
                seen.add((seriesId, id))) {
          chapters.add((
            seriesId: seriesId,
            id: id,
            fingerprint: fingerprint,
            progress: progress,
            bookmarked: bookmarked == 1,
            lastReadAt: lastReadAt,
          ));
        } else {
          throw invalid;
        }
      }
      final favorites = <_FavoriteMetadata>[];
      if (version == 2) {
        final saved = decoded['favorites'];
        if (saved is! List<dynamic>) throw invalid;
        final seenFavorites = <String>{};
        for (final row in saved) {
          if (row
              case {
                'id': final String id,
                'title': final String title,
                'source': final Object source,
              }
              when id.isNotEmpty &&
                  id.length <= 2048 &&
                  title.trim().isNotEmpty &&
                  title.length <= 384 &&
                  seenFavorites.add(id)) {
            final parsed = LocalSeriesSource.fromJson(source);
            if (parsed == null) throw invalid;
            favorites.add((id: id, title: title, source: parsed));
          } else {
            throw invalid;
          }
        }
      }
      return _MetadataBackup(categories, memberships, chapters, favorites);
    }
    throw invalid;
  }
}

class _CatalogDatabase extends GeneratedDatabase {
  _CatalogDatabase(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE series (id TEXT PRIMARY KEY, title TEXT NOT NULL, in_library INTEGER, source TEXT)',
      );
      await customStatement('''
      CREATE TABLE chapters (
        series_id TEXT NOT NULL REFERENCES series(id),
        id TEXT NOT NULL,
        title TEXT NOT NULL,
        storage TEXT NOT NULL UNIQUE,
        page_names TEXT NOT NULL,
        fingerprint TEXT,
        position INTEGER NOT NULL,
        ready INTEGER NOT NULL DEFAULT 0,
        progress INTEGER NOT NULL DEFAULT 0,
        bookmarked INTEGER NOT NULL DEFAULT 0,
        last_read_at INTEGER,
        PRIMARY KEY (series_id, id)
      )
      ''');
      await customStatement(
        'CREATE INDEX chapters_import_fingerprint ON chapters(fingerprint)',
      );
      await _createCategories();
      await _createRemoteHistory();
      await _createSeriesMeta();
      await _createChapterMarks();
      await _createSyncTables();
    },
    onUpgrade: (_, from, to) async {
      await transaction(() async {
        if (from < 2) await _createCategories();
        if (from < 3) {
          final columns = {
            for (final row in await customSelect(
              'PRAGMA table_info(series)',
            ).get())
              row.read<String>('name'),
          };
          if (!columns.contains('in_library')) {
            await customStatement(
              'ALTER TABLE series ADD COLUMN in_library INTEGER',
            );
          }
          if (!columns.contains('source')) {
            await customStatement('ALTER TABLE series ADD COLUMN source TEXT');
          }
        }
        if (from < 4) await _createRemoteHistory();
        if (from < 5) await _createSeriesMeta();
        if (from < 6) await _createChapterMarks();
        if (from < 7) await _createSyncTables();
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // The sync outbox, what each local key is called on a backend, the last
  // state both sides agreed on, and chapters waiting to move between them.
  // No foreign keys: sync also covers series that aren't saved here.
  Future<void> _createSyncTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_changes (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        key TEXT NOT NULL,
        op TEXT NOT NULL,
        changed_at INTEGER NOT NULL
      )
      ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_changes_key ON sync_changes(kind, key)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_links (
        backend TEXT NOT NULL,
        kind TEXT NOT NULL,
        local_key TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        PRIMARY KEY (backend, kind, local_key)
      )
      ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_links_remote ON sync_links(backend, kind, remote_id)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_base (
        backend TEXT NOT NULL,
        kind TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY (backend, kind, key)
      )
      ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_transfers (
        series_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        remote_chapter_id INTEGER,
        keep_local INTEGER NOT NULL,
        state TEXT NOT NULL,
        error TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (series_id, chapter_id)
      )
      ''');
  }

  // No foreign key: ratings and notes also apply to series that aren't saved.
  Future<void> _createChapterMarks() => customStatement('''
    CREATE TABLE IF NOT EXISTS chapter_marks (
      series_id TEXT NOT NULL,
      chapter_id TEXT NOT NULL,
      read INTEGER NOT NULL DEFAULT 0,
      bookmarked INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (series_id, chapter_id)
    )
    ''');

  Future<void> _createSeriesMeta() => customStatement('''
    CREATE TABLE IF NOT EXISTS series_meta (
      series_id TEXT PRIMARY KEY,
      rating INTEGER NOT NULL DEFAULT 0,
      notes TEXT NOT NULL DEFAULT '',
      tags TEXT NOT NULL DEFAULT '[]',
      cover TEXT
    )
    ''');

  // No foreign key: History outlives the series row and its saved chapters.
  Future<void> _createRemoteHistory() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS remote_history (
        series_id TEXT NOT NULL,
        series_title TEXT NOT NULL,
        source TEXT,
        chapter_id TEXT NOT NULL,
        chapter_title TEXT NOT NULL,
        progress INTEGER NOT NULL DEFAULT 0,
        last_read_at INTEGER NOT NULL,
        PRIMARY KEY (series_id, chapter_id)
      )
      ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS remote_history_read_at ON remote_history(last_read_at)',
    );
  }

  Future<void> _createCategories() async {
    await customStatement('CREATE TABLE categories (name TEXT PRIMARY KEY)');
    await customStatement('''
      CREATE TABLE series_categories (
        series_id TEXT NOT NULL REFERENCES series(id) ON DELETE CASCADE,
        name TEXT NOT NULL REFERENCES categories(name) ON DELETE CASCADE,
        PRIMARY KEY (series_id, name)
      )
      ''');
    await customStatement(
      'CREATE INDEX series_categories_name ON series_categories(name)',
    );
  }
}

class _SerialOperations {
  Future<void> _tail = Future.value();
  int _size = 0;
  bool get isIdle => _size == 0;

  Future<T> run<T>(Future<T> Function() operation) {
    _size++;
    final result = _tail.then((_) => operation()).whenComplete(() => _size--);
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

const _maxNotesLength = 20000;
const _maxCoverBytes = 20 * 1024 * 1024;

String _coverExtension(String path) {
  final extension = p.extension(path).toLowerCase();
  return const {
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.heic',
        '.gif',
      }.contains(extension)
      ? extension
      : '.image';
}

List<String> _decodeTags(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is List
        ? List.unmodifiable(decoded.whereType<String>().take(64))
        : const [];
  } on FormatException {
    return const [];
  }
}

Future<void> _removeEmptySeries(_CatalogDatabase db) => db.customStatement('''
  DELETE FROM series WHERE in_library IS NULL
  AND NOT EXISTS (SELECT 1 FROM chapters WHERE chapters.series_id = series.id)
  ''');

String? _encodeSeriesSource(LocalSeriesSource? source) =>
    source == null ? null : jsonEncode(source.toJson());

LocalSeriesSource? _decodeSeriesSource(String? source) =>
    source == null ? null : LocalSeriesSource.fromJson(jsonDecode(source));

String _nonEmptyName(String value, String argument) {
  final name = value.trim();
  if (name.isEmpty) {
    throw ArgumentError.value(value, argument, 'Cannot be empty');
  }
  return name;
}

List<String> _decodePageNames(String value) =>
    (jsonDecode(value) as List).cast<String>();

String _pageName(int index, String extension) =>
    '${index.toString().padLeft(5, '0')}$extension';

String _downloadId(String seriesId, String chapterId) =>
    _hash(jsonEncode([seriesId, chapterId]));

String _hash(String input) =>
    _hex(SHA256Digest().process(Uint8List.fromList(utf8.encode(input))));

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<(List<String>, String)> _stageImport(
  String source,
  String destination,
  List<String> Function(String source, String destination) stage,
) => Isolate.run(() async {
  final filenames = stage(source, destination);
  return (filenames, await _fingerprint(Directory(destination), filenames));
});

Future<String> _fingerprint(Directory folder, List<String> pages) async {
  final digest = SHA256Digest();
  for (final name in pages) {
    final file = File(p.join(folder.path, name));
    final length = ByteData(8)..setUint64(0, await file.length());
    digest.update(length.buffer.asUint8List(), 0, 8);
    await for (final chunk in file.openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }
  }
  final output = Uint8List(digest.digestSize);
  digest.doFinal(output, 0);
  return _hex(output);
}

bool _isHttpPage(Uri page) =>
    (page.scheme == 'https' || page.scheme == 'http') &&
    page.host.isNotEmpty &&
    page.userInfo.isEmpty;

void _validatePageList(List<Uri> pages) {
  if (pages.isEmpty ||
      pages.length > _maxPages ||
      pages.any((page) => !_isHttpPage(page))) {
    throw const FormatException('Invalid chapter page list.');
  }
}

void _validatePageHeaders(List<Uri> pages, List<Map<String, String>>? headers) {
  if (headers != null && headers.length != pages.length) {
    throw const FormatException('Invalid chapter page request headers.');
  }
}

void _checkCancellation(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) throw const LocalTransferCancelled();
}

Future<void> _prepareDownload(Directory staging, String fingerprint) async {
  final journal = File(p.join(staging.path, 'page-list'));
  if (await journal.exists() && await journal.readAsString() == fingerprint) {
    return;
  }
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  await journal.writeAsString(fingerprint, flush: true);
}

Future<List<String>> _transferPages(
  Directory directory,
  List<Uri> pages,
  http.Client client, {
  List<Map<String, String>>? pageHeaders,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final filenames = <String>[];
  var totalBytes = 0;
  for (final (index, url) in pages.indexed) {
    _checkCancellation(isCancelled);
    final name = _pageName(index, '.image');
    final page = File(p.join(directory.path, name));
    totalBytes += await page.exists()
        ? await page.length()
        : await _downloadPage(
            url,
            page,
            client,
            _maxChapterBytes - totalBytes,
            isCancelled,
            headers: pageHeaders?[index],
          );
    if (totalBytes > _maxChapterBytes) {
      throw const FormatException('Chapter is too large.');
    }
    filenames.add(name);
    onProgress?.call(index + 1, pages.length);
  }
  _checkCancellation(isCancelled);
  return filenames;
}

Future<int> _downloadPage(
  Uri url,
  File page,
  http.Client client,
  int remaining,
  bool Function()? isCancelled, {
  Map<String, String>? headers,
}) async {
  final limit = remaining < _maxPageBytes ? remaining : _maxPageBytes;
  final request = http.Request('GET', url)..followRedirects = false;
  if (headers != null) request.headers.addAll(headers);
  final response = await client.send(request).timeout(_transferTimeout);
  final mediaType = response.headers['content-type']
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  if (response.statusCode != 200 ||
      !_imageTypes.contains(mediaType) ||
      (response.contentLength ?? 0) > limit) {
    await response.stream.listen(null).cancel();
    throw http.ClientException(
      'Could not download image (HTTP ${response.statusCode}).',
      url,
    );
  }
  final part = File('${page.path}.part');
  final output = await part.open(mode: FileMode.write);
  var bytes = 0;
  try {
    try {
      await for (final chunk in response.stream.timeout(_transferTimeout)) {
        _checkCancellation(isCancelled);
        bytes += chunk.length;
        if (bytes > limit) {
          throw const FormatException('Page exceeds the size limit.');
        }
        await output.writeFrom(chunk);
      }
      if (bytes == 0 ||
          (response.contentLength != null && response.contentLength != bytes)) {
        throw http.ClientException('Incomplete image download.', url);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    await part.rename(page.path);
    return bytes;
  } finally {
    if (await part.exists()) await part.delete();
  }
}

bool _isImage(String path) =>
    _imageExtensions.contains(p.extension(path).toLowerCase()) &&
    !path.split('/').any((part) => part.startsWith('.') || part == '__MACOSX');

void _checkImport(int count, int bytes, int pageBytes) {
  if (count > _maxPages ||
      bytes > _maxChapterBytes ||
      pageBytes <= 0 ||
      pageBytes > _maxPageBytes) {
    throw const FormatException(
      'Chapter exceeds the limits for page count or file size.',
    );
  }
}

List<String> _extractArchive(String source, String destination) {
  if (File(source).lengthSync() > _maxChapterBytes) {
    throw const FormatException('Archive is too large.');
  }
  final input = InputFileStream(source);
  final directory = ZipDirectory();
  try {
    directory.read(input);
    if (directory.numberOfThisDisk != 0 ||
        directory.fileHeaders.length > _maxPages * 2) {
      throw const FormatException('Unsupported archive structure.');
    }
    final files = <({String name, ZipFileHeader header})>[];
    for (final entry in directory.fileHeaders) {
      final name = entry.filename.replaceAll('\\', '/');
      if (name.startsWith('/') ||
          name.split('/').contains('..') ||
          name.contains(':')) {
        throw const FormatException('Archive contains an invalid file path.');
      }
      final kind = (entry.externalFileAttributes >> 16) & 0xf000;
      if (kind == 0xa000) {
        throw const FormatException('Archive contains a symbolic link.');
      }
      if (name.endsWith('/') || !_isImage(name)) continue;
      if (entry.compressionMethod != 0 && entry.compressionMethod != 8 ||
          (entry.generalPurposeBitFlag & 1) != 0) {
        throw const FormatException(
          'Compressed or encrypted page is unsupported.',
        );
      }
      files.add((name: name, header: entry));
    }
    if (files.isEmpty) {
      throw const FormatException('No supported images were found.');
    }
    files.sort((a, b) => compareAsciiLowerCaseNatural(a.name, b.name));
    final names = <String>[];
    var total = 0;
    for (final (index, page) in files.indexed) {
      final size = page.header.uncompressedSize;
      total += size;
      _checkImport(files.length, total, size);
      final name = _pageName(index, p.extension(page.name).toLowerCase());
      final output = _ArchivePageOutput(p.join(destination, name), size);
      try {
        page.header.file!.decompress(output);
        if (output.length != size || output.checksum != page.header.crc32) {
          throw const FormatException('Archive image is damaged.');
        }
      } finally {
        output.closeSync();
      }
      names.add(name);
    }
    return names;
  } on ArchiveException catch (error) {
    throw FormatException('Invalid ZIP archive: $error');
  } finally {
    input.closeSync();
  }
}

List<String> _copyImageFolder(String source, String destination) {
  final files = <({String name, File file})>[];
  for (final entity in Directory(
    source,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source);
    if (!_isImage(relative)) continue;
    if (files.length >= _maxPages) {
      throw const FormatException('Too many images in this folder.');
    }
    files.add((name: relative, file: entity));
  }
  if (files.isEmpty) {
    throw const FormatException('No supported images were found.');
  }
  files.sort((a, b) => compareAsciiLowerCaseNatural(a.name, b.name));
  var total = 0;
  final names = <String>[];
  for (final (index, page) in files.indexed) {
    final size = page.file.lengthSync();
    total += size;
    _checkImport(files.length, total, size);
    final name = _pageName(index, p.extension(page.name).toLowerCase());
    page.file.copySync(p.join(destination, name));
    names.add(name);
  }
  return names;
}

class _ArchivePageOutput extends OutputFileStream {
  _ArchivePageOutput(String path, this._maxBytes)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int _maxBytes;
  int checksum = 0;

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (this.length + count > _maxBytes) {
      throw const FormatException('Archive page is larger than declared.');
    }
    checksum = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      checksum,
    );
    super.writeBytes(bytes, length: count);
  }
}
