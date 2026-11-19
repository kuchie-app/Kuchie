import 'package:shared_preferences/shared_preferences.dart';

import 'local_catalog.dart';
import 'local_collection_services.dart';
import 'local_sources.dart';

typedef LocalMangaUpdate = ({
  LocalExtension source,
  LocalSourceManga manga,
  int count,
  String seriesId,
  List<String> chapterIds,

  /// The new chapters themselves, newest first, for a per-chapter list.
  List<LocalSourceChapter> newChapters,
});

/// The chapters each library title had when Updates last looked, so only
/// chapters a source added since then count as new, as in Mihon.
abstract interface class LocalUpdateBaseline {
  Future<Set<String>?> read(String seriesId);
  Future<void> write(String seriesId, Iterable<String> chapterIds);
}

/// Keeps the baseline in SharedPreferences.
class PreferencesUpdateBaseline implements LocalUpdateBaseline {
  const PreferencesUpdateBaseline();

  static String _key(String seriesId) => 'local.updates.known.$seriesId';

  @override
  Future<Set<String>?> read(String seriesId) async =>
      (await SharedPreferences.getInstance())
          .getStringList(_key(seriesId))
          ?.toSet();

  @override
  Future<void> write(String seriesId, Iterable<String> chapterIds) async =>
      (await SharedPreferences.getInstance()).setStringList(
        _key(seriesId),
        chapterIds.toList(growable: false),
      );
}

/// Library titles whose source has chapters the reader has not seen.
///
/// With a [baseline], a title's first check only records its chapters; later
/// checks report chapters added since, unless they are saved or read
/// ([readChapters]). Without one, every chapter newer than the newest saved
/// chapter counts.
Future<({List<LocalMangaUpdate> items, int failed})> loadLocalUpdates(
  LocalSources sources,
  List<LocalSeries> library, {
  LocalUpdateBaseline? baseline,
  Future<Set<String>> Function(String seriesId)? readChapters,
}) async {
  final books = library.where((book) => book.inLibrary).toList();
  if (books.isEmpty) return (items: <LocalMangaUpdate>[], failed: 0);
  final installed = {
    for (final source in await sources.sources())
      if (source.enabled) source.id: source,
  };
  final legacyCatalogs = <String, Future<List<LocalSourceManga>>>{};
  final updates = <LocalMangaUpdate>[];
  var failed = 0;

  Future<LocalMangaUpdate?> loadBook(LocalSeries book) async {
    final identity = parseLocalSourceSeriesId(book.id);
    if (identity == null) return null;
    final source = installed[identity.sourceId];
    if (source == null || source.catalogOrigin.toString() != identity.origin) {
      return null;
    }
    final reference =
        book.source ??
        sources.legacySeriesReference(identity.sourceId, identity.mangaId);

    final LocalSourceManga? manga;
    if (reference != null && reference.mangaId == identity.mangaId) {
      manga = sources.restoreSeries(source, reference, book.title).manga;
    } else {
      // Older installations did not persist a locator with downloaded pages.
      final catalog = await legacyCatalogs.putIfAbsent(
        source.id,
        () => sources.browse(source.id),
      );
      manga = catalog.where((item) => item.id == identity.mangaId).firstOrNull;
    }
    if (manga == null) return null;
    final chapters = await sources.chapters(source.id, manga);
    final saved = book.chapters.map((chapter) => chapter.id).toSet();
    final ids = [for (final chapter in chapters) chapter.id];
    final latestFirst = source.chaptersNewestFirst
        ? chapters
        : chapters.reversed.toList();
    final List<LocalSourceChapter> fresh;
    if (baseline != null) {
      final known = await baseline.read(book.id);
      if (known == null) {
        await baseline.write(book.id, ids);
        return null;
      }
      final read = await readChapters?.call(book.id) ?? const <String>{};
      fresh = [
        for (final chapter in latestFirst)
          if (!known.contains(chapter.id) &&
              !saved.contains(chapter.id) &&
              !read.contains(chapter.id))
            chapter,
      ];
    } else {
      fresh = latestFirst
          .takeWhile((chapter) => !saved.contains(chapter.id))
          .toList();
    }
    return fresh.isEmpty
        ? null
        : (
            source: source,
            manga: manga,
            count: fresh.length,
            seriesId: book.id,
            chapterIds: ids,
            newChapters: fresh,
          );
  }

  // Bound concurrent extension operations while keeping a slow title from
  // serializing every request in a large library.
  const concurrency = 3;
  for (var offset = 0; offset < books.length; offset += concurrency) {
    final batch = await Future.wait([
      for (final book in books.skip(offset).take(concurrency))
        loadBook(book).catchError((Object _) {
          failed++;
          return null;
        }),
    ]);
    updates.addAll(batch.nonNulls);
  }
  return (items: updates, failed: failed);
}
