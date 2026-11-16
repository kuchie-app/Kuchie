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

const _maxPages = 4000;
const _maxPageBytes = 64 * 1024 * 1024;
const _maxChapterBytes = 4 * 1024 * 1024 * 1024;
const _maxBackupBytes = 16 * 1024 * 1024;
const _transferTimeout = Duration(seconds: 30);
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
  }) : chapters = List.unmodifiable(chapters),
       categories = List.unmodifiable(categories);

  final String id;
  final String title;
  final List<LocalChapter> chapters;
  final List<String> categories;
  final bool inLibrary;
  final LocalSeriesSource? source;
}

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

/// A device-owned library with no dependency on a server or authenticated session.
class LocalCatalog {
  LocalCatalog(this._root);

  final Directory _root;
  final _metadata = _SerialOperations();
  final _transfers = <String, _SerialOperations>{};
  late final Future<_CatalogDatabase> _database = _open();
  Directory get _pages => Directory(p.join(_root.path, 'pages'));
  Directory get _imports => Directory(p.join(_root.path, 'imports'));
  Directory get _downloads => Directory(p.join(_root.path, 'downloads'));

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
    });
  });

  Future<List<LocalSeries>> _list(
    _CatalogDatabase db, {
    String? seriesId,
  }) async {
    final rows = await db
        .customSelect(
          '''
      SELECT s.id AS catalog_series_id, s.title AS series_title, s.in_library, s.source, c.*
      FROM series s LEFT JOIN chapters c ON c.series_id = s.id AND c.ready = 1
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
    await db.customStatement(
      'UPDATE chapters SET progress = ?, last_read_at = ? WHERE series_id = ? AND id = ?',
      [page, DateTime.now().millisecondsSinceEpoch, seriesId, chapterId],
    );
  });

  Future<void> setBookmark(
    String seriesId,
    String chapterId,
    bool bookmarked,
  ) => _metadata.run(() async {
    final db = await _database;
    await db.customStatement(
      'UPDATE chapters SET bookmarked = ? WHERE series_id = ? AND id = ? AND ready = 1',
      [bookmarked ? 1 : 0, seriesId, chapterId],
    );
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
    await db.customStatement(
      'INSERT OR IGNORE INTO categories (name) VALUES (?)',
      [_nonEmptyName(name, 'name')],
    );
  });

  Future<void> deleteCategory(String name) => _metadata.run(() async {
    final db = await _database;
    await db.customStatement('DELETE FROM categories WHERE name = ?', [
      name.trim(),
    ]);
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
      var restored = 0;
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
        for (final (seriesId, name) in backup.memberships) {
          for (final matched in matchedSeries[seriesId] ?? const <String>{}) {
            batch.customStatement(
              'INSERT OR IGNORE INTO series_categories (series_id, name) VALUES (?, ?)',
              [matched, name],
            );
          }
        }
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
  int get schemaVersion => 3;

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
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

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
