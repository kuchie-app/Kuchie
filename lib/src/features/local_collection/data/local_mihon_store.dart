part of 'local_sources.dart';

// Mihon extension stores, read the way Mihon's ExtensionStoreService reads
// them: a v2 index as protobuf or JSON (optionally gzipped, optionally with the
// extension list behind `extensionListUrl`), or a legacy `index.min.json` with
// its `repo.json`, whose `index_v2` points at the v2 index when there is one.
// Trust comes from the store's signing key: an APK installs only when one of
// its verified signer certificates has that SHA-256 fingerprint.

const _maxMihonStoreBytes = 16 * 1024 * 1024;

final _mihonPackagePattern = RegExp(
  r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_-]+){1,15}$',
);

// Top-level so the isolate closure captures only the bytes, never a
// LocalSources (its HTTP client and runtime cannot cross isolates).
Future<Object?> _decodeMihonDocumentInBackground(Uint8List bytes) =>
    Isolate.run(() => _decodeMihonDocument(bytes));

Future<List<String>> _verifyApkSignersInBackground(Uint8List apk) =>
    Isolate.run(() => verifyApkSigners(apk));

/// Decodes a store document: JSON (object or legacy array) or v2 protobuf.
Object? _decodeMihonDocument(Uint8List raw) {
  var bytes = raw;
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    final sink = _CappedSink(_maxMihonStoreBytes);
    gzip.decoder.startChunkedConversion(sink)
      ..add(bytes)
      ..close();
    bytes = sink.bytes.takeBytes();
  }
  final first = bytes.firstWhere(
    (byte) => byte != 0x20 && byte != 0x0a && byte != 0x0d && byte != 0x09,
    orElse: () => -1,
  );
  if (first == 0x5b || first == 0x7b) return jsonDecode(utf8.decode(bytes));
  return _MihonProto(bytes).store();
}

/// A Mihon `repo.json`: the legacy store metadata.
({String name, String signingKey, Uri? indexV2})? _mihonLegacyMeta(
  Object? document,
) {
  if (document is! Map<String, Object?> || document['meta'] is! Map) {
    return null;
  }
  final meta = _object(document['meta']);
  final rawV2 = document['index_v2'];
  final indexV2 = rawV2 is String ? _secureArtifactUri(rawV2) : null;
  if (rawV2 != null && indexV2 == null) {
    throw const LocalSourceSecurityException(
      'Use an HTTPS URL without credentials or fragments.',
      insecureUrl: true,
    );
  }
  return (
    name: _string(meta, 'name', max: 160),
    signingKey: _mihonSigningKey(meta['signingKeyFingerprint']),
    indexV2: indexV2,
  );
}

final _storeLinkPattern = RegExp(
  r'''(?:mihon://extension-store|tachiyomi://add-repo)\?url=([^"'&<>\s]+)''',
);

/// The first "add store" link on an HTML page, or null for other documents.
Uri? _storeLinkInPage(Uint8List bytes) {
  final first = bytes.firstWhere(
    (byte) => byte != 0x20 && byte != 0x0a && byte != 0x0d && byte != 0x09,
    orElse: () => -1,
  );
  if (first != 0x3c) return null; // '<'
  final html = utf8.decode(bytes, allowMalformed: true);
  for (final match in _storeLinkPattern.allMatches(html)) {
    final String raw;
    try {
      raw = Uri.decodeComponent(match.group(1)!.replaceAll('&amp;', '&'));
    } on ArgumentError {
      continue;
    }
    final url = Uri.tryParse(raw);
    if (url != null && url.scheme == 'https' && url.hasAuthority) return url;
  }
  return null;
}

// Sites a notice entry points at instead of a manga site.
const _noticeHosts = {'keiyoushi.github.io', 'mihon.app', 'tachiyomi.org'};

