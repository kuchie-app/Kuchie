import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/sha256.dart';

class MihonRuntimeSource {
  const MihonRuntimeSource({
    required this.id,
    required this.name,
    required this.language,
    this.homepage,
    this.supportsLatest = true,
  });

  final String id;
  final String name;
  final String language;
  final Uri? homepage;
  final bool supportsLatest;
}

class MihonRuntimeManga {
  const MihonRuntimeManga({
    required this.locator,
    required this.title,
    this.description = '',
    this.cover,
    this.coverHeaders = const {},
    this.author = '',
    this.artist = '',
    this.status = 0,
    this.genres = const [],
  });

  final String locator;
  final String title;
  final String description;
  final Uri? cover;
  final Map<String, String> coverHeaders;
  final String author;
  final String artist;
  final int status;
  final List<String> genres;

  String get stableLocator => _stableLocator(locator);
}

class MihonRuntimeChapter {
  const MihonRuntimeChapter({
    required this.locator,
    required this.title,
    this.uploadDate,
    this.number,
  });

  final String locator;
  final String title;
  final DateTime? uploadDate;
  final double? number;

  String get stableLocator => _stableLocator(locator);
}

String _stableLocator(String locator) {
  const marker = '|mangayomi-memo|';
  final index = locator.lastIndexOf(marker);
  return index > 0 ? locator.substring(0, index) : locator;
}

class MihonRuntimePage {
  const MihonRuntimePage({required this.url, this.headers = const {}});

  final Uri url;
  final Map<String, String> headers;
}

