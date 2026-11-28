import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../local_collection/data/chapter_page_resolver.dart';
import '../../local_collection/data/local_catalog.dart';
import '../../local_collection/data/local_collection_services.dart';
import '../../local_collection/presentation/local_extension_browser.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../controller/extension_sync.dart';
import '../controller/server_only_series.dart';
import '../domain/sync_records.dart';
import 'extension_suggestions.dart';

/// Opens the page of a "Needs server" series (design 3.5).
Future<void> openServerOnlySeries(
  BuildContext context,
  LocalCollectionServices services,
  LocalSeries series,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ServerOnlySeriesScreen(services: services, series: series),
  ),
);

/// Reopens a chapter of a "Needs server" series from History.
Future<void> openServerOnlyHistoryChapter(
  BuildContext context,
  LocalCollectionServices services, {
  required LocalSeries series,
  required String chapterId,
}) async {
  final chapters = await ProviderScope.containerOf(
    context,
    listen: false,
  ).read(serverOnlySeriesProvider).chapters(series.id);
  if (!chapters.any((chapter) => chapter.id == chapterId)) {
    throw StateError('The chapter is no longer listed.');
  }
  if (!context.mounted) return;
  await openServerOnlyChapter(
    context,
    services,
    series: series,
    chapters: [
      for (final chapter in chapters) (id: chapter.id, title: chapter.title),
    ],
    initialId: chapterId,
  );
}

/// The series page for a series no extension on this iPhone reads: its
/// chapters come from the sync server, and so do their pages. Marks and
/// reading sync as for any series.
class ServerOnlySeriesScreen extends ConsumerStatefulWidget {
  const ServerOnlySeriesScreen({
    super.key,
    required this.services,
    required this.series,
  });

  final LocalCollectionServices services;
  final LocalSeries series;

  @override
  ConsumerState<ServerOnlySeriesScreen> createState() =>
      _ServerOnlySeriesScreenState();
}

typedef _Loaded = ({
  List<ServerOnlySeriesChapter> chapters,
  Map<String, ChapterState> states,
});

