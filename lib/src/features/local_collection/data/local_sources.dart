import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pub_semver/pub_semver.dart';

import 'local_catalog.dart';
import 'local_mihon_runtime.dart';

part 'local_shinigami_source.dart';

class LocalSourceRepository {
  LocalSourceRepository._(
    this.url,
    this.name,
    List<LocalSourcePackage> packages, {
    this.hasNativeAdapters = false,
  }) : packages = List.unmodifiable(packages);

  final Uri url;
  final String name;
  final List<LocalSourcePackage> packages;
  final bool hasNativeAdapters;
}

class LocalSourcePackage {
  const LocalSourcePackage._({
    required this.id,
    required this.name,
    required this.version,
    required this.language,
    required this.url,
    required this.sha256,
    required this.repository,
    required this.catalogOrigin,
    this.icon,
    this.isNsfw = false,
    bool native = false,
    bool mihon = false,
  }) : _native = native,
       _mihon = mihon;

  final String id;
  final String name;
  final String version;
  final String language;
  final Uri url;
  final String? sha256;
  final Uri repository;
  final Uri catalogOrigin;
  final Uri? icon;
  final bool isNsfw;
  final bool _native;
  final bool _mihon;
}

class LocalExtension {
  const LocalExtension._(
    this._manifest,
    this.enabled,
    this.repository, {
    MihonRuntimeSource? runtimeSource,
  }) : _runtimeSource = runtimeSource;

  final _Manifest _manifest;
  final MihonRuntimeSource? _runtimeSource;
  final bool enabled;
  final Uri? repository;

  String get id => _runtimeSource == null
      ? _manifest.id
      : '${_manifest.id}:${_runtimeSource.id}';
  String get packageId => _manifest.id;
  String get packageName => _manifest.name;
  String get packageLanguage => _manifest.language;
  String get name => _runtimeSource?.name ?? _manifest.name;
  String get version => _manifest.version;
  String get language => _runtimeSource?.language ?? _manifest.language;
  Uri get catalogOrigin => Uri.parse(_manifest.catalog.origin);
  List<Uri> get mediaOrigins =>
      _manifest.mediaOrigins.map(Uri.parse).toList(growable: false);
  Uri? get icon => _manifest.nativeIcon;
  Uri? get homepage => _runtimeSource?.homepage ?? _manifest.nativeHomepage;
  bool get supportsLatest =>
      _runtimeSource?.supportsLatest ?? _manifest.isShinigami;
  bool get chaptersNewestFirst =>
      _manifest.isShinigami || _runtimeSource != null;
  bool get isNsfw => _manifest.isNsfw;
}

typedef LocalSourcePage = ({Uri url, Map<String, String> headers});

class LocalSourceManga {
  const LocalSourceManga._({
    required this.id,
    required this.title,
    required this.description,
    required this.cover,
    this.coverFallback,
    this.author = '',
    this.artist = '',
    this.status = 0,
    this.genres = const [],
    this.alternativeTitle = '',
    this.webUrl,
    required Uri feed,
    required String sourceId,
    required String sourceVersion,
    MihonRuntimeManga? runtimeManga,
  }) : _feed = feed,
       _sourceId = sourceId,
       _sourceVersion = sourceVersion,
       _runtimeManga = runtimeManga;

  final String id;
  final String title;
  final String description;
  final Uri? cover;
  final Uri? coverFallback;
  final String author;
  final String artist;
  final int status;
  final List<String> genres;
  final String alternativeTitle;
  final Uri? webUrl;
  final Uri _feed;
  final String _sourceId;
  final String _sourceVersion;
  final MihonRuntimeManga? _runtimeManga;
  Map<String, String> get coverHeaders =>
      _runtimeManga?.coverHeaders ?? const {};
}

class LocalSourceChapter {
  const LocalSourceChapter._({
    required this.id,
    required this.title,
    required Uri feed,
    required String sourceId,
    required String sourceVersion,
    this.runtimeLocator,
    this.uploadDate,
    this.number,
  }) : _feed = feed,
       _sourceId = sourceId,
       _sourceVersion = sourceVersion;

  final String id;
  final String title;
  final Uri _feed;
  final String _sourceId;
  final String _sourceVersion;
  final String? runtimeLocator;
  final DateTime? uploadDate;
  final double? number;
}

/// Keeps the device's enabled sources and explicit extension installations.
class LocalSources {
  LocalSources(
    Directory root, {
    http.Client? client,
    MihonRuntimeClient? runtime,
    bool allowInsecureLoopback = false,
  }) : _directory = Directory('${root.path}/sources'),
       _client = client ?? http.Client(),
       _runtime = runtime ?? MihonRuntimeClient(),
       _ownsRuntime = runtime == null,
       _ownsClient = client == null,
       _allowInsecureLoopback = allowInsecureLoopback;

  static const _networkTimeout = Duration(seconds: 20);
  static const _maxManifestBytes = 128 * 1024;
  static const _maxFeedBytes = 2 * 1024 * 1024;
  static const _maxKeiyoushiBytes = 4 * 1024 * 1024;
  static const _maxApkBytes = 16 * 1024 * 1024;
  static const _maxStateBytes = 12 * 1024 * 1024;
  static const _maxRepositories = 32;
  static const _maxPackages = 1000;
  static const _maxInstalled = 128;
  static const _maxCacheEntries = 24;
  static final _digestPattern = RegExp(r'^[a-f0-9]{64}$');
  static final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
  static final _mihonId = RegExp(r'^-?[0-9]{1,20}$');

  final Directory _directory;
  final http.Client _client;
  final MihonRuntimeClient _runtime;
  final bool _ownsRuntime;
  final bool _ownsClient;
  final bool _allowInsecureLoopback;
  Future<void> _writes = Future.value();
  Future<void>? _legacyUpgrade;
  ({String file, Uint8List bytes})? _cachedApk;
  File get _state => File('${_directory.path}/sources.json');

