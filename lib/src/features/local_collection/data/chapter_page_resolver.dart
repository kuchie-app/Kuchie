import 'dart:async';
import 'dart:io';

import 'local_sources.dart';

/// Pages of a Local series' chapter through the sync server.
abstract interface class ServerChapterPages {
  /// The pages, or null when sync is off, the series isn't linked or the
  /// server doesn't answer.
  Future<List<LocalSourcePage>?> pages(String seriesId, String chapterId);
}

/// The chapter needs the server, which can't be reached, and no extension
/// on this iPhone reads it (design 3.6).
class ChapterNeedsServer implements Exception {
  const ChapterNeedsServer();
}

/// Neither the server nor the source answered: no internet.
class ChapterOffline implements Exception {
  const ChapterOffline(this.cause);

  final Object cause;
}

/// Where a chapter's pages come from, in order, with no choice for the
/// reader (design 3.6): a copy on this iPhone (the caller's), the sync
/// server, then the extension on this iPhone.
class ChapterPageResolver {
  ChapterPageResolver({
    required this.sources,
    this.server,
    this.serverTimeout = const Duration(seconds: 3),
  });

  final LocalSources sources;
  final ServerChapterPages? server;

  /// How long the server may take before the source is asked instead.
  final Duration serverTimeout;

  Future<List<LocalSourcePage>> pages({
    required String seriesId,
    required String chapterId,
    String? extensionId,
    LocalSourceChapter? chapter,
  }) async {
    final fromServer = await _server(seriesId, chapterId);
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    if (extensionId == null || chapter == null) {
      throw const ChapterNeedsServer();
    }
    try {
      return await sources.chapterPages(extensionId, chapter);
    } on SocketException catch (error) {
      throw ChapterOffline(error);
    }
  }

  Future<List<LocalSourcePage>?> _server(
    String seriesId,
    String chapterId,
  ) async {
    final server = this.server;
    if (server == null) return null;
    try {
      return await server.pages(seriesId, chapterId).timeout(serverTimeout);
    } catch (_) {
      // Unreachable, slow or refusing: the source still reads it.
      return null;
    }
  }
}