class _ServerOnlySeriesScreenState
    extends ConsumerState<ServerOnlySeriesScreen> {
  late Future<_Loaded> _loaded = _load();

  LocalCatalog get _catalog => widget.services.catalog;

  Future<_Loaded> _load() async {
    final (chapters, states) = await (
      ref.read(serverOnlySeriesProvider).chapters(widget.series.id),
      _catalog.syncChapterStates(widget.series.id),
    ).wait;
    return (chapters: chapters, states: states);
  }

  void _reload() => setState(() => _loaded = _load());

  Future<void> _refreshFromSource() async {
    try {
      await ref.read(serverOnlySeriesProvider).refresh(widget.series.id);
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
    if (mounted) _reload();
  }

  Future<void> _read(
    List<ServerOnlySeriesChapter> chapters,
    ServerOnlySeriesChapter chapter,
  ) async {
    await openServerOnlyChapter(
      context,
      widget.services,
      series: widget.series,
      chapters: [
        for (final entry in chapters) (id: entry.id, title: entry.title),
      ],
      initialId: chapter.id,
    );
    if (mounted) _reload();
  }

  Future<void> _mark(
    Iterable<String> chapterIds, {
    bool? read,
    bool? bookmarked,
  }) async {
    try {
      await _catalog.setChapterMarks(
        widget.series.id,
        chapterIds,
        read: read,
        bookmarked: bookmarked,
      );
    } catch (error) {
      if (mounted) localFailure(context, error);
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: detailNavigationAppBar(
      context,
      title: Text(widget.series.title),
      actions: [
        IconButton(
          tooltip: localText(context, 'Check for chapters', 'Cek chapter baru'),
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => unawaited(_refreshFromSource()),
        ),
      ],
    ),
    body: FutureBuilder<_Loaded>(
      future: _loaded,
      builder: (context, snapshot) {
        final header = _Header(
          services: widget.services,
          series: widget.series,
        );
        if (snapshot.hasError) {
          return ListView(
            children: [
              header,
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      snapshot.error is ChapterNeedsServer
                          ? localText(
                              context,
                              "Your server can't be reached. This series is read through it; it opens again once the server answers.",
                              'Server Anda tidak terjangkau. Series ini dibaca lewat server; bisa dibuka lagi setelah server menjawab.',
                            )
                          : localText(
                              context,
                              "The server couldn't list the chapters.",
                              'Server tidak bisa menampilkan daftar chapter.',
                            ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _reload,
                      child: Text(localText(context, 'Try again', 'Coba lagi')),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final loaded = snapshot.data;
        if (loaded == null) {
          return ListView(
            children: [
              header,
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        final chapters = loaded.chapters;
        // Newest first, as the other series pages.
        final newestFirst = chapters.reversed.toList();
        final nextUp = chapters
            .where((chapter) => !(loaded.states[chapter.id]?.read ?? false))
            .firstOrNull;
        return RefreshIndicator(
          onRefresh: _refreshFromSource,
          child: ListView.builder(
            itemCount: newestFirst.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    if (nextUp != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: () => unawaited(_read(chapters, nextUp)),
                          label: Text(
                            loaded.states.values.any(
                                  (state) => state.read || state.page > 0,
                                )
                                ? localText(
                                    context,
                                    'Continue: ${nextUp.title}',
                                    'Lanjutkan: ${nextUp.title}',
                                  )
                                : localText(
                                    context,
                                    'Start: ${nextUp.title}',
                                    'Mulai: ${nextUp.title}',
                                  ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        localText(
                          context,
                          chapters.length == 1
                              ? '1 chapter'
                              : '${chapters.length} chapters',
                          '${chapters.length} chapter',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                );
              }
              final chapter = newestFirst[index - 1];
              final state = loaded.states[chapter.id] ?? const ChapterState();
              return _ChapterRow(
                chapter: chapter,
                state: state,
                onOpen: () => unawaited(_read(chapters, chapter)),
                onRead: (read) => unawaited(_mark([chapter.id], read: read)),
                onBookmark: (bookmarked) =>
                    unawaited(_mark([chapter.id], bookmarked: bookmarked)),
                onReadBefore: () => unawaited(
                  _mark([
                    for (final earlier in chapters.take(
                      chapters.indexOf(chapter) + 1,
                    ))
                      earlier.id,
                  ], read: true),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class _Header extends ConsumerWidget {
  const _Header({required this.services, required this.series});

  final LocalCollectionServices services;
  final LocalSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cover = series.customCover ?? services.catalog.keptCover(series.id);
    final suggestions = ref.watch(extensionSuggestionsProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 96,
                  height: 136,
                  child: cover == null
                      ? ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.book_outlined),
                        )
                      : Image.file(cover, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(series.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const ServerOnlyBadge(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            localText(
              context,
              "This iPhone doesn't have its extension, so it is read through your server. Reading syncs as usual.",
              'Extension-nya belum ada di iPhone ini, jadi series ini dibaca lewat server Anda. Progres baca tetap tersinkron.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (suggestions != null && suggestions.toInstall.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.extension_outlined),
                onPressed: () => unawaited(
                  installExtensionsFromServer(context, suggestions),
                ),
                label: Text(
                  localText(
                    context,
                    "Install the server's extensions",
                    'Pasang extension dari server',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Needs server", on a series only the sync server reads.
class ServerOnlyBadge extends StatelessWidget {
  const ServerOnlyBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 2 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: compact ? 12 : 14,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              localText(context, 'Needs server', 'Butuh server'),
              style:
                  (compact
                          ? Theme.of(context).textTheme.labelSmall
                          : Theme.of(context).textTheme.labelMedium)
                      ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.state,
    required this.onOpen,
    required this.onRead,
    required this.onBookmark,
    required this.onReadBefore,
  });

  final ServerOnlySeriesChapter chapter;
  final ChapterState state;
  final VoidCallback onOpen;
  final ValueChanged<bool> onRead;
  final ValueChanged<bool> onBookmark;
  final VoidCallback onReadBefore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final details = [
      if (state.read)
        localText(context, 'Read', 'Dibaca')
      else if (state.page > 0)
        localText(
          context,
          'Page ${state.page + 1}',
          'Halaman ${state.page + 1}',
        ),
      if (chapter.remote.downloaded)
        localText(context, 'On the server', 'Di server'),
    ];
    return ListTile(
      title: Text(
        chapter.title,
        style: state.read ? TextStyle(color: muted) : null,
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      leading: state.bookmarked
          ? Icon(Icons.bookmark_rounded, color: theme.colorScheme.primary)
          : null,
      trailing: PopupMenuButton<String>(
        onSelected: (action) => switch (action) {
          'read' => onRead(!state.read),
          'bookmark' => onBookmark(!state.bookmarked),
          'before' => onReadBefore(),
          _ => null,
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'read',
            child: Text(
              state.read
                  ? localText(context, 'Mark as unread', 'Tandai belum dibaca')
                  : localText(context, 'Mark as read', 'Tandai dibaca'),
            ),
          ),
          PopupMenuItem(
            value: 'bookmark',
            child: Text(
              state.bookmarked
                  ? localText(context, 'Remove bookmark', 'Hapus bookmark')
                  : localText(context, 'Bookmark', 'Bookmark'),
            ),
          ),
          PopupMenuItem(
            value: 'before',
            child: Text(
              localText(
                context,
                'Mark this and earlier as read',
                'Tandai ini dan sebelumnya dibaca',
              ),
            ),
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}