/// Whether [value] is a notice rather than an extension: retired stores keep
/// an entry such as "Outdated App" or "Please migrate to Keiyoushi" whose
/// sources have made-up ids and point at an app site, or whose APK link is a
/// web page.
bool _isMihonNotice(Map<String, Object?> value) {
  final sources = value['sources'];
  if (sources is! List<Object?> || sources.isEmpty) return false;
  final resources = value['resources'];
  final apk = value['apk'] ?? (resources is Map ? resources['apkUrl'] : null);
  var notice = apk is String && !apk.toLowerCase().endsWith('.apk');
  for (final source in sources) {
    if (source is! Map) return false;
    final id = int.tryParse('${source['id']}');
    // Real sources use hashed ids; a few old ones picked small numbers.
    if (id == null || id.abs() >= 1000) return false;
    final home = Uri.tryParse(
      '${source['homeUrl'] ?? source['baseUrl'] ?? ''}',
    );
    if (home != null && _noticeHosts.contains(home.host)) notice = true;
  }
  return notice;
}

/// Drops notice entries; a store with nothing else is retired.
List<Object?> _withoutNotices(List<Object?> entries, String storeName) {
  final kept = <Object?>[];
  var keiyoushi = false;
  var notices = 0;
  for (final value in entries) {
    if (value is Map<String, Object?> && _isMihonNotice(value)) {
      notices++;
      keiyoushi |= '${value['name']} ${value['pkg'] ?? value['packageName']}'
          .toLowerCase()
          .contains('keiyoushi');
      for (final source in value['sources']! as List<Object?>) {
        if (source is Map) {
          final home = source['homeUrl'] ?? source['baseUrl'];
          keiyoushi |= '$home'.contains('keiyoushi.github.io');
        }
      }
    } else {
      kept.add(value);
    }
  }
  if (kept.isEmpty && notices > 0) {
    throw LocalSourceRetiredStoreException(
      storeName,
      movedToKeiyoushi: keiyoushi,
    );
  }
  return kept;
}

/// The store's signing key, as a lowercase SHA-256 hex digest.
///
/// Like Mihon, a store whose key is missing or not a SHA-256 (some publish an
/// MD5, a SHA-1 or a placeholder) is still added: its APKs simply match no
/// key, and each one needs the reader's explicit trust before it installs.
String _mihonSigningKey(Object? raw) {
  if (raw is! String) return '';
  final key = raw.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
  return key.length <= 128 ? key : '';
}

/// Normalises v2 extensions (`extensionList.extensions`) to Kuchie packages.
List<Map<String, Object?>> _mihonV2Packages(
  List<Object?> entries, {
  required bool keiyoushi,
}) => [
  for (final value in entries)
    if (value is Map<String, Object?>)
      ?_mihonV2Package(value, keiyoushi: keiyoushi),
];

Map<String, Object?>? _mihonV2Package(
  Map<String, Object?> value, {
  required bool keiyoushi,
}) {
  final id = value['packageName'];
  final version = value['versionName'];
  final sources = value['sources'];
  if (id is! String ||
      !_isMangaPackage(id) ||
      !_supportedLib('${value['extensionLib'] ?? ''}') ||
      version is! String ||
      !_validVersion(version) ||
      sources is! List<Object?> ||
      sources.isEmpty) {
    return null;
  }
  final isShinigami =
      keiyoushi &&
      id == _ShinigamiSource.id &&
      sources.any(
        (source) =>
            source is Map && '${source['id']}' == _ShinigamiSource.sourceId,
      );
  final resources = value['resources'];
  final apk = resources is Map ? resources['apkUrl'] : null;
  final icon = resources is Map ? resources['iconUrl'] : null;
  final name = value['name'];
  if (!isShinigami &&
      (apk is! String ||
          _secureArtifactUri(apk) == null ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 160)) {
    return null;
  }
  final languages = {
    for (final source in sources)
      if (source is Map && source['language'] is String) source['language'],
  };
  return {
    'id': id,
    'name': isShinigami ? 'Shinigami' : name,
    'version': version,
    'language': languages.length == 1 ? languages.single : 'all',
    'apk': isShinigami ? null : apk,
    'icon': icon is String ? _secureArtifactUri(icon)?.toString() : null,
    'nsfw': value['contentWarning'] == 'CONTENT_WARNING_NSFW',
    'sources': _mihonSourceIds(sources),
  };
}

