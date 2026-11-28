import 'package:graphql/client.dart';

import '../../../../utils/extensions/custom_extensions.dart';
import 'graphql/__generated__/sync.graphql.dart';
import 'suwayomi_identity.dart';

/// What the server holds, for the connect analysis.
class ServerLibrary {
  const ServerLibrary({required this.series, required this.packages});

  final List<RemoteSeriesRef> series;

  /// Package names of the extensions installed on the server.
  final Set<String> packages;
}

/// Reads the server library page by page, and its installed extensions.
/// Writes nothing.
Future<ServerLibrary> readServerLibrary(
  GraphQLClient client, {
  int pageSize = 200,
}) async {
  final series = <RemoteSeriesRef>[];
  final cursors = <int>{};
  int? after;
  while (true) {
    final page = await client
        .query$SyncLibraryPage(
          Options$Query$SyncLibraryPage(
            variables: Variables$Query$SyncLibraryPage(
              first: pageSize,
              after: after,
            ),
          ),
        )
        .getData((data) => data.mangas);
    if (page == null) throw StateError('The server sent no library page.');
    for (final manga in page.nodes) {
      if (!manga.user.inLibrary) continue;
      series.add(
        RemoteSeriesRef(
          id: manga.id,
          title: manga.title,
          sourceId: manga.sourceId,
          url: manga.url,
        ),
      );
    }
    if (!page.pageInfo.hasNextPage) break;
    after = page.pageInfo.endCursor;
    if (after == null || !cursors.add(after)) {
      throw StateError('The server repeated a library page.');
    }
  }
  final extensions = await client.query$SyncExtensions().getData(
    (data) => data.extensions.nodes,
  );
  if (extensions == null) throw StateError('The server sent no extensions.');
  return ServerLibrary(
    series: series,
    packages: {
      for (final extension in extensions)
        if (extension.isInstalled) extension.pkgName,
    },
  );
}
