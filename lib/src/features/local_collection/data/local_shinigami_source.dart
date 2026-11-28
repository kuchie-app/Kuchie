part of 'local_sources.dart';

final _keiyoushiIndex = Uri.parse(
  'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json',
);

bool _isKeiyoushiUrl(Uri url) {
  if (url.scheme != 'https' ||
      url.hasPort ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment) {
    return false;
  }
  const filenames = {'index.pb', 'index.json', 'index.min.json', 'repo.json'};
  final path = url.path;
  if (url.host == 'keiyoushi.github.io') {
    return const {'', '/', '/extensions', '/extensions/'}.contains(path);
  }
  if (url.host == 'github.com') {
    if (const {
      '/keiyoushi/extensions',
      '/keiyoushi/extensions/',
    }.contains(path)) {
      return true;
    }
    return filenames.any(
      (name) =>
          path == '/keiyoushi/extensions/raw/repo/$name' ||
          path == '/keiyoushi/extensions/blob/repo/$name' ||
          path == '/keiyoushi/extensions/raw/refs/heads/repo/$name' ||
          path == '/keiyoushi/extensions/blob/refs/heads/repo/$name',
    );
  }
  return url.host == 'raw.githubusercontent.com' &&
      filenames.any(
        (name) =>
            path == '/keiyoushi/extensions/repo/$name' ||
            path == '/keiyoushi/extensions/refs/heads/repo/$name',
      );
}

/// The certificate Keiyoushi signs its APKs with, for stores saved before
/// Kuchie recorded each store's key.
const keiyoushiSigningKey =
    '9add655a78e96c4ec7a53ef89dccb557cb5d767489fac5e785d671a5a75d4da2';

Uri? _secureArtifactUri(String raw) {
  final uri = raw.length <= 2048 ? Uri.tryParse(raw) : null;
  return uri != null &&
          uri.scheme == 'https' &&
          uri.hasAuthority &&
          uri.host.isNotEmpty &&
          !uri.hasPort &&
          uri.userInfo.isEmpty &&
          !uri.hasFragment
      ? uri
      : null;
}

// API routes and field names follow the public Shinigami API used by Keiyoushi.
class _ShinigamiSource {
  static const id = 'eu.kanade.tachiyomi.extension.id.shinigami';
  static const sourceId = '3411809758861089969';
  static const _apiHost = 'api.shngm.io';
  static const _assetOrigin = 'https://assets.shngm.id';
  static final origin = Uri.https(_apiHost);
  static final icon = Uri.parse(
    'https://cdn.jsdelivr.net/gh/keiyoushi/extensions-source@main/src/id/shinigami/res/mipmap-xhdpi/ic_launcher.png',
  );
  static final _homepage = Uri.https('11.shinigami.asia');

  static _Manifest manifest(String version, {Uri? icon}) => _Manifest(
    id: id,
    name: 'Shinigami',
    version: version,
    language: 'id',
    catalog: browseUrl('', false, 1),
    mediaOrigins: const {_assetOrigin},
    isShinigami: true,
    nativeIcon: icon,
    nativeHomepage: _homepage,
  );

  static Uri browseUrl(String query, bool latest, int page) =>
      Uri.https(_apiHost, '/v1/manga/list', {
        'page': '$page',
        'page_size': '30',
        if (query.isNotEmpty)
          'q': query
        else
          'sort': latest ? 'latest' : 'popularity',
      });

  static Uri detailsUrl(String mangaId) =>
      Uri.https(_apiHost, '/v1/manga/detail/$mangaId');

  static ({List<LocalSourceManga> items, bool hasMore}) browse(
    LocalExtension source,
    Map<String, Object?> envelope,
  ) {
    _verified(envelope);
    final meta = _object(envelope['meta']);
    final page = _positiveInt(meta['page']);
    final total = _positiveInt(meta['total_page']);
    final seen = <String>{};
    final manga = <LocalSourceManga>[];
    for (final value in _list(envelope, 'data', 30)) {
      final entry = _object(value);
      final mangaId = _id(entry, 'manga_id');
      if (!seen.add(mangaId)) continue;
      manga.add(_manga(source, entry, id: mangaId));
    }
    return (
      items: manga,
      hasMore: page != null && total != null && page < total,
    );
  }

  static LocalSourceManga details(
    LocalExtension source,
    LocalSourceManga manga,
    Map<String, Object?> envelope,
  ) {
    _verified(envelope);
    return _manga(
      source,
      _object(envelope['data']),
      id: manga.id,
      known: manga,
    );
  }