/// The Mihon source ids an extension serves, as the sync server names
/// sources (sync matches series by them).
List<String> _mihonSourceIds(Object? sources) => [
  if (sources is List<Object?>)
    for (final source in sources.take(256))
      if (source is Map)
        if ('${source['id']}' case final id
            when LocalSources._mihonId.hasMatch(id))
          id,
];

/// Normalises a legacy `index.min.json` array, whose files live beside it.
List<Map<String, Object?>> _mihonLegacyPackages(
  List<Object?> entries,
  Uri base,
) => [
  for (final value in entries)
    if (value is Map<String, Object?>) ?_mihonLegacyPackage(value, base),
];

final _apkFilePattern = RegExp(r'^[A-Za-z0-9._-]{1,200}\.apk$');

Map<String, Object?>? _mihonLegacyPackage(
  Map<String, Object?> value,
  Uri base,
) {
  final id = value['pkg'];
  final apk = value['apk'];
  final version = value['version'];
  final name = value['name'];
  final language = value['lang'];
  if (id is! String ||
      !_isMangaPackage(id) ||
      version is! String ||
      !_validVersion(version) ||
      // Legacy versions are "<lib>.<code>", e.g. 1.4.29 for lib 1.4.
      !_supportedLib(version.substring(0, version.lastIndexOf('.'))) ||
      apk is! String ||
      !_apkFilePattern.hasMatch(apk) ||
      name is! String ||
      language is! String ||
      language.isEmpty ||
      language.length > 32) {
    return null;
  }
  final label = name.startsWith('Tachiyomi: ')
      ? name.substring('Tachiyomi: '.length)
      : name;
  if (label.trim().isEmpty || label.length > 160) return null;
  return {
    'id': id,
    'name': label,
    'version': version,
    'language': language,
    'apk': base.resolve('apk/$apk').toString(),
    'icon': base.resolve('icon/$id.png').toString(),
    'nsfw': value['nsfw'] == 1,
    'sources': _mihonSourceIds(value['sources']),
  };
}

/// Mihon loads manga extensions only; Aniyomi's anime extensions share the
/// stores but not the API.
bool _isMangaPackage(String id) =>
    _mihonPackagePattern.hasMatch(id) && !id.contains('.animeextension.');

/// The extension-lib versions Mihon loads (ExtensionLoader's
/// SUPPORTED_LIB_VERSIONS). Others would install and then never run.
bool _supportedLib(String lib) => const {'1.4', '1.6'}.contains(lib);

bool _validVersion(String version) {
  if (version.length > 64) return false;
  try {
    Version.parse(version);
    return true;
  } on FormatException {
    return false;
  }
}

/// The directory a store file sits in, for its `repo.json` and legacy files.
Uri _mihonBase(Uri index) => index.replace(
  path: index.path.substring(0, index.path.lastIndexOf('/') + 1),
  query: null,
);

/// Reads the v2 `NetworkExtensionStore` protobuf into its JSON shape.
class _MihonProto {
  _MihonProto(this._bytes, [this._offset = 0, int? end])
    : _end = end ?? _bytes.length;

  final Uint8List _bytes;
  int _offset;
  final int _end;

  static const _warnings = [
    'CONTENT_WARNING_UNSPECIFIED',
    'CONTENT_WARNING_SAFE',
    'CONTENT_WARNING_MIXED',
    'CONTENT_WARNING_NSFW',
  ];

  Map<String, Object?> store() {
    final store = <String, Object?>{};
    _fields((field, wire, reader) {
      switch (field) {
        case 1:
          store['name'] = reader.string(wire);
        case 2:
          store['badgeLabel'] = reader.string(wire);
        case 3:
          store['signingKey'] = reader.string(wire);
        case 101:
          store['extensionList'] = reader.message(wire).extensionList();
        case 102:
          store['extensionListUrl'] = reader.string(wire);
        default:
          reader.skip(wire);
      }
    });
    return store;
  }