  void close() {
    if (_ownsClient) _client.close();
    if (_ownsRuntime) _runtime.close();
  }

  Future<List<LocalSourceRepository>> repositories() async {
    var state = await _readState();
    final keiyoushi = state.repositories[_keiyoushiIndex.toString()];
    if (keiyoushi is Map && keiyoushi['format'] == 'kuchie.keiyoushi.v1') {
      await (_legacyUpgrade ??= _upgradeKeiyoushi());
      state = await _readState();
    }
    return [
      for (final entry in state.repositories.entries)
        _parseRepository(Uri.parse(entry.key), _object(entry.value)),
    ];
  }

  Future<void> _upgradeKeiyoushi() async {
    try {
      await refreshRepository(_keiyoushiIndex);
    } on Exception {
      // Keep the installed Shinigami adapter available while offline.
    } on StateError {
      // The repository can be removed while the index is downloading.
    }
  }

  Future<List<LocalExtension>> extensions() async {
    final state = await _readState();
    return state.extensions.values.map(_parseInstalled).toList(growable: false);
  }

  Future<List<LocalExtension>> sources() async {
    final installed = await extensions();
    return [
      for (final extension in installed)
        if (extension._manifest.runtimeSources.isEmpty)
          extension
        else
          for (final runtimeSource in extension._manifest.runtimeSources)
            LocalExtension._(
              extension._manifest,
              extension.enabled,
              extension.repository,
              runtimeSource: runtimeSource,
            ),
    ];
  }

  Future<LocalSourceRepository> addRepository(Uri index) =>
      _storeRepository(index);

  Future<LocalSourceRepository> refreshRepository(Uri index) =>
      _storeRepository(index, refresh: true);

  Future<LocalSourceRepository> _storeRepository(
    Uri index, {
    bool refresh = false,
  }) async {
    final url = _repositoryUrl(index);
    final key = url.toString();
    final isKeiyoushi = url == _keiyoushiIndex;
    final bytes = await _download(
      url,
      isKeiyoushi ? _maxKeiyoushiBytes : _maxFeedBytes,
    );
    final indexData = isKeiyoushi
        ? await _decodeKeiyoushiIndex(bytes)
        : _decode(bytes);
    final repository = _parseRepository(url, indexData);
    return _change((state) {
      final existing = state.repositories.containsKey(key);
      if (refresh && !existing) throw StateError('Repository is not saved.');
      if (!existing && state.repositories.length >= _maxRepositories) {
        throw StateError('This device has too many local repositories.');
      }
      state.repositories[key] = _repositoryJson(repository);
      return repository;
    });
  }

  Future<void> removeRepository(Uri index) => _change<void>((state) {
    state.repositories.remove(_repositoryUrl(index).toString());
  });

  Future<LocalExtension> install(LocalSourcePackage package) async {
    _requirePackage(await _readState(), package);
    if (package._native) {
      return _installManifest(
        _ShinigamiSource.manifest(package.version, icon: package.icon),
        package: package,
      );
    }
    if (package._mihon) return _installMihon(package);
    final bytes = await _download(package.url, _maxManifestBytes);
    if (_sha256(bytes) != package.sha256) {
      throw const FormatException('Extension package checksum does not match.');
    }
    final manifest = _parseManifest(_decode(bytes), base: package.url);
    if (manifest.id != package.id ||
        manifest.version != package.version ||
        manifest.name != package.name ||
        manifest.language != package.language ||
        manifest.catalog.origin != package.catalogOrigin.toString()) {
      throw const FormatException(
        'Extension package does not match the repository.',
      );
    }
    return _installManifest(manifest, package: package);
  }

  Future<LocalExtension> _installMihon(LocalSourcePackage package) async {
    final apk = await _download(
      package.url,
      _maxApkBytes,
      accept: 'application/vnd.android.package-archive',
      allowApkRedirects: true,
    );
    final sources = await _runtime.inspect(apk, packageName: package.id);
    if (sources.isEmpty || sources.length > 256) {
      throw const FormatException('The extension has no manga sources.');
    }
    final ids = <String>{};
    if (sources.any(
      (source) => !_mihonId.hasMatch(source.id) || !ids.add(source.id),
    )) {
      throw const FormatException('Invalid manga source identifiers.');
    }
    final fingerprint = _sha256(apk);
    final manifest = _Manifest(
      id: package.id,
      name: package.name,
      version: package.version,
      language: package.language,
      catalog: _keiyoushiIndex,
      mediaOrigins: const {},
      nativeIcon: package.icon,
      isNsfw: package.isNsfw,
      apkFingerprint: fingerprint,
      runtimeSources: sources,
    );
    try {
      return await _installManifest(manifest, package: package, apk: apk);
    } finally {
      await _pruneApks(package.id);
    }
  }

  Directory _apkDirectory(String id) =>
      Directory('${_directory.path}/mihon/$id');

  File _apkFile(String id, String digest) =>
      File('${_apkDirectory(id).path}/$digest.apk');

