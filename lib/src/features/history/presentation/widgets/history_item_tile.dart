// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../widgets/desktop/desktop_page_frame.dart';
import '../../../../widgets/server_image.dart';
import '../../../../widgets/web_route_link.dart';
import '../../../local_collection/data/local_reading_stats.dart';
import '../../../manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import '../../../manga_book/presentation/manga_details/widgets/chapter_context_menu.dart';
import '../../domain/history_item.dart';
import 'history_row_menu.dart';

bool isHistoryChapterCompleted(HistoryItemDto item) {
  final isFullyRead = item.user.isRead == true;
  final hasFinishedChapter =
      item.pageCount > 0 && item.user.lastPageRead >= (item.pageCount - 1);
  return isFullyRead || hasFinishedChapter;
}

/// The page a reader resumes on, counted from 1; the server stores it from 0.
int historyResumePage(HistoryItemDto item) => item.user.lastPageRead + 1;

void ensureHistoryPreferenceProvidersInitialized(WidgetRef ref, int mangaId) {
  ref.read(mangaChapterSortProvider);
  ref.read(mangaChapterSortDirectionProvider);
  ref.read(mangaChapterFilterUnreadProvider);
  ref.read(mangaChapterFilterDownloadedProvider);
  ref.read(mangaChapterFilterBookmarkedProvider);
  ref.read(mangaPreferredScanlatorsProvider(mangaId: mangaId));
}

void navigateHistoryItemToReader(
  BuildContext context,
  WidgetRef ref,
  HistoryItemDto item,
) {
  // On phones the reader opens above the manga page, so Back lands on the
  // manga instead of History, as in the Local collection.
  if (!context.usesDesktopShell) {
    unawaited(MangaRoute(mangaId: item.mangaId).push<void>(context));
  }
  if (isHistoryChapterCompleted(item)) {
    navigateToNextHistoryChapterAfterLoading(context, ref, item);
  } else {
    ReaderRoute(mangaId: item.mangaId, chapterId: item.id).push(context);
  }
}

Future<void> navigateToNextHistoryChapterAfterLoading(
  BuildContext context,
  WidgetRef ref,
  HistoryItemDto item,
) async {
  final completer = Completer<void>();
  ProviderSubscription? subscription;

  void navigateAndCleanup(int chapterId) {
    if (completer.isCompleted) return;

    if (context.mounted) {
      ReaderRoute(mangaId: item.mangaId, chapterId: chapterId).push(context);
    }
    subscription?.close();
    completer.complete();
  }

  subscription = ref.listenManual(
    mangaChapterListWithFilterProvider(mangaId: item.mangaId),
    (previous, next) {
      if (next is AsyncData<List<dynamic>?>) {
        final nextPrevChapterPair = ref.read(
          getNextAndPreviousChaptersProvider(
            mangaId: item.mangaId,
            chapterId: item.id,
          ),
        );
        navigateAndCleanup(nextPrevChapterPair?.first?.id ?? item.id);
      } else if (next is AsyncError) {
        navigateAndCleanup(item.id);
      }
    },
  );

  ensureHistoryPreferenceProvidersInitialized(ref, item.mangaId);
  await ref
      .read(mangaChapterListProvider(mangaId: item.mangaId).notifier)
      .refresh();

  unawaited(
    Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 10)).then((_) {
        if (!completer.isCompleted) {
          navigateAndCleanup(item.id);
        }
      }),
    ]),
  );
}

class HistoryItemTile extends StatelessWidget {
  const HistoryItemTile({super.key, required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!context.usesDesktopShell) return _PhoneTile(item: item, onTap: onTap);
    return _DesktopTile(item: item, onTap: onTap);
  }
}

