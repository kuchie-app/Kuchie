// Which Local series is which Suwayomi manga (spike S1: `sourceId` plus the
// manga URL, exactly as stored, with no normalizer).

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// The id Kuchie gives a Mihon manga or chapter: the SHA-256 of its URL, as
/// `LocalSources` derives it from a runtime locator's stable part. A server
/// URL is already that stable part.
String kuchieLocatorId(String url) => SHA256Digest()
    .process(Uint8List.fromList(utf8.encode(url)))
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// A Mihon source on this iPhone is `<package>:<source id>`; the source id
/// is the one Suwayomi uses. Built-in and Kuchie repo sources have no colon.
({String package, String sourceId})? parseLocalSource(String id) {
  final colon = id.lastIndexOf(':');
  if (colon <= 0 || colon == id.length - 1) return null;
  final sourceId = id.substring(colon + 1);
  if (int.tryParse(sourceId) == null && BigInt.tryParse(sourceId) == null) {
    return null;
  }
  return (package: id.substring(0, colon), sourceId: sourceId);
}

const _chapterMarker = '|kuchie-chapter|';
const _memoMarker = '|mangayomi-memo|';

/// The manga URL in a Local locator, without Kuchie's chapter suffix or a
/// Mangayomi memo. The same as the runtime's `_stableLocator`.
String stableLocator(String locator) {
  final chapter = locator.lastIndexOf(_chapterMarker);
  final url = chapter < 0 ? locator : locator.substring(0, chapter);
  final memo = url.lastIndexOf(_memoMarker);
  return memo > 0 ? url.substring(0, memo) : url;
}

/// The built-in Shinigami adapter, which shares its package name with the
/// Mihon extension but has no Suwayomi source id.
const builtInShinigamiPackage = 'eu.kanade.tachiyomi.extension.id.shinigami';

/// A series in the Local library, as matching needs it.
class LocalSeriesRef {
  const LocalSeriesRef({
    required this.id,
    required this.title,
    this.sourceId,
    this.locator,
  });

  final String id;
  final String title;

  /// Null for imported files.
  final String? sourceId;
  final String? locator;
}

/// A manga in the server library.
class RemoteSeriesRef {
  const RemoteSeriesRef({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.url,
  });

  final int id;
  final String title;
  final String sourceId;
  final String url;
}

/// Why a Local series has no counterpart on the server, and whether it can
/// be sent there.
sealed class LocalOnlyReason {
  const LocalOnlyReason();

  bool get sendable => false;
}

/// From a CBZ or folder import; the server has no source for it.
final class ImportedFile extends LocalOnlyReason {
  const ImportedFile();
}

/// From a Kuchie repo catalog, which Suwayomi cannot read.
final class KuchieRepo extends LocalOnlyReason {
  const KuchieRepo();
}

/// From the built-in Shinigami adapter.
final class BuiltIn extends LocalOnlyReason {
  const BuiltIn();
}

/// From a Mihon extension the server doesn't have yet.
final class ExtensionMissing extends LocalOnlyReason {
  const ExtensionMissing(this.package);

  final String package;

  @override
  bool operator ==(Object other) =>
      other is ExtensionMissing && other.package == package;

  @override
  int get hashCode => package.hashCode;
}

/// Not on the server yet, but its extension is there: sync can add it.
final class Sendable extends LocalOnlyReason {
  const Sendable();

  @override
  bool get sendable => true;
}

class SeriesMatch {
  const SeriesMatch({
    required this.links,
    required this.onlyLocal,
    required this.onlyRemote,
  });

  /// Local series id → server manga id.
  final Map<String, int> links;
  final List<(LocalSeriesRef, LocalOnlyReason)> onlyLocal;

  /// With whether this iPhone has the extension to read it.
  final List<(RemoteSeriesRef, bool installedHere)> onlyRemote;
}

/// Pairs the two libraries by source id and manga URL.
///
/// [serverPackages] are the extensions installed on the server, and
/// [localSourceIds] the Suwayomi source ids this iPhone can read.
SeriesMatch matchSeries({
  required List<LocalSeriesRef> local,
  required List<RemoteSeriesRef> remote,
  required Set<String> serverPackages,
  required Set<String> localSourceIds,
}) {
  final byKey = <(String, String), RemoteSeriesRef>{
    for (final manga in remote) (manga.sourceId, manga.url): manga,
  };
  final links = <String, int>{};
  final linkedRemote = <int>{};
  final onlyLocal = <(LocalSeriesRef, LocalOnlyReason)>[];
  for (final series in local) {
    final sourceId = series.sourceId, locator = series.locator;
    if (sourceId == null || locator == null) {
      onlyLocal.add((series, const ImportedFile()));
      continue;
    }
    final parsed = parseLocalSource(sourceId);
    if (parsed == null) {
      onlyLocal.add((
        series,
        sourceId == builtInShinigamiPackage
            ? const BuiltIn()
            : const KuchieRepo(),
      ));
      continue;
    }
    final match = byKey[(parsed.sourceId, stableLocator(locator))];
    if (match != null && linkedRemote.add(match.id)) {
      links[series.id] = match.id;
    } else {
      onlyLocal.add((
        series,
        serverPackages.contains(parsed.package)
            ? const Sendable()
            : ExtensionMissing(parsed.package),
      ));
    }
  }
  return SeriesMatch(
    links: links,
    onlyLocal: onlyLocal,
    onlyRemote: [
      for (final manga in remote)
        if (!linkedRemote.contains(manga.id))
          (manga, localSourceIds.contains(manga.sourceId)),
    ],
  );
}

/// The source of a series only the sync server can read: its extension
/// isn't on this iPhone (design 3.5, "Needs server"). No colon, so it never
/// parses as a Mihon source.
const serverOnlySourceId = 'suwayomi';

const _serverOnlyPrefix = 'suwayomi-manga-';

/// The Local id of server manga [remoteId] while only the server reads it.
String serverOnlySeriesId(String remoteId) => '$_serverOnlyPrefix$remoteId';

bool isServerOnlySeriesId(String seriesId) =>
    seriesId.startsWith(_serverOnlyPrefix);

/// The server manga id of a [serverOnlySeriesId], or null.
String? serverOnlyRemoteId(String seriesId) => isServerOnlySeriesId(seriesId)
    ? seriesId.substring(_serverOnlyPrefix.length)
    : null;
