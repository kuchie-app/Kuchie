import 'local_catalog.dart';
import 'local_collection_services.dart';
import 'local_sources.dart';

typedef LocalMangaUpdate = ({
  LocalExtension source,
  LocalSourceManga manga,
  int count,
});

Future<({List<LocalMangaUpdate> items, int failed})> loadLocalUpdates(
  LocalSources sources,
  List<LocalSeries> library,
) async {
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
    final latestFirst = source.chaptersNewestFirst
        ? chapters
        : chapters.reversed;
    final count = latestFirst
        .takeWhile((chapter) => !saved.contains(chapter.id))
        .length;
    return count == 0 ? null : (source: source, manga: manga, count: count);
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