class _DesktopTile extends HookConsumerWidget {
  const _DesktopTile({required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hovered = useState(false);
    final optionsKey = useMemoized(GlobalKey.new);
    final optionsFocus = useFocusNode();
    final optionsFocused = useState(false);
    final inLibrary = item.manga.user.inLibrary;
    final completed = isHistoryChapterCompleted(item);
    final timeString = item.readAt != null
        ? DateFormat.Hm().format(item.readAt!)
        : '';

    void openMenuAt(Offset position) {
      showHistoryChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForPoint(context, position),
        item: item,
        refocus: () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    void openOptions() {
      final box = optionsKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      showHistoryChapterMenu(
        context: context,
        ref: ref,
        position: menuAnchorForRect(
          context,
          box.localToGlobal(Offset.zero) & box.size,
        ),
        item: item,
        refocus: () {
          if (context.mounted) optionsFocus.requestFocus();
        },
      );
    }

    final scheme = context.theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: WebRouteLink(
        // Completed entries load the next chapter dynamically, so they have no fixed link.
        location: completed
            ? null
            : ReaderRoute(mangaId: item.mangaId, chapterId: item.id).location,
        builder: (context, openInNewTab) => GestureDetector(
          onSecondaryTapDown: (details) => openMenuAt(details.globalPosition),
          child: MouseRegion(
            onEnter: (_) => hovered.value = true,
            onExit: (_) => hovered.value = false,
            child: InkWell(
              onTap: () => WebRouteLink.handleTap(
                openInNewTab,
                onTap ?? () => navigateHistoryItemToReader(context, ref, item),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ).onDesktopPageLine(context),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: WebRouteLink(
                        location: MangaRoute(mangaId: item.mangaId).location,
                        enabled: false,
                        builder: (context, openMangaInNewTab) => InkWell(
                          onTap: () => WebRouteLink.handleTap(
                            openMangaInNewTab,
                            () async {
                              await MangaRoute(
                                mangaId: item.mangaId,
                              ).push(context);
                              if (!context.mounted) return;
                              await refreshHistory(ref);
                            },
                          ),
                          child: ServerImage(
                            imageUrl: item.manga.displayCoverUrl,
                            fallbackImageUrl: item.manga.thumbnailUrl,
                            coverVersion: item.manga.coverVersion,
                            fallbackCoverVersion:
                                item.manga.thumbnailUrlLastFetched,
                            size: const Size(48, 68),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.manga.title,
                            style: context.theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: context.theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _ProgressLine(item: item, completed: completed),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        timeString,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: IconButtonTheme(
                        data: IconButtonThemeData(
                          style: IconButton.styleFrom(
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 32,
                              child: !inLibrary && hovered.value
                                  ? IconButton(
                                      tooltip: context.l10n.addToLibrary,
                                      onPressed: () async {
                                        await addHistorySeriesToLibrary(
                                          ref,
                                          context,
                                          item.mangaId,
                                        );
                                        if (!context.mounted) return;
                                        await refreshHistory(ref);
                                      },
                                      icon: Icon(
                                        FluentIcons.heart_24_regular,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                            ),
                            SizedBox(
                              width: 32,
                              child: Visibility(
                                visible: hovered.value || optionsFocused.value,
                                maintainSize: true,
                                maintainState: true,
                                maintainAnimation: true,
                                child: Focus(
                                  focusNode: optionsFocus,
                                  onFocusChange: (v) =>
                                      optionsFocused.value = v,
                                  child: IconButton(
                                    key: optionsKey,
                                    tooltip: context.l10n.more,
                                    onPressed: openOptions,
                                    icon: Icon(
                                      FluentIcons.more_vertical_24_regular,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.item, required this.completed});

  final HistoryItemDto item;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    if (completed) {
      return Text(
        context.l10n.historyChapterCompleted,
        style: context.theme.textTheme.labelSmall?.copyWith(
          color: scheme.secondary,
        ),
      );
    }
    if (item.user.lastPageRead <= 0 || item.pageCount <= 0) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: historyResumePage(item) / item.pageCount,
              minHeight: 3,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            context.l10n.pageOfTotal(historyResumePage(item), item.pageCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneTile extends ConsumerWidget {
  const _PhoneTile({required this.item, this.onTap});

  final HistoryItemDto item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) => HistoryRowView(
    cover: (size) => ServerImage(
      imageUrl: item.manga.displayCoverUrl,
      fallbackImageUrl: item.manga.thumbnailUrl,
      coverVersion: item.manga.coverVersion,
      fallbackCoverVersion: item.manga.thumbnailUrlLastFetched,
      size: size,
    ),
    seriesTitle: item.manga.title,
    chapterTitle: item.name,
    readAt: item.readAt,
    readingTime: LocalReadingStats.instance.timeFor(
      serverReadingKey(item.mangaId),
    ),
    linkLocation: MangaRoute(mangaId: item.mangaId).location,
    // Like Tachimanga: the row opens the series; resuming is in the sheet.
    onTap: onTap ?? () => MangaRoute(mangaId: item.mangaId).push(context),
    onLongPress: () =>
        showHistoryActionsSheet(context: context, ref: ref, item: item),
    onMore: () =>
        showHistoryActionsSheet(context: context, ref: ref, item: item),
  );
}

/// One read series in History, for every collection, laid out like
/// Tachimanga: cover, title, chapter, time spent reading and when, and a
/// remove (or more) button. The row opens the series.
class HistoryRowView extends StatelessWidget {
  const HistoryRowView({
    super.key,
    required this.cover,
    required this.seriesTitle,
    required this.chapterTitle,
    required this.onTap,
    this.readAt,
    this.readingTime = Duration.zero,
    this.onLongPress,
    this.onRemove,
    this.onMore,
    this.linkLocation,
  });

  /// Builds the cover at the given size.
  final Widget Function(Size size) cover;
  final String seriesTitle;
  final String chapterTitle;
  final VoidCallback onTap;
  final DateTime? readAt;

  /// Time spent reading this series; shown when at least a minute.
  final Duration readingTime;
  final VoidCallback? onLongPress;

  /// Shows a trash button; takes the place of [onMore].
  final VoidCallback? onRemove;
  final VoidCallback? onMore;
  final String? linkLocation;

  static const coverSize = Size(64, 92);

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final meta = context.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final readAt = this.readAt;
    Widget metaRow(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return WebRouteLink(
      location: linkLocation,
      builder: (context, openInNewTab) => InkWell(
        onTap: () => WebRouteLink.handleTap(openInNewTab, onTap),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.fromSize(
                  size: coverSize,
                  child: cover(coverSize),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seriesTitle,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chapterTitle.isNotEmpty)
                      Text(
                        chapterTitle,
                        style: meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (readingTime.inMinutes > 0)
                      metaRow(
                        FluentIcons.book_open_24_regular,
                        formatReadingTime(readingTime),
                      ),
                    if (readAt != null)
                      metaRow(
                        FluentIcons.clock_24_regular,
                        historyRelativeDay(context, readAt),
                      ),
                  ],
                ),
              ),
              if (onRemove case final remove?)
                IconButton(
                  tooltip: context.l10n.delete,
                  icon: Icon(
                    FluentIcons.delete_24_regular,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: remove,
                )
              else if (onMore case final more?)
                IconButton(
                  tooltip: context.l10n.more,
                  icon: Icon(
                    FluentIcons.more_vertical_24_regular,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: more,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", "3 days ago", or a short date, as History shows.
String historyRelativeDay(BuildContext context, DateTime at) {
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  return switch (days) {
    <= 0 => DateGroupKeys.today.toLocale(context),
    1 => DateGroupKeys.yesterday.toLocale(context),
    < 7 => context.l10n.daysAgo(days),
    _ => MaterialLocalizations.of(context).formatShortDate(at),
  };
}