  Map<String, Object?> extensionList() {
    final extensions = <Object?>[];
    _fields((field, wire, reader) {
      if (field == 1) {
        if (extensions.length >= 20000) {
          throw const FormatException('The extension store is too large.');
        }
        extensions.add(reader.message(wire).extension());
      } else {
        reader.skip(wire);
      }
    });
    return {'extensions': extensions};
  }

  Map<String, Object?> extension() {
    final extension = <String, Object?>{'sources': <Object?>[]};
    _fields((field, wire, reader) {
      switch (field) {
        case 1:
          extension['name'] = reader.string(wire);
        case 2:
          extension['packageName'] = reader.string(wire);
        case 3:
          extension['resources'] = reader.message(wire).resources();
        case 4:
          extension['extensionLib'] = reader.string(wire);
        case 5:
          extension['versionCode'] = '${reader.varint(wire)}';
        case 6:
          extension['versionName'] = reader.string(wire);
        case 7:
          final warning = reader.varint(wire);
          extension['contentWarning'] = warning >= 0 && warning < 4
              ? _warnings[warning]
              : _warnings.first;
        case 8:
          (extension['sources']! as List<Object?>).add(
            reader.message(wire).source(),
          );
        default:
          reader.skip(wire);
      }
    });
    return extension;
  }

  Map<String, Object?> resources() {
    final resources = <String, Object?>{};
    _fields((field, wire, reader) {
      switch (field) {
        case 1:
          resources['apkUrl'] = reader.string(wire);
        case 2:
          resources['iconUrl'] = reader.string(wire);
        default:
          reader.skip(wire);
      }
    });
    return resources;
  }

  Map<String, Object?> source() {
    final source = <String, Object?>{};
    _fields((field, wire, reader) {
      switch (field) {
        case 1:
          source['id'] = '${reader.varint(wire)}';
        case 2:
          source['name'] = reader.string(wire);
        case 3:
          source['language'] = reader.string(wire);
        case 4:
          source['homeUrl'] = reader.string(wire);
        default:
          reader.skip(wire);
      }
    });
    return source;
  }

  void _fields(void Function(int field, int wire, _MihonProto reader) read) {
    while (_offset < _end) {
      final key = _varint();
      final field = key >> 3;
      if (field == 0) throw const FormatException('Invalid store index.');
      read(field, key & 7, this);
    }
    if (_offset != _end) throw const FormatException('Invalid store index.');
  }

  int _varint() {
    var result = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (_offset >= _end) throw const FormatException('Invalid store index.');
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
    }
    throw const FormatException('Invalid store index.');
  }

  // A known field with another wire type (an Aniyomi store reusing a number)
  // is skipped, so one odd entry drops out instead of the whole store.

  int varint(int wire) {
    if (wire != 0) {
      skip(wire);
      return -1;
    }
    return _varint();
  }

  (int, int) _delimited(int wire) {
    if (wire != 2) throw const FormatException('Invalid store index.');
    final length = _varint();
    if (length < 0 || length > _end - _offset) {
      throw const FormatException('Invalid store index.');
    }
    final start = _offset;
    _offset += length;
    return (start, start + length);
  }

  String string(int wire) {
    if (wire != 2) {
      skip(wire);
      return '';
    }
    final (start, end) = _delimited(wire);
    if (end - start > 4096) throw const FormatException('Invalid store index.');
    return utf8.decode(Uint8List.sublistView(_bytes, start, end));
  }

  _MihonProto message(int wire) {
    if (wire != 2) {
      skip(wire);
      return _MihonProto(_bytes, _offset, _offset);
    }
    final (start, end) = _delimited(wire);
    return _MihonProto(_bytes, start, end);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        _varint();
      case 1:
        _advance(8);
      case 2:
        _delimited(wire);
      case 5:
        _advance(4);
      default:
        throw const FormatException('Invalid store index.');
    }
  }

  void _advance(int count) {
    if (count > _end - _offset) {
      throw const FormatException('Invalid store index.');
    }
    _offset += count;
  }
}

/// Collects inflated bytes and stops a compressed store that expands too far.
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._max);

  final int _max;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > _max) {
      throw const FormatException('The extension store is too large.');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
