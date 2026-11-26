import 'dart:convert';

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../global_providers/global_providers.dart';
import '../../../settings/data/server_connection/server_url.dart';

/// A title with chapters saved on the server.
typedef ServerDownloadedTitle = ({
  int mangaId,
  String title,
  String? thumbnailUrl,
  int chapters,

  /// When this device saw a chapter finish, else the newest chapter's fetch
  /// time on the server.
  DateTime? downloadedAt,
});

/// When this device last saw a chapter of each title finish downloading on
/// the server, by manga id.
///
/// Suwayomi does not record when a download finishes, so the queue reports it
/// as it happens. Titles downloaded while Kuchie was closed fall back to the
/// chapter's fetch time.
class ServerDownloadHistory extends Notifier<Map<int, DateTime>> {
  static const _keyPrefix = 'server.downloads.finishedAt.';

  String get _key => '$_keyPrefix${ref.read(serverUrlProvider) ?? ''}';

  @override
  Map<int, DateTime> build() {
    ref.watch(serverUrlProvider);
    final saved = ref.read(sharedPreferencesProvider).getString(_key);
    if (saved == null) return const {};
    try {
      final map = jsonDecode(saved) as Map<String, dynamic>;
      return {
        for (final entry in map.entries)
          ?int.tryParse(entry.key): DateTime.fromMillisecondsSinceEpoch(
            entry.value as int,
          ),
      };
    } on FormatException {
      return const {};
    } on TypeError {
      return const {};
    }
  }

  /// Notes that a chapter of each of [mangaIds] just finished.
  void recordFinished(Iterable<int> mangaIds) {
    if (mangaIds.isEmpty) return;
    final now = DateTime.now();
    state = {...state, for (final id in mangaIds) id: now};
    // Keep the newest 500 so the record stays small.
    final entries = state.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final kept = entries.take(500);
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(
      _key,
      jsonEncode({
        for (final entry in kept)
          '${entry.key}': entry.value.millisecondsSinceEpoch,
      }),
    );
  }
}

final serverDownloadHistoryProvider =
    NotifierProvider<ServerDownloadHistory, Map<int, DateTime>>(
      ServerDownloadHistory.new,
    );

const _downloadedChaptersQuery = r'''
query KuchieDownloadedChapters($first: Int!) {
  chapters(
    filter: {isDownloaded: {equalTo: true}}
    orderBy: FETCHED_AT
    orderByType: DESC
    first: $first
  ) {
    nodes {
      id
      fetchedAt
      manga {
        id
        title
        thumbnailUrl
      }
    }
  }
}
''';

/// The most chapters read to build the list; enough for any real library.
const _maxChapters = 10000;

/// Titles with chapters saved on the server, newest download first.
final serverDownloadedTitlesProvider =
    FutureProvider<List<ServerDownloadedTitle>>((ref) async {
      final client = ref.watch(graphQlClientProvider);
      final result = await client.query(
        QueryOptions(
          document: gql(_downloadedChaptersQuery),
          variables: const {'first': _maxChapters},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.exception case final exception?) throw exception;
      final nodes =
          ((result.data?['chapters'] as Map<String, dynamic>?)?['nodes']
                  as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      final history = ref.watch(serverDownloadHistoryProvider);

      final titles = <int, ServerDownloadedTitle>{};
      for (final node in nodes) {
        final manga = node['manga'] as Map<String, dynamic>?;
        final id = manga?['id'] as int?;
        if (manga == null || id == null) continue;
        final fetchedSeconds = int.tryParse('${node['fetchedAt']}');
        final fetched = fetchedSeconds == null || fetchedSeconds == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(fetchedSeconds * 1000);
        final previous = titles[id];
        DateTime? newest = previous?.downloadedAt;
        if (fetched != null && (newest == null || fetched.isAfter(newest))) {
          newest = fetched;
        }
        titles[id] = (
          mangaId: id,
          title: manga['title'] as String? ?? '',
          thumbnailUrl: manga['thumbnailUrl'] as String?,
          chapters: (previous?.chapters ?? 0) + 1,
          downloadedAt: newest,
        );
      }
      final list = [
        for (final title in titles.values)
          switch (history[title.mangaId]) {
            final seen?
                when title.downloadedAt == null ||
                    seen.isAfter(title.downloadedAt!) =>
              (
                mangaId: title.mangaId,
                title: title.title,
                thumbnailUrl: title.thumbnailUrl,
                chapters: title.chapters,
                downloadedAt: seen,
              ),
            _ => title,
          },
      ];
      list.sort((a, b) {
        final left = a.downloadedAt;
        final right = b.downloadedAt;
        if (left == null || right == null) {
          return left == null ? (right == null ? 0 : 1) : -1;
        }
        return right.compareTo(left);
      });
      return list;
    });