  static LocalSourceManga _manga(
    LocalExtension source,
    Map<String, Object?> entry, {
    required String id,
    LocalSourceManga? known,
  }) {
    final covers = {
      ...[
        _thumbnail(entry['cover_portrait_url']),
        _thumbnail(entry['cover_image_url']),
        known?.cover,
        known?.coverFallback,
      ].nonNulls,
    };
    final taxonomy = entry['taxonomy'];
    final authors = _taxonomy(taxonomy, 'Author');
    final artists = _taxonomy(taxonomy, 'Artist');
    final genres = {
      ..._taxonomy(taxonomy, 'Genre'),
      ..._taxonomy(taxonomy, 'Format'),
    };
    final status = switch (entry['status']) {
      1 => 1,
      2 => 2,
      3 => 6, // Shinigami API and Mihon use different codes for hiatus.
      _ => known?.status ?? 0,
    };
    return LocalSourceManga._(
      id: id,
      title:
          _optionalText(entry['title'], max: 384) ??
          known?.title ??
          _string(entry, 'title', max: 384),
      description:
          _optionalText(entry['description'], max: 12000) ??
          known?.description ??
          '',
      cover: covers.firstOrNull,
      coverFallback: covers.skip(1).firstOrNull,
      author: authors.isEmpty ? known?.author ?? '' : authors.join(', '),
      artist: artists.isEmpty ? known?.artist ?? '' : artists.join(', '),
      status: status,
      genres: genres.isEmpty
          ? known?.genres ?? const []
          : List.unmodifiable(genres),
      alternativeTitle:
          _optionalText(entry['alternative_title'], max: 1024) ??
          known?.alternativeTitle ??
          '',
      webUrl: _homepage.replace(pathSegments: ['series', id]),
      feed: Uri.https(_apiHost, '/v1/chapter/$id/list', {'page_size': '3000'}),
      sourceId: source.id,
      sourceVersion: source.version,
    );
  }

  static Uri? _thumbnail(Object? value) {
    final raw = _optionalText(value, max: 2048);
    final url = raw == null ? null : Uri.tryParse(raw);
    return url != null &&
            url.scheme == 'https' &&
            url.hasAuthority &&
            url.origin == _assetOrigin &&
            url.userInfo.isEmpty &&
            !url.hasFragment
        ? url
        : null;
  }

  static Iterable<String> _taxonomy(Object? value, String key) sync* {
    if (value is! Map<String, Object?>) return;
    final items = value[key];
    if (items is! List<Object?>) return;
    for (final item in items.take(100)) {
      if (item is! Map<String, Object?>) continue;
      if (_optionalText(item['name'], max: 256) case final String name) {
        yield name;
      }
    }
  }

  static String? _optionalText(Object? value, {required int max}) =>
      value is String && value.length <= max && value.trim().isNotEmpty
      ? value.trim()
      : null;

  static List<LocalSourceChapter> chapters(
    LocalExtension source,
    Map<String, Object?> envelope,
  ) {
    _verified(envelope);
    final seen = <String>{};
    final chapters = <LocalSourceChapter>[];
    for (final value in _list(envelope, 'data', 3000)) {
      final entry = _object(value);
      final chapterId = _id(entry, 'chapter_id');
      if (!seen.add(chapterId)) continue;
      final number = entry['chapter_number'];
      if (number is! num || !number.isFinite) {
        throw const FormatException('Invalid Shinigami chapter number.');
      }
      final titleNumber = number == number.truncate()
          ? '${number.truncate()}'
          : '$number';
      final subtitle = entry['chapter_title'];
      final title = subtitle is String && subtitle.trim().isNotEmpty
          ? 'Chapter $titleNumber ${subtitle.trim()}'
          : 'Chapter $titleNumber';
      chapters.add(
        LocalSourceChapter._(
          id: chapterId,
          title: title,
          feed: Uri.https(_apiHost, '/v1/chapter/detail/$chapterId'),
          sourceId: source.id,
          sourceVersion: source.version,
          uploadDate: switch (entry['release_date']) {
            final String date when date.length <= 64 => DateTime.tryParse(date),
            _ => null,
          },
          number: number.toDouble(),
        ),
      );
    }
    return chapters;
  }

  static List<Uri> pages(
    Map<String, Object?> envelope,
    Uri Function(String path) validate,
  ) {
    _verified(envelope);
    final data = _object(envelope['data']);
    final chapter = _object(data['chapter']);
    final names = _list(chapter, 'data', 1000);
    if (names.isEmpty) throw const FormatException('The chapter has no pages.');
    final origin = _string(data, 'base_url');
    if (origin != _assetOrigin) {
      throw const FormatException('Unknown Shinigami image host.');
    }
    final path = _string(chapter, 'path');
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    if (!path.startsWith('/chapter/') ||
        !path.endsWith('/') ||
        !segments.every(_pathSegment.hasMatch)) {
      throw const FormatException('Invalid Shinigami image path.');
    }
    return [
      for (final value in names)
        if (value is String && _pathSegment.hasMatch(value))
          validate('$origin$path$value')
        else
          throw const FormatException('Invalid Shinigami page filename.'),
    ];
  }

  static final _pathSegment = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]*$');

  static void _verified(Map<String, Object?> envelope) {
    if (envelope['retcode'] != 0) {
      throw const FormatException('Shinigami returned an invalid response.');
    }
  }

  static int? _positiveInt(Object? value) =>
      value is int && value > 0 ? value : null;
}