class MihonRuntimeException implements Exception {
  const MihonRuntimeException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MihonRuntimeUnavailable extends MihonRuntimeException {
  const MihonRuntimeUnavailable(super.message);
}

/// Talks to the M-Extension-Server HTTP bridge inside this app.
class MihonRuntimeClient {
  MihonRuntimeClient({
    http.Client? client,
    Future<Uri> Function()? resolveEndpoint,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _resolveEndpoint = resolveEndpoint == null
           ? _startEmbeddedServer
           : (() async => (url: await resolveEndpoint(), token: null));

  static const _channel = MethodChannel('m_extension_server');
  static const _preferredPort = 34879;
  static const _timeout = Duration(seconds: 45);
  static const _maxResponseBytes = 12 * 1024 * 1024;
  static const _maxApkBytes = 16 * 1024 * 1024;
  static final _sourceId = RegExp(r'^-?\d{1,19}$');
  static final _portSuffix = RegExp(r'\bport (\d+)$');
  static final _headerName = RegExp(r'^[A-Za-z0-9!#$%&\x27*+.^_`|~\-]+$');
  static const _unsafeImageHeaders = {
    'connection',
    'content-length',
    'host',
    'keep-alive',
    'proxy-authorization',
    'proxy-connection',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'x-kuchie-runtime-token',
  };

  final http.Client _client;
  final bool _ownsClient;
  final Future<_RuntimeEndpoint> Function() _resolveEndpoint;
  final _keys = Expando<String>();
  Future<_RuntimeEndpoint>? _endpoint;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<MihonRuntimeSource>> inspect(
    Uint8List apk, {
    required String packageName,
  }) async {
    final response = await _invoke(apk, 'extensionInfo');
    final extension = _object(response.result);
    if (extension['packageName'] != packageName ||
        extension['itemType'] != 'manga') {
      throw const MihonRuntimeException(
        'The APK does not match the manga extension in the repository.',
      );
    }
    final entries = _list(extension['sources'], limit: 1000);
    if (entries.isEmpty) {
      throw const MihonRuntimeException(
        'The extension has no compatible manga sources.',
      );
    }
    return [for (final entry in entries) _parseSource(_object(entry))];
  }

  Future<({List<MihonRuntimeManga> items, bool hasMore})> browse(
    Uint8List apk,
    MihonRuntimeSource source, {
    required String query,
    required bool latest,
    required int page,
  }) async {
    final response = await _invoke(
      apk,
      query.isNotEmpty
          ? 'getSearchManga'
          : latest && source.supportsLatest
          ? 'getLatestManga'
          : 'getPopularManga',
      source: source,
      arguments: {'page': page, if (query.isNotEmpty) 'search': query},
    );
    final data = _object(response.result);
    final mangas = _list(data['mangas'], limit: 1000);
    return (
      items: [
        for (final manga in mangas)
          _parseManga(_object(manga), response.endpoint),
      ],
      hasMore: data['hasNextPage'] == true,
    );
  }

  Future<MihonRuntimeManga> details(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonRuntimeManga manga,
  ) async {
    final response = await _invoke(
      apk,
      'getDetailsManga',
      source: source,
      arguments: {'mangaData': _mangaPayload(manga)},
    );
    // Like Mihon, details refine the entry the reader opened: an extension
    // that leaves the URL or title empty keeps the ones from the listing.
    return _parseManga(
      _object(response.result),
      response.endpoint,
      listed: manga,
    );
  }

  Future<List<MihonRuntimeChapter>> chapters(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonRuntimeManga manga,
  ) async {
    final response = await _invoke(
      apk,
      'getChapterList',
      source: source,
      arguments: {'mangaData': _mangaPayload(manga)},
    );
    return [
      for (final value in _list(response.result, limit: 10000))
        _parseChapter(_object(value)),
    ];
  }

  Future<List<MihonRuntimePage>> pages(
    Uint8List apk,
    MihonRuntimeSource source,
    MihonRuntimeChapter chapter,
  ) async {
    final response = await _invoke(
      apk,
      'getPageList',
      source: source,
      arguments: {
        'chapterData': {'url': chapter.locator, 'name': chapter.title},
      },
    );
    final entries = _list(response.result, limit: 4000);
    if (entries.isEmpty) {
      throw const MihonRuntimeException('The extension returned no pages.');
    }
    return [
      for (final entry in entries)
        _parsePage(_object(entry), response.endpoint),
    ];
  }

  Future<_RuntimeEndpoint> _readyEndpoint() async {
    final flight = _endpoint ??= _connect();
    try {
      return await flight;
    } catch (_) {
      if (identical(_endpoint, flight)) _endpoint = null;
      rethrow;
    }
  }

  Future<_RuntimeEndpoint> _connect() async {
    try {
      return await _checkRuntime();
    } on http.ClientException {
      throw const MihonRuntimeUnavailable(
        'Could not reach the extension runtime.',
      );
    } on TimeoutException {
      throw const MihonRuntimeUnavailable(
        'The extension runtime took too long to start.',
      );
    }
  }

  Future<_RuntimeEndpoint> _checkRuntime() async {
    final endpoint = await _resolveEndpoint().timeout(_timeout);
    final url = endpoint.url;
    if (url.scheme != 'http' ||
        url.host != '127.0.0.1' ||
        !url.hasPort ||
        url.port < 1 ||
        url.userInfo.isNotEmpty ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasQuery ||
        url.hasFragment) {
      throw const MihonRuntimeUnavailable('Invalid extension runtime address.');
    }
    final capabilities = _object(
      await _send(url.replace(path: '/capabilities'), token: endpoint.token),
    );
    if (capabilities['extensionInfo'] != true ||
        capabilities['extensionHandles'] != true) {
      throw const MihonRuntimeUnavailable(
        'This extension runtime version is incompatible.',
      );
    }
    return endpoint;
  }

  static Future<_RuntimeEndpoint> _startEmbeddedServer() async {
    try {
      final response = await _channel.invokeMethod<Object?>('startServer', {
        'port': _preferredPort,
      });
      final port = switch (response) {
        {'port': final int port} => port,
        final String status =>
          int.tryParse(status) ??
              int.tryParse(_portSuffix.firstMatch(status)?.group(1) ?? ''),
        _ => null,
      };
      if (port == null || port < 1 || port > 65535) {
        throw const MihonRuntimeUnavailable(
          'The extension runtime did not start.',
        );
      }
      final token = response is Map ? response['token'] : null;
      if (token != null &&
          (token is! String ||
              token.isEmpty ||
              token.length > 256 ||
              token.contains(RegExp(r'\s')))) {
        throw const MihonRuntimeUnavailable(
          'Invalid extension runtime credentials.',
        );
      }
      return (
        url: Uri(scheme: 'http', host: '127.0.0.1', port: port),
        token: token as String?,
      );
    } on MissingPluginException {
      throw const MihonRuntimeUnavailable(
        'The extension runtime is unavailable on this device.',
      );
    } on PlatformException catch (error) {
      throw MihonRuntimeUnavailable(
        error.message ?? 'The extension runtime did not start.',
      );
    }
  }

  Future<({Uri endpoint, Object? result})> _invoke(
    Uint8List apk,
    String method, {
    MihonRuntimeSource? source,
    Map<String, Object?> arguments = const {},
  }) async {
    if (apk.isEmpty || apk.length > _maxApkBytes) {
      throw const MihonRuntimeException(
        'The extension APK has an invalid size.',
      );
    }
    final key = _keys[apk] ??= SHA256Digest()
        .process(apk)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final body = {
      'method': method,
      if (source != null) 'sourceId': source.id,
      ...arguments,
    };

    Future<({Uri endpoint, Object? result})> execute(
      _RuntimeEndpoint endpoint,
    ) async {
      final target = endpoint.url.replace(path: '/dalvik');
      try {
        return (
          endpoint: endpoint.url,
          result: await _send(
            target,
            token: endpoint.token,
            jsonBody: {...body, 'extensionId': key},
          ),
        );
      } on MihonRuntimeException catch (error) {
        if (error.statusCode != 409) rethrow;
        return (
          endpoint: endpoint.url,
          result: await _send(
            target,
            token: endpoint.token,
            jsonBody: {...body, 'data': base64Encode(apk)},
          ),
        );
      }
    }

    final endpoint = await _readyEndpoint();
    try {
      return await execute(endpoint);
    } on http.ClientException {
      // The iOS bridge may pause its listener while the app is in background.
      _endpoint = null;
      return execute(await _readyEndpoint());
    }
  }

  Future<Object?> _send(
    Uri uri, {
    required String? token,
    Map<String, Object?>? jsonBody,
  }) async {
    final request = http.Request(jsonBody == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['X-Kuchie-Runtime-Token'] = token;
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    }
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen(null).cancel();
      throw MihonRuntimeException(
        'The extension could not complete the request.',
        statusCode: response.statusCode,
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(_timeout)) {
      if (bytes.length + chunk.length > _maxResponseBytes) {
        throw const MihonRuntimeException(
          'The extension response is too large.',
        );
      }
      bytes.add(chunk);
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw const MihonRuntimeException('The extension returned invalid data.');
    }
  }

  static MihonRuntimeSource _parseSource(Map<String, Object?> data) {
    final id = _text(data['id'], max: 20);
    if (!_sourceId.hasMatch(id)) {
      throw const MihonRuntimeException(
        'The extension returned an invalid source.',
      );
    }
    return MihonRuntimeSource(
      id: id,
      name: _text(data['name'], max: 256),
      language: _text(data['lang'], max: 32),
      homepage: _httpUrl(data['baseUrl']),
    );
  }

  static MihonRuntimeManga _parseManga(
    Map<String, Object?> data,
    Uri endpoint, {
    MihonRuntimeManga? listed,
  }) => MihonRuntimeManga(
    locator: switch (_locator(data['url'])) {
      '' when listed != null => listed.locator,
      final locator => locator,
    },
    title:
        _labelOrNull(data['title'], max: 1024) ?? listed?.title ?? 'Untitled',
    description: _optionalText(data['description'], max: 16000),
    cover: _imageUrl(data['thumbnail_url'], endpoint),
    author: _optionalText(data['author'], max: 2048),
    artist: _optionalText(data['artist'], max: 2048),
    status: switch (data['status']) {
      final int status when status >= 0 && status <= 6 => status,
      _ => 0,
    },
    genres: List.unmodifiable(
      _optionalText(data['genre'], max: 4096)
          .split(',')
          .map((genre) => genre.trim())
          .where((genre) => genre.isNotEmpty),
    ),
  );

  static Map<String, String> _mangaPayload(MihonRuntimeManga manga) => {
    'url': manga.locator,
    'title': manga.title,
    if (manga.description.isNotEmpty) 'description': manga.description,
  };

  static MihonRuntimeChapter _parseChapter(
    Map<String, Object?> data,
  ) => MihonRuntimeChapter(
    locator: _locator(data['url']),
    title:
        _labelOrNull(data['name'], max: 1024) ??
        switch (data['chapter_number']) {
          final num value when value.isFinite && value >= 0 =>
            'Chapter ${value == value.roundToDouble() ? value.toInt() : value}',
          _ => 'Chapter',
        },
    uploadDate: switch (data['date_upload']) {
      final int millis when millis > 0 && millis <= 8640000000000000 =>
        DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      _ => null,
    },
    number: switch (data['chapter_number']) {
      final num value when value.isFinite && value >= 0 => value.toDouble(),
      _ => null,
    },
  );

  static MihonRuntimePage _parsePage(Map<String, Object?> data, Uri endpoint) {
    final url =
        _imageUrl(data['imageUrl'], endpoint) ??
        _imageUrl(data['url'], endpoint);
    if (url == null) {
      throw const MihonRuntimeException(
        'The extension returned an invalid page.',
      );
    }
    final headers = url.host == endpoint.host
        ? const <String, String>{}
        : _parseImageHeaders(data['headers']);
    return MihonRuntimePage(url: url, headers: headers);
  }

  static Map<String, String> _parseImageHeaders(Object? value) {
    if (value is! Map<String, Object?> || value.length > 32) return const {};
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.value case final String text
            when entry.key.length <= 128 &&
                _headerName.hasMatch(entry.key) &&
                !_unsafeImageHeaders.contains(entry.key.toLowerCase()) &&
                text.length <= 8192 &&
                !text.contains('\r') &&
                !text.contains('\n') &&
                !text.contains('\u0000'))
          entry.key: text,
    });
  }

