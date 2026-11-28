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

/// The server answered but couldn't open the chapter, and no extension on
/// this iPhone reads it: its source is missing on the server too, or the
/// site refused.
class ChapterServerFailed implements Exception {
  const ChapterServerFailed(this.cause);

  final Object cause;

  @override
  String toString() => '$cause';
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
    Object? serverError;
    List<LocalSourcePage>? fromServer;
    final server = this.server;
    if (server != null) {
      try {
        fromServer = await server
            .pages(seriesId, chapterId)
            .timeout(serverTimeout);
      } on TimeoutException {
        // Slow: the source still reads it.
      } catch (error) {
        // Refusing: the source still reads it.
        serverError = error;
      }
    }
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    if (extensionId == null || chapter == null) {
      throw serverError == null
          ? const ChapterNeedsServer()
          : ChapterServerFailed(serverError);
    }
    try {
      return await sources.chapterPages(extensionId, chapter);
    } on SocketException catch (error) {
      throw ChapterOffline(error);
    }
  }
}