  Future<void> _pruneApks(String id) => _serial(() async {
    final directory = _apkDirectory(id);
    final path = (await _readState()).extensions[id];
    final keep = path == null
        ? null
        : _parseInstalled(path)._manifest.apkFingerprint;
    try {
      if (!await directory.exists()) return;
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File &&
            (keep == null || entry.path != _apkFile(id, keep).path)) {
          if (_cachedApk?.file == entry.path) _cachedApk = null;
          await entry.delete();
        }
      }
    } on FileSystemException {
      // The next update or uninstall can remove an unused package.
    }
  });

  Future<Uint8List> _installedApk(LocalExtension extension) async {
    final file = _apkFile(
      extension.packageId,
      extension._manifest.apkFingerprint!,
    );
    final cached = _cachedApk;
    if (cached?.file == file.path) return cached!.bytes;
    if (!await file.exists() || await file.length() > _maxApkBytes) {
      throw StateError('The extension APK is missing. Install it again.');
    }
    final bytes = await file.readAsBytes();
    if (_sha256(bytes) != extension._manifest.apkFingerprint) {
      throw const FormatException('The installed APK is damaged.');
    }
    _cachedApk = (file: file.path, bytes: bytes);
    return bytes;
  }

  Future<LocalExtension> importFile(File file) async {
    if (!_isPackagePath(file.path)) {
      throw const FormatException(
        'Choose a .kuchie-source or .json extension package.',
      );
    }
    if (await file.length() > _maxManifestBytes) {
      throw const FormatException('Extension package is too large.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > _maxManifestBytes) {
        throw const FormatException('Extension package is too large.');
      }
      bytes.add(chunk);
    }
    return _installManifest(_parseManifest(_decode(bytes.takeBytes())));
  }

  Future<LocalExtension> _installManifest(
    _Manifest manifest, {
    LocalSourcePackage? package,
    Uint8List? apk,
  }) => _change((state) async {
    if (package != null) _requirePackage(state, package);
    final old = state.extensions[manifest.id];
    final previous = old == null ? null : _parseInstalled(old);
    final repository = package?.repository;
    if (previous != null &&
        (previous.repository != repository ||
            previous._manifest.catalog.origin != manifest.catalog.origin)) {
      throw StateError('This ID is already installed from a different source.');
    }
    if (previous != null) {
      final comparison = Version.parse(
        manifest.version,
      ).compareTo(Version.parse(previous.version));
      if (comparison < 0) {
        throw StateError('A newer version is already installed.');
      }
      if (comparison == 0) {
        if (apk != null &&
            manifest.apkFingerprint == previous._manifest.apkFingerprint) {
          await _writeApk(manifest, apk);
          return previous;
        }
        final sameManifest =
            jsonEncode(manifest.toJson()) ==
            jsonEncode(previous._manifest.toJson());
        if (!sameManifest) {
          throw StateError('A changed extension must use a newer version.');
        }
        return previous;
      }
    } else if (state.extensions.length >= _maxInstalled) {
      throw StateError('This device has too many installed extensions.');
    }
    if (apk != null) await _writeApk(manifest, apk);
    final installed = LocalExtension._(
      manifest,
      previous?.enabled ?? true,
      repository,
      runtimeSource: manifest.runtimeSources.firstOrNull,
    );
    state.extensions[manifest.id] = _extensionJson(installed);
    return installed;
  });

  Future<void> _writeApk(_Manifest manifest, Uint8List bytes) async {
    final file = _apkFile(manifest.id, manifest.apkFingerprint!);
    await file.parent.create(recursive: true);
    await _atomicWrite(file, bytes);
    _cachedApk = (file: file.path, bytes: bytes);
  }

  String _packageId(String id) => id.split(':').first;

  Future<void> setEnabled(String id, bool enabled) => _change<void>((state) {
    final key = _packageId(id);
    final raw = state.extensions[key];
    if (raw == null) throw StateError('Extension is not installed.');
    final current = _parseInstalled(raw);
    state.extensions[key] = _extensionJson(
      LocalExtension._(current._manifest, enabled, current.repository),
    );
  });

  Future<void> uninstall(String id) async {
    final key = _packageId(id);
    if (!_idPattern.hasMatch(key)) throw ArgumentError.value(id);
    await _change<void>((state) => state.extensions.remove(key));
    await _pruneApks(key);
  }

  Future<List<LocalSourceManga>> browse(
    String id, {
    String query = '',
    bool latest = false,
  }) async => (await browsePage(id, query: query, latest: latest)).items;

  Future<({List<LocalSourceManga> items, bool hasMore})> browsePage(
    String id, {
    String query = '',
    bool latest = false,
    int page = 1,
    void Function(bool fromCache)? onFreshness,
  }) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    final source = await _enabled(id);
    final manifest = source._manifest;
    if (source._runtimeSource case final runtimeSource?) {
      final pageResult = await _runtime.browse(
        await _installedApk(source),
        runtimeSource,
        query: query.trim(),
        latest: latest,
        page: page,
      );
      final ids = <String>{};
      final items = <LocalSourceManga>[];
      for (final manga in pageResult.items) {
        final mangaId = _mihonLocatorId(manga.stableLocator);
        if (!ids.add(mangaId)) continue;
        items.add(
          LocalSourceManga._(
            id: mangaId,
            title: manga.title,
            description: manga.description,
            cover: manga.cover,
            author: manga.author,
            artist: manga.artist,
            status: manga.status,
            genres: manga.genres,
            feed: manifest.catalog,
            sourceId: source.id,
            sourceVersion: source.version,
            runtimeManga: manga,
          ),
        );
      }
      onFreshness?.call(false);
      return (items: items, hasMore: pageResult.hasMore);
    }
    if (manifest.isShinigami) {
      final url = _ShinigamiSource.browseUrl(query.trim(), latest, page);
      return _feed(
        source,
        url,
        (data) => _ShinigamiSource.browse(source, data),
        onFreshness: onFreshness,
      );
    }
    if (page != 1) return (items: <LocalSourceManga>[], hasMore: false);
    final feed = manifest.catalog;
    final keyword = query.trim().toLowerCase();
    final items = await _feed(
      source,
      feed,
      (data) => _catalog(source, data, keyword),
      onFreshness: onFreshness,
    );
    return (items: items, hasMore: false);
  }

  List<LocalSourceManga> _catalog(
    LocalExtension source,
    Map<String, Object?> data,
    String keyword,
  ) {
    final manifest = source._manifest;
    final feed = manifest.catalog;
    final mangas = <LocalSourceManga>[];
    final ids = <String>{};
    for (final value in _list(data, 'manga', 5000)) {
      final entry = _object(value);
      final itemId = _id(entry, 'id');
      if (!ids.add(itemId)) throw const FormatException('Duplicate manga ID.');
      final title = _string(entry, 'title', max: 384);
      final description = entry['description'] == null
          ? ''
          : _string(entry, 'description', max: 12000, allowEmpty: true);
      final chapterFeed = _sourceLink(
        manifest,
        feed,
        _string(entry, 'chapters'),
      );
      final cover = entry['cover'] == null
          ? null
          : _sourceLink(manifest, feed, _string(entry, 'cover'), media: true);
      if (keyword.isEmpty || title.toLowerCase().contains(keyword)) {
        mangas.add(
          LocalSourceManga._(
            id: itemId,
            title: title,
            description: description,
            cover: cover,
            feed: chapterFeed,
            sourceId: source.id,
            sourceVersion: source.version,
          ),
        );
      }
    }
    return mangas;
  }

  LocalSeriesSource seriesReference(
    LocalSourceManga manga, {
    String? sourceName,
  }) => LocalSeriesSource(
    sourceId: manga._sourceId,
    mangaId: manga.id,
    locator: manga._runtimeManga?.locator ?? manga._feed.toString(),
    cover: manga.cover?.scheme == 'https' ? manga.cover : null,
    genres: manga.genres,
    sourceName: sourceName,
  );

  Future<({LocalExtension extension, LocalSourceManga manga})> resolveSeries(
    LocalSeriesSource reference,
    String title,
  ) async {
    final source = await _enabled(reference.sourceId);
    return restoreSeries(source, reference, title);
  }

  ({LocalExtension extension, LocalSourceManga manga}) restoreSeries(
    LocalExtension source,
    LocalSeriesSource reference,
    String title,
  ) {
    if (source.id != reference.sourceId || !source.enabled) {
      throw StateError('The source is unavailable.');
    }
    final runtime = source._runtimeSource != null;
    final runtimeManga = runtime
        ? MihonRuntimeManga(
            locator: reference.locator,
            title: title,
            cover: reference.cover,
          )
        : null;
    if (runtimeManga != null &&
        _mihonLocatorId(runtimeManga.stableLocator) != reference.mangaId) {
      throw const FormatException(
        'The saved manga locator does not match its source.',
      );
    }
    final feed = switch ((runtime, source._manifest.isShinigami)) {
      (true, _) => source._manifest.catalog,
      (_, true) => _shinigamiChapterFeed(reference.mangaId),
      _ => _sourceLink(
        source._manifest,
        source._manifest.catalog,
        reference.locator,
      ),
    };
    return (
      extension: source,
      manga: LocalSourceManga._(
        id: reference.mangaId,
        title: title,
        description: '',
        cover: reference.cover,
        genres: reference.genres,
        feed: feed,
        sourceId: source.id,
        sourceVersion: source.version,
        runtimeManga: runtimeManga,
      ),
    );
  }

  LocalSeriesSource? legacySeriesReference(String sourceId, String mangaId) {
    if (sourceId != _ShinigamiSource.id || !_idPattern.hasMatch(mangaId)) {
      return null;
    }
    return LocalSeriesSource(
      sourceId: sourceId,
      mangaId: mangaId,
      locator: _shinigamiChapterFeed(mangaId).toString(),
    );
  }

  Uri _shinigamiChapterFeed(String mangaId) {
    if (!_idPattern.hasMatch(mangaId)) {
      throw const FormatException('Invalid Shinigami manga ID.');
    }
    return Uri.https(_ShinigamiSource._apiHost, '/v1/chapter/$mangaId/list', {
      'page_size': '3000',
    });
  }

  Future<LocalSourceManga> mangaDetails(
    String id,
    LocalSourceManga manga,
  ) async {
    final original = manga._runtimeManga;
    final source = await _enabled(id);
    _checkSelection(source, manga._sourceId, manga._sourceVersion);
    if (source._manifest.isShinigami) {
      return _feed(
        source,
        _ShinigamiSource.detailsUrl(manga.id),
        (data) => _ShinigamiSource.details(source, manga, data),
      );
    }
    if (original == null) return manga;
    final details = await _runtime.details(
      await _installedApk(source),
      source._runtimeSource!,
      original,
    );
    final result = MihonRuntimeManga(
      locator: original.locator,
      title: details.title,
      description: details.description.isEmpty
          ? original.description
          : details.description,
      cover: details.cover ?? original.cover,
      coverHeaders: details.cover == null
          ? original.coverHeaders
          : details.coverHeaders,
      author: details.author.isEmpty ? original.author : details.author,
      artist: details.artist.isEmpty ? original.artist : details.artist,
      status: details.status == 0 ? original.status : details.status,
      genres: details.genres.isEmpty ? original.genres : details.genres,
    );
    return LocalSourceManga._(
      id: manga.id,
      title: result.title,
      description: result.description,
      cover: result.cover,
      author: result.author,
      artist: result.artist,
      status: result.status,
      genres: result.genres,
      feed: manga._feed,
      sourceId: manga._sourceId,
      sourceVersion: manga._sourceVersion,
      runtimeManga: result,
    );
  }

  Future<List<LocalSourceChapter>> chapters(
    String id,
    LocalSourceManga manga,
  ) async {
    final source = await _enabled(id);
    _checkSelection(source, manga._sourceId, manga._sourceVersion);
    if (source._runtimeSource case final runtimeSource?) {
      final runtimeManga = manga._runtimeManga!;
      final chapters = await _runtime.chapters(
        await _installedApk(source),
        runtimeSource,
        runtimeManga,
      );
      final ids = <String>{};
      final items = <LocalSourceChapter>[];
      for (final chapter in chapters) {
        final chapterId = _mihonLocatorId(chapter.stableLocator);
        if (!ids.add(chapterId)) continue;
        items.add(
          LocalSourceChapter._(
            id: chapterId,
            title: chapter.title,
            feed: source._manifest.catalog,
            sourceId: source.id,
            sourceVersion: source.version,
            runtimeLocator: chapter.locator,
            uploadDate: chapter.uploadDate,
            number: chapter.number,
          ),
        );
      }
      return items;
    }
    if (source._manifest.isShinigami) {
      return _feed(
        source,
        manga._feed,
        (data) => _ShinigamiSource.chapters(source, data),
      );
    }
    return _feed(source, manga._feed, (data) {
      final seen = <String>{};
      return [
        for (final value in _list(data, 'chapters', 5000))
          _chapter(source, manga._feed, _object(value), seen),
      ];
    });
  }

  LocalSourceChapter _chapter(
    LocalExtension source,
    Uri feed,
    Map<String, Object?> data,
    Set<String> seen,
  ) {
    final id = _id(data, 'id');
    if (!seen.add(id)) throw const FormatException('Duplicate chapter ID.');
    return LocalSourceChapter._(
      id: id,
      title: _string(data, 'title', max: 384),
      feed: _sourceLink(source._manifest, feed, _string(data, 'pages')),
      sourceId: source.id,
      sourceVersion: source.version,
    );
  }

  Future<List<Uri>> pages(String id, LocalSourceChapter chapter) async => [
    for (final page in await chapterPages(id, chapter)) page.url,
  ];

  Future<List<LocalSourcePage>> chapterPages(
    String id,
    LocalSourceChapter chapter,
  ) async {
    final source = await _enabled(id);
    _checkSelection(source, chapter._sourceId, chapter._sourceVersion);
    if (chapter.runtimeLocator case final locator?) {
      return _runtimeChapterPages(source, locator);
    }
    return [
      for (final url in await _feedChapterPages(source, chapter))
        (url: url, headers: const <String, String>{}),
    ];
  }

  Future<List<LocalSourcePage>> refreshChapterPages(
    String sourceId,
    String chapterLocator,
  ) async => _runtimeChapterPages(await _enabled(sourceId), chapterLocator);

  Future<List<LocalSourcePage>> _runtimeChapterPages(
    LocalExtension source,
    String locator,
  ) async {
    final runtimeSource = source._runtimeSource;
    if (runtimeSource == null || locator.isEmpty || locator.length > 32768) {
      throw const FormatException('Invalid chapter locator.');
    }
    final pages = await _runtime.pages(
      await _installedApk(source),
      runtimeSource,
      MihonRuntimeChapter(locator: locator, title: ''),
    );
    if (pages.isEmpty || pages.length > 4000) {
      throw const FormatException('The extension returned no valid pages.');
    }
    return [
      for (final page in pages)
        (
          url: page.url,
          headers: Map<String, String>.unmodifiable(page.headers),
        ),
    ];
  }

  Future<List<Uri>> _feedChapterPages(
    LocalExtension source,
    LocalSourceChapter chapter,
  ) async {
    if (source._manifest.isShinigami) {
      return _feed(
        source,
        chapter._feed,
        (data) => _ShinigamiSource.pages(
          data,
          (path) =>
              _sourceLink(source._manifest, chapter._feed, path, media: true),
        ),
      );
    }
    final data = _decode(await _download(chapter._feed, _maxFeedBytes));
    final pages = _list(data, 'pages', 1000);
    if (pages.isEmpty) throw const FormatException('The chapter has no pages.');
    return [
      for (final entry in pages)
        if (entry case final String link)
          _sourceLink(source._manifest, chapter._feed, link, media: true)
        else
          throw const FormatException('Invalid chapter page URL.'),
    ];
  }

  static void _checkSelection(
    LocalExtension source,
    String id,
    String version,
  ) {
    if (source.id != id || source.version != version) {
      throw StateError(
        'The source changed. Open the manga from its catalog again.',
      );
    }
  }

  Future<LocalExtension> _enabled(String id) async {
    final raw = (await _readState()).extensions[_packageId(id)];
    if (raw != null) {
      final extension = _parseInstalled(raw);
      if (extension.enabled) {
        if (id == extension.id || id == extension.packageId) return extension;
        final source = extension._manifest.runtimeSources
            .where((source) => id == '${extension.packageId}:${source.id}')
            .firstOrNull;
        if (source != null) {
          return LocalExtension._(
            extension._manifest,
            true,
            extension.repository,
            runtimeSource: source,
          );
        }
      }
    }
    throw StateError('Extension is missing or disabled.');
  }

  void _requirePackage(_SourceState state, LocalSourcePackage requested) {
    final index = state.repositories[requested.repository.toString()];
    if (index == null) {
      throw StateError('The extension repository was removed.');
    }
    final repo = _parseRepository(requested.repository, _object(index));
    final matches = repo.packages.any(
      (package) =>
          package.id == requested.id &&
          package.version == requested.version &&
          package.url == requested.url &&
          package.sha256 == requested.sha256 &&
          package.catalogOrigin == requested.catalogOrigin &&
          package._native == requested._native &&
          package._mihon == requested._mihon &&
          package.icon == requested.icon &&
          package.isNsfw == requested.isNsfw,
    );
    if (!matches) throw StateError('Refresh the extension list and try again.');
  }

  LocalSourceRepository _parseRepository(Uri url, Map<String, Object?> data) {
    if (url == _keiyoushiIndex && data['format'] == 'kuchie.keiyoushi.v2') {
      return LocalSourceRepository._(url, 'Keiyoushi', [
        for (final entry in _list(data, 'extensions', 10000))
          _parseKeiyoushiPackage(url, _object(entry)),
      ], hasNativeAdapters: true);
    }
    if (url == _keiyoushiIndex && data['format'] == 'kuchie.keiyoushi.v1') {
      final entry = data['shinigami'];
      return LocalSourceRepository._(url, 'Keiyoushi', [
        if (entry != null)
          LocalSourcePackage._(
            id: _ShinigamiSource.id,
            name: 'Shinigami',
            version: _version(_object(entry)),
            language: 'id',
            url: url,
            sha256: null,
            repository: url,
            catalogOrigin: _ShinigamiSource.origin,
            icon: _ShinigamiSource.icon,
            native: true,
          ),
      ], hasNativeAdapters: true);
    }
    if (data['format'] != 'kuchie.repository.v1') {
      throw const FormatException(
        'Use a Kuchie repository or the official Keiyoushi store URL.',
      );
    }
    final packages = <LocalSourcePackage>[];
    final seen = <String>{};
    for (final value in _list(data, 'extensions', _maxPackages)) {
      final details = _object(value);
      final id = _id(details, 'id');
      if (!seen.add(id)) throw const FormatException('Duplicate extension ID.');
      final packageUrl = _url(_string(details, 'url'), base: url);
      if (packageUrl.origin != url.origin || !_isPackagePath(packageUrl.path)) {
        throw const FormatException(
          'Use a v1 extension package on the repository origin.',
        );
      }
      final digest = _string(details, 'sha256');
      if (!_digestPattern.hasMatch(digest)) {
        throw const FormatException(
          'A package is missing its SHA-256 checksum.',
        );
      }
      packages.add(
        LocalSourcePackage._(
          id: id,
          name: _string(details, 'name', max: 160),
          version: _version(details),
          language: _string(details, 'language', max: 32),
          url: packageUrl,
          sha256: digest,
          repository: url,
          catalogOrigin: details['catalogOrigin'] == null
              ? Uri.parse(url.origin)
              : _parseOrigin(_string(details, 'catalogOrigin')),
        ),
      );
    }
    return LocalSourceRepository._(
      url,
      _string(data, 'name', max: 160),
      packages,
    );
  }

  LocalSourcePackage _parseKeiyoushiPackage(
    Uri index,
    Map<String, Object?> data,
  ) {
    final id = _id(data, 'id');
    final rawApk = data['apk'];
    final builtIn = rawApk == null && id == _ShinigamiSource.id;
    final uri = rawApk is String ? _keiyoushiApkUri(rawApk) : null;
    if (!builtIn && (uri == null || !_keiyoushiPackagePattern.hasMatch(id))) {
      throw const FormatException('Invalid Keiyoushi package.');
    }
    final rawIcon = data['icon'];
    return LocalSourcePackage._(
      id: id,
      name: _string(data, 'name', max: 160),
      version: _version(data),
      language: _string(data, 'language', max: 32),
      url: uri ?? index,
      sha256: null,
      repository: index,
      catalogOrigin: builtIn
          ? _ShinigamiSource.origin
          : Uri.parse(index.origin),
      icon: rawIcon is String
          ? _keiyoushiIconUri(rawIcon)
          : builtIn
          ? _ShinigamiSource.icon
          : null,
      native: builtIn,
      mihon: !builtIn,
      isNsfw: data['nsfw'] == true,
    );
  }

  _Manifest _parseManifest(Map<String, Object?> data, {Uri? base}) {
    if (data['format'] != 'kuchie.extension.v1') {
      throw const FormatException(
        'This file is not a Kuchie v1 extension. APK and JAR are unsupported.',
      );
    }
    final catalog = _url(_string(data, 'catalog'), base: base);
    final media = <String>{};
    if (data['mediaOrigins'] != null) {
      for (final entry in _list(data, 'mediaOrigins', 8)) {
        if (entry is! String) {
          throw const FormatException('Invalid media origin.');
        }
        media.add(_parseOrigin(entry).toString());
      }
    }
    return _Manifest(
      id: _id(data, 'id'),
      name: _string(data, 'name', max: 160),
      version: _version(data),
      language: _string(data, 'language', max: 32),
      catalog: catalog,
      mediaOrigins: media,
    );
  }

  LocalExtension _parseInstalled(Object? raw) {
    final data = _object(raw);
    final repository = data['repository'] == null
        ? null
        : _url(_string(data, 'repository'));
    final manifest = _object(data['manifest']);
    final _Manifest parsed;
    if (repository == _keiyoushiIndex) {
      parsed = switch (manifest['format']) {
        'kuchie.native-shinigami.v1' => _ShinigamiSource.manifest(
          _version(manifest),
          icon: _ShinigamiSource.icon,
        ),
        'kuchie.mihon.v1' => _parseRuntimeManifest(manifest),
        _ => _parseManifest(manifest),
      };
    } else {
      parsed = _parseManifest(manifest);
    }
    return LocalExtension._(
      parsed,
      data['enabled'] == true,
      repository,
      runtimeSource: parsed.runtimeSources.firstOrNull,
    );
  }

  _Manifest _parseRuntimeManifest(Map<String, Object?> manifest) {
    final id = _id(manifest, 'id');
    final fingerprint = _string(manifest, 'apkFingerprint', max: 64);
    if (!_keiyoushiPackagePattern.hasMatch(id) ||
        !_digestPattern.hasMatch(fingerprint)) {
      throw const FormatException('Invalid installed extension APK.');
    }
    final sources = [
      for (final entry in _list(manifest, 'runtimeSources', 256))
        _parseRuntimeSource(_object(entry)),
    ];
    if (sources.isEmpty) {
      throw const FormatException('The extension has no manga sources.');
    }
    final rawIcon = manifest['icon'];
    return _Manifest(
      id: id,
      name: _string(manifest, 'name', max: 160),
      version: _version(manifest),
      language: _string(manifest, 'language', max: 32),
      catalog: _keiyoushiIndex,
      mediaOrigins: const {},
      nativeIcon: rawIcon is String ? _keiyoushiIconUri(rawIcon) : null,
      isNsfw: manifest['nsfw'] == true,
      apkFingerprint: fingerprint,
      runtimeSources: sources,
    );
  }

  MihonRuntimeSource _parseRuntimeSource(Map<String, Object?> data) {
    final id = _string(data, 'id', max: 20);
    if (!_mihonId.hasMatch(id)) {
      throw const FormatException('Invalid manga source identifier.');
    }
    final homepage = data['homepage'];
    return MihonRuntimeSource(
      id: id,
      name: _string(data, 'name', max: 160),
      language: _string(data, 'language', max: 32),
      homepage: homepage is String ? _secureArtifactUri(homepage) : null,
      supportsLatest: data['supportsLatest'] != false,
    );
  }

  Uri _sourceLink(
    _Manifest source,
    Uri base,
    String path, {
    bool media = false,
  }) {
    final target = _url(path, base: base);
    if (target.origin != source.catalog.origin &&
        !(media && source.mediaOrigins.contains(target.origin))) {
      throw const FormatException(
        'Source URL is outside the extension’s allowed origins.',
      );
    }
    return target;
  }

  Uri _url(String input, {Uri? base}) {
    if (input.length > 2048 ||
        input.contains(RegExp(r'[\u0000-\u0020\u007f\\]'))) {
      throw const FormatException('Invalid extension URL.');
    }
    final parsed = Uri.tryParse(input);
    if (parsed == null) throw const FormatException('Invalid extension URL.');
    final url = base?.resolveUri(parsed) ?? parsed;
    final loopback = const {'127.0.0.1', 'localhost', '::1'}.contains(url.host);
    if (!(url.scheme == 'https' ||
            (_allowInsecureLoopback && loopback && url.scheme == 'http')) ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const FormatException(
        'Use an HTTPS URL without credentials or fragments.',
      );
    }
    return url;
  }

  Uri _repositoryUrl(Uri index) {
    if ((index.scheme == 'mihon' && index.host == 'extension-store') ||
        (index.scheme == 'tachiyomi' && index.host == 'add-repo')) {
      final candidate = Uri.tryParse(index.queryParameters['url'] ?? '');
      if (candidate != null && _isKeiyoushiUrl(candidate)) {
        return _keiyoushiIndex;
      }
    }
    final url = _url(index.toString());
    return _isKeiyoushiUrl(url) ? _keiyoushiIndex : url;
  }

  Uri _parseOrigin(String input) {
    final url = _url(input);
    if ((url.path.isNotEmpty && url.path != '/') || url.hasQuery) {
      throw const FormatException(
        'Extension origins must not include a path or query.',
      );
    }
    return Uri.parse(url.origin);
  }

  Future<Uint8List> _download(
    Uri url,
    int maxBytes, {
    String accept = 'application/json',
    bool allowApkRedirects = false,
  }) async {
    final abort = Completer<void>();
    final elapsed = Stopwatch()..start();
    try {
      var current = url;
      http.StreamedResponse response;
      for (var redirects = 0; ; redirects++) {
        final request =
            http.AbortableRequest('GET', current, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers['Accept'] = accept;
        response = await _client.send(request).timeout(_networkTimeout);
        if (!allowApkRedirects ||
            !const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          break;
        }
        final location = response.headers['location'];
        final next = location == null ? null : current.resolve(location);
        if (redirects >= 3 ||
            elapsed.elapsed > _networkTimeout ||
            next == null ||
            !_isGitHubReleaseAsset(next)) {
          throw const FormatException('Untrusted extension download redirect.');
        }
        // Release redirects have no installer payload. Cancel their stream.
        await response.stream.listen(null).cancel();
        current = next;
      }
      final announced = response.contentLength;
      if (response.statusCode != HttpStatus.ok) {
        throw _SourceHttpException(response.statusCode, url);
      }
      if (announced != null && announced > maxBytes) {
        throw const FormatException('The extension response is too large.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_networkTimeout)) {
        if (elapsed.elapsed > _networkTimeout) {
          throw TimeoutException('Source request timed out.');
        }
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('The extension response is too large.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      abort.complete();
    }
  }

  bool _isGitHubReleaseAsset(Uri url) =>
      url.scheme == 'https' &&
      !url.hasPort &&
      url.userInfo.isEmpty &&
      !url.hasFragment &&
      const {
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
      }.contains(url.host);

  Future<T> _feed<T>(
    LocalExtension source,
    Uri url,
    T Function(Map<String, Object?>) parse, {
    void Function(bool fromCache)? onFreshness,
  }) async {
    final cache = _cacheFile(source, url);
    Future<T> readCache() async {
      final data = parse(await _cached(cache));
      onFreshness?.call(true);
      return data;
    }

    final Uint8List bytes;
    try {
      bytes = await _download(url, _maxFeedBytes);
    } on SocketException {
      return readCache();
    } on http.ClientException {
      return readCache();
    } on TimeoutException {
      return readCache();
    } on _SourceHttpException catch (error) {
      if (!source._manifest.isShinigami ||
          !error.canUseCachedResponse ||
          !await cache.exists()) {
        rethrow;
      }
      return readCache();
    }
    final data = parse(_decode(bytes));
    try {
      await _writeCache(cache, bytes);
    } on FileSystemException {
      // Cache is opportunistic. A failed disk write must not hide online content.
    }
    onFreshness?.call(false);
    return data;
  }

  Future<Map<String, Object?>> _cached(File file) async {
    if (await file.exists() && await file.length() <= _maxFeedBytes) {
      return _decode(await file.readAsBytes());
    }
    throw const SocketException(
      'No connection and this source has no saved catalog.',
    );
  }

  File _cacheFile(LocalExtension source, Uri url) {
    final key = _sha256(
      Uint8List.fromList(utf8.encode('${source.id}\n${source.version}\n$url')),
    );
    return File('${_directory.path}/cache/${source.id}-$key.json');
  }

  Future<void> _writeCache(File file, Uint8List bytes) => _serial(() async {
    await file.parent.create(recursive: true);
    await _atomicWrite(file, bytes);
    final entries = await file.parent
        .list(followLinks: false)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    if (entries.length <= _maxCacheEntries) return;
    final modified = await Future.wait([
      for (final entry in entries) entry.lastModified(),
    ]);
    final byAge = List.generate(entries.length, (i) => i)
      ..sort((left, right) => modified[left].compareTo(modified[right]));
    for (final index in byAge.take(entries.length - _maxCacheEntries)) {
      await entries[index].delete();
    }
  });

  Future<_SourceState> _readState() async {
    final file = _state;
    if (!await file.exists()) return _SourceState({}, {});
    if (await file.length() > _maxStateBytes) {
      throw const FormatException('Saved local extension data is too large.');
    }
    final data = _decode(await file.readAsBytes());
    return _SourceState(
      _object(data['repositories']),
      _object(data['extensions']),
    );
  }

  Future<T> _change<T>(FutureOr<T> Function(_SourceState state) update) =>
      _serial(() async {
        final state = await _readState();
        final value = await update(state);
        final bytes = utf8.encode(
          jsonEncode({
            'repositories': state.repositories,
            'extensions': state.extensions,
          }),
        );
        if (bytes.length > _maxStateBytes) {
          throw StateError('Local extension storage is full.');
        }
        await _directory.create(recursive: true);
        await _atomicWrite(_state, bytes);
        return value;
      });

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static Future<void> _atomicWrite(File target, List<int> bytes) async {
    final staging = File('${target.path}.part');
    await staging.writeAsBytes(bytes, flush: true);
    await staging.rename(target.path);
  }
}

class _Manifest {
  const _Manifest({
    required this.id,
    required this.name,
    required this.version,
    required this.language,
    required this.catalog,
    required this.mediaOrigins,
    this.isShinigami = false,
    this.nativeIcon,
    this.nativeHomepage,
    this.isNsfw = false,
    this.apkFingerprint,
    this.runtimeSources = const [],
  });

  final String id;
  final String name;
  final String version;
  final String language;
  final Uri catalog;
  final Set<String> mediaOrigins;
  final bool isShinigami;
  final Uri? nativeIcon;
  final Uri? nativeHomepage;
  final bool isNsfw;
  final String? apkFingerprint;
  final List<MihonRuntimeSource> runtimeSources;

  Map<String, Object?> toJson() => {
    'format': apkFingerprint != null
        ? 'kuchie.mihon.v1'
        : isShinigami
        ? 'kuchie.native-shinigami.v1'
        : 'kuchie.extension.v1',
    'id': id,
    'name': name,
    'version': version,
    'language': language,
    'catalog': catalog.toString(),
    'mediaOrigins': mediaOrigins.toList()..sort(),
    if (apkFingerprint != null) ...{
      'apkFingerprint': apkFingerprint,
      'icon': nativeIcon?.toString(),
      'nsfw': isNsfw,
      'runtimeSources': [
        for (final source in runtimeSources)
          {
            'id': source.id,
            'name': source.name,
            'language': source.language,
            'homepage': source.homepage?.toString(),
            'supportsLatest': source.supportsLatest,
          },
      ],
    },
  };
}

class _SourceHttpException extends HttpException {
  _SourceHttpException(this.statusCode, Uri url)
    : super('HTTP $statusCode', uri: url);

  final int statusCode;

  bool get canUseCachedResponse =>
      statusCode == HttpStatus.forbidden ||
      statusCode == HttpStatus.tooManyRequests ||
      statusCode >= HttpStatus.internalServerError;
}

class _SourceState {
  const _SourceState(this.repositories, this.extensions);

  final Map<String, Object?> repositories;
  final Map<String, Object?> extensions;
}

Map<String, Object?> _repositoryJson(LocalSourceRepository repo) =>
    repo.hasNativeAdapters
    ? {
        'format': 'kuchie.keiyoushi.v2',
        'extensions': [
          for (final package in repo.packages)
            {
              'id': package.id,
              'name': package.name,
              'version': package.version,
              'language': package.language,
              'apk': package._mihon ? package.url.toString() : null,
              'icon': package.icon?.toString(),
              'nsfw': package.isNsfw,
            },
        ],
      }
    : {
        'format': 'kuchie.repository.v1',
        'name': repo.name,
        'extensions': [
          for (final package in repo.packages)
            {
              'id': package.id,
              'name': package.name,
              'version': package.version,
              'language': package.language,
              'url': package.url.toString(),
              'sha256': package.sha256,
              'catalogOrigin': package.catalogOrigin.toString(),
            },
        ],
      };

Map<String, Object?> _extensionJson(LocalExtension extension) => {
  'manifest': extension._manifest.toJson(),
  'enabled': extension.enabled,
  'repository': extension.repository?.toString(),
};

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?> _decode(Uint8List bytes) =>
    _object(jsonDecode(utf8.decode(bytes)));

List<Object?> _list(Map<String, Object?> data, String key, int max) {
  final value = data[key];
  if (value is! List<Object?> || value.length > max) {
    throw FormatException('Invalid extension field: $key.');
  }
  return value;
}

String _string(
  Map<String, Object?> data,
  String key, {
  int max = 2048,
  bool allowEmpty = false,
}) {
  final value = data[key];
  if (value is! String ||
      (!allowEmpty && value.trim().isEmpty) ||
      value.length > max) {
    throw FormatException('Invalid extension field: $key.');
  }
  return value;
}

String _id(Map<String, Object?> data, String key) {
  final id = _string(data, key, max: 128);
  if (!LocalSources._idPattern.hasMatch(id)) {
    throw const FormatException('Invalid extension identifier.');
  }
  return id;
}

String _version(Map<String, Object?> data) {
  final version = _string(data, 'version', max: 64);
  Version.parse(version);
  return version;
}

String _sha256(Uint8List bytes) => SHA256Digest()
    .process(bytes)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

String _mihonLocatorId(String locator) =>
    _sha256(Uint8List.fromList(utf8.encode(locator)));

bool _isPackagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.json') || lower.endsWith('.kuchie-source');
}