  static Uri? _imageUrl(Object? value, Uri endpoint) {
    final url = _httpUrl(value);
    if (url == null) return null;
    if (url.host == 'localhost' ||
        url.host.endsWith('.localhost') ||
        InternetAddress.tryParse(url.host)?.isLoopback == true) {
      if (url.host != endpoint.host ||
          url.scheme != 'http' ||
          url.port != endpoint.port ||
          url.pathSegments.length != 2 ||
          url.pathSegments.first != 'image' ||
          url.pathSegments.last.isEmpty ||
          url.hasQuery) {
        return null;
      }
    }
    return url;
  }

  static Uri? _httpUrl(Object? value) {
    if (value is! String || value.isEmpty || value.length > 16384) return null;
    final url = Uri.tryParse(value);
    if (url == null ||
        (url.scheme != 'https' && url.scheme != 'http') ||
        !url.hasAuthority ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      return null;
    }
    return url;
  }

  static Map<String, Object?> _object(Object? data) {
    if (data is Map<String, Object?>) return data;
    throw const MihonRuntimeException('The extension returned invalid data.');
  }

  static List<Object?> _list(Object? data, {required int limit}) {
    if (data is List<Object?> && data.length <= limit) return data;
    throw const MihonRuntimeException(
      'The extension returned an invalid list.',
    );
  }

  static String _text(Object? value, {required int max}) {
    if (value is String && value.trim().isNotEmpty && value.length <= max) {
      return value;
    }
    throw const MihonRuntimeException('The extension returned invalid text.');
  }

  /// A manga or chapter URL as the extension stores it. Mihon allows an empty
  /// one: single-series sources use the site's front page.
  static String _locator(Object? value) {
    if (value is String && value.length <= 16384) return value;
    throw const MihonRuntimeException('The extension returned invalid text.');
  }

  static String? _labelOrNull(Object? value, {required int max}) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.length <= max ? value : value.substring(0, max);
  }

  static String _optionalText(Object? value, {required int max}) =>
      value is String ? value.substring(0, value.length.clamp(0, max)) : '';
}

typedef _RuntimeEndpoint = ({Uri url, String? token});
